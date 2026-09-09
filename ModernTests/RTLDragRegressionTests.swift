//
//  RTLDragRegressionTests.swift
//  ModernTests
//
//  Characterization tests for specific right-to-left (Persian/Arabic) rendering
//  cases surfaced from real agent (Claude Code) output. Each test appends a line
//  like `cat` would and records its visual (drawn) order, so both regressions and
//  fixes are caught. Cases known to be WRONG today are marked and assert the
//  current behavior; when one is fixed, its assertion fails and gets updated.
//

import XCTest
@testable import iTerm2SharedARC

private class RTLDragFakeSession: FakeSession {
    private let syncConfig: VT100MutableScreenConfiguration = {
        let c = VT100MutableScreenConfiguration()
        c.sessionGuid = "RTLDragRegressionTests"
        return c
    }()
    override func screenRestore(_ state: VT100ScreenState) { screen?.restore(state) }
    override func screenUpdateDisplay(_ redraw: Bool) {
        guard let screen else { return }
        _ = screen.synchronize(withConfig: syncConfig, expect: nil, checkTriggers: .none,
                               resetOverflow: false, mutableState: screen.mutableState)
    }
}

class RTLDragRegressionTests: XCTestCase {
    private var session = RTLDragFakeSession()

    private func setBidi(_ on: Bool) {
        iTermPreferences.setBool(on, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != on && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }
    override func setUp() { super.setUp(); setBidi(true) }
    override func tearDown() { setBidi(false); super.tearDown() }

    private func makeScreen(width: Int32, height: Int32 = 4) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, m, _ in
            m.terminalEnabled = true
            m.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: height, mutableState: m)
        })
        return screen
    }

    // The visual (drawn) order of a single appended line, read via the bidi
    // reorder map the way the renderer does.
    private func visual(_ line: String, width: Int32 = 90) -> String {
        let screen = makeScreen(width: width)
        screen.performBlock(joinedThreads: { _, m, _ in
            m.appendString(atCursor: line)
            m.populateRTLStateIfNeeded()
        })
        let sca = screen.screenCharArray(forLine: 0)
        let logical = Array(sca.stringValue)
        guard let bidi = screen.bidiInfo(forLine: 0) else { return sca.stringValue }
        var s = ""
        for v in 0..<Int(bidi.numberOfCells) {
            let lg = Int(bidi.logicalForVisual(Int32(v)))
            if lg >= 0 && lg < logical.count { s.append(logical[lg]) }
        }
        return s
    }

    // Number of occupied cells (up to the last non-empty) of an appended line.
    private func cellCount(_ line: String, width: Int32 = 40) -> Int {
        let screen = makeScreen(width: width)
        screen.performBlock(joinedThreads: { _, m, _ in m.appendString(atCursor: line) })
        let sca = screen.screenCharArray(forLine: 0)
        let l = sca.line
        var last = 0
        for i in 0..<Int(sca.length) where UInt32(l[i].code) != 0 { last = i + 1 }
        return last
    }

    // Pins Detect/Justify/Isolate to the shipped defaults for the duration of
    // one closure, restoring whatever was there before.
    private func withShippedDefaults(_ body: () -> Void) {
        let d = iTermUserDefaults.userDefaults()
        let keys = ["DetectParagraphDirection", "RightJustifyRTLLines", "IsolateLatinRunsInRTL"]
        let saved = keys.map { d.object(forKey: $0) }
        keys.forEach { d.set(false, forKey: $0) }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        body()
    }

    private class PortedWrappedSelectionDelegate: NSObject, iTermSelectionDelegate {
        let width: Int32
        let bidiByLine: [Int64: BidiDisplayInfoObjc]
        init(width: Int32, bidiByLine: [Int64: BidiDisplayInfoObjc]) {
            self.width = width
            self.bidiByLine = bidiByLine
        }
        func selectionDidChange(_ selection: iTermSelection!) {}
        func liveSelectionDidEnd() {}
        func selectionAbsRangeForParenthetical(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
        func selectionAbsRangeForWord(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
        func selectionAbsRangeForSmartSelection(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
        func selectionAbsRangeForWrappedLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
        func selectionAbsRangeForLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
        func selectionRangeOfTerminalNulls(onAbsoluteLine absLineNumber: Int64) -> VT100GridRange {
            // PTYTextView returns (width, 0) for any line that has bidi info.
            return VT100GridRangeMake(width, 0)
        }
        func selectionPredecessor(of absCoord: VT100GridAbsCoord) -> VT100GridAbsCoord { VT100GridAbsCoordMake(0, 0) }
        func selectionViewportWidth() -> Int32 { width }
        func selectionTotalScrollbackOverflow() -> Int64 { 0 }
        func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet { IndexSet() }
        func selectionParagraphIsRTL(onAbsoluteLine line: Int64) -> Bool {
            return bidiByLine[line]?.paragraphIsRTL ?? false
        }
        func selectionLogicalIndexes(forVisualRange visualRange: NSRange, onAbsoluteLine line: Int64) -> IndexSet {
            guard let bidi = bidiByLine[line], let range = Range(visualRange) else {
                return IndexSet(integersIn: Range(visualRange) ?? 0..<0)
            }
            var result = IndexSet()
            for v in range {
                if v < Int(bidi.numberOfCells) {
                    result.insert(Int(bidi.logicalForVisual(Int32(v))))
                } else {
                    result.insert(v)
                }
            }
            return result
        }
    }

    func testTwoLineDragOnWrappedParagraphHighlightsContiguousSweep() {
        withShippedDefaults {
            let paragraph = "همان حالتی که فیکس‌ها برایش ساخته شده‌اند. بعد از باز کردن، این‌ها را امتحان کن:"
            let screen = makeScreen(width: 40)
            screen.performBlock(joinedThreads: { _, m, _ in
                m.appendString(atCursor: paragraph)
                m.populateRTLStateIfNeeded()
            })
            var bidiByLine = [Int64: BidiDisplayInfoObjc]()
            for row: Int64 in 0..<3 {
                if let b = screen.bidiInfo(forLine: Int32(row)) { bidiByLine[row] = b }
            }
            guard let bidi0 = bidiByLine[0], let bidi1 = bidiByLine[1] else {
                return XCTFail("wrapped paragraph must have bidi info on both rows")
            }
            let delegate = PortedWrappedSelectionDelegate(width: 40, bidiByLine: bidiByLine)
            let selection = iTermSelection()
            selection.delegate = delegate
            selection.begin(at: VT100GridAbsCoordMake(20, 0),
                            mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                            resume: false,
                            append: false)
            selection.moveEndpoint(to: VT100GridAbsCoordMake(10, 1))

            let sca1 = screen.screenCharArray(forLine: 1)
            let sel1 = IndexSet(selection.selectedIndexes(onAbsoluteLine: 1))
            let lit1 = litVisuals(forSelected: sel1, sca: sca1, bidi: bidi1)
            XCTAssertEqual(lit1, Set(0..<10),
                           "end line must light exactly visual 0..<10, got \(lit1.sorted())")

            let sca0 = screen.screenCharArray(forLine: 0)
            let sel0 = IndexSet(selection.selectedIndexes(onAbsoluteLine: 0))
            let lit0 = litVisuals(forSelected: sel0, sca: sca0, bidi: bidi0)
            XCTAssertEqual(lit0, Set(20..<40),
                           "start line must light exactly visual 20..<40, got \(lit0.sorted())")
        }
    }

    // The user's daily configuration: right-justified RTL paragraphs.
    private func withRightJustifiedConfig(_ body: () -> Void) {
        let d = iTermUserDefaults.userDefaults()
        let keys = ["DetectParagraphDirection", "RightJustifyRTLLines", "RtlParagraphMinimumWords", "IsolateLatinRunsInRTL"]
        let saved = keys.map { d.object(forKey: $0) }
        d.set(true, forKey: "DetectParagraphDirection")
        d.set(true, forKey: "RightJustifyRTLLines")
        d.set(1, forKey: "RtlParagraphMinimumWords")
        d.set(true, forKey: "IsolateLatinRunsInRTL")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        body()
    }

    // Right-to-left single-line drag and a two-line drag on right-justified
    // rows: the highlight must stay under the swept columns.
    func testDragsOnRightJustifiedRowsLightSweptColumns() {
        withRightJustifiedConfig {
            let paragraph = "غضنفر میره کتابخونه، میگه: «یه ساندویچ بدید.» کتابدار: «آقا اینجا کتابخونه‌ست!»"
            let screen = makeScreen(width: 40, height: 6)
            screen.performBlock(joinedThreads: { _, m, _ in
                m.appendString(atCursor: paragraph)
                m.populateRTLStateIfNeeded()
            })
            var bidiByLine = [Int64: BidiDisplayInfoObjc]()
            for row: Int64 in 0..<3 {
                if let b = screen.bidiInfo(forLine: Int32(row)) { bidiByLine[row] = b }
            }
            guard let bidi0 = bidiByLine[0], let bidi1 = bidiByLine[1] else {
                return XCTFail("wrapped paragraph must have bidi info on both rows")
            }
            let delegate = PortedWrappedSelectionDelegate(width: 40, bidiByLine: bidiByLine)

            // NOTE ON SEMANTICS: iTermSelection receives cell BOUNDARIES, not
            // cell indexes. The view layer rounds the click by half a cell
            // (fractionOfCharacterSelectingNextNeighbor in coordForPoint), so
            // boundary B means "between cell B-1 and cell B". A drag between
            // boundaries [lo..hi] covers cells lo..<hi.

            // Single-line drag right-to-left over content of row 0.
            let vA = Int32(bidi0.visualForLogical(3))   // near sentence start: visually right
            let vB = Int32(bidi0.visualForLogical(12))  // later logical: visually further left
            let selection = iTermSelection()
            selection.delegate = delegate
            selection.begin(at: VT100GridAbsCoordMake(max(vA, vB), 0),
                            mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                            resume: false,
                            append: false)
            selection.moveEndpoint(to: VT100GridAbsCoordMake(min(vA, vB), 0))
            let sca0 = screen.screenCharArray(forLine: 0)
            let lit = litVisuals(forSelected: IndexSet(selection.selectedIndexes(onAbsoluteLine: 0)),
                                 sca: sca0, bidi: bidi0)
            XCTAssertEqual(lit, Set(Int(min(vA, vB))..<Int(max(vA, vB))),
                           "right-to-left drag between boundaries \(min(vA, vB))..\(max(vA, vB)) lit \(lit.sorted())")

            // Two-line drag ending on row 1. The anchor row of a downward drag
            // on a right-justified RTL row opens toward its reading end (the
            // left margin, mirroring how LTR lights through the right margin);
            // the end row covers from its reading start (right margin) to the
            // pointer boundary.
            let anchor = Int32(bidi0.visualForLogical(5))
            let pointer = Int32(bidi1.visualForLogical(8))
            let selection2 = iTermSelection()
            selection2.delegate = delegate
            selection2.begin(at: VT100GridAbsCoordMake(anchor, 0),
                             mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                             resume: false,
                             append: false)
            selection2.moveEndpoint(to: VT100GridAbsCoordMake(pointer, 1))
            let sca1 = screen.screenCharArray(forLine: 1)
            let lit0 = litVisuals(forSelected: IndexSet(selection2.selectedIndexes(onAbsoluteLine: 0)),
                                  sca: sca0, bidi: bidi0)
            let lit1 = litVisuals(forSelected: IndexSet(selection2.selectedIndexes(onAbsoluteLine: 1)),
                                  sca: sca1, bidi: bidi1)
            XCTAssertEqual(lit0, Set(0..<Int(anchor)),
                           "start row opens from the anchor boundary to its reading end, lit \(lit0.sorted())")
            XCTAssertEqual(lit1, Set(Int(pointer)..<40),
                           "end row covers reading start to the pointer boundary, lit \(lit1.sorted())")
        }
    }

    // With a pre-existing subselection (append/cmd-drag, click-to-select-command
    // leftovers), selectedIndexesOnAbsoluteLine takes its slow path. The live
    // range still holds VISUAL columns and must be converted like the fast path
    // does, not treated as logical cells, which mirrors the highlight to the
    // opposite end of an RTL line.
    func testLiveDragWithExistingSubSelectionStillHighlightsSweptColumns() {
        withShippedDefaults {
            let paragraph = "همان حالتی که فیکس‌ها برایش ساخته شده‌اند. بعد از باز کردن، این‌ها را امتحان کن:"
            let screen = makeScreen(width: 40, height: 6)
            screen.performBlock(joinedThreads: { _, m, _ in
                m.appendString(atCursor: paragraph)
                m.populateRTLStateIfNeeded()
            })
            var bidiByLine = [Int64: BidiDisplayInfoObjc]()
            for row: Int64 in 0..<3 {
                if let b = screen.bidiInfo(forLine: Int32(row)) { bidiByLine[row] = b }
            }
            guard let bidi1 = bidiByLine[1] else {
                return XCTFail("wrapped paragraph must have bidi info on row 1")
            }
            let delegate = PortedWrappedSelectionDelegate(width: 40, bidiByLine: bidiByLine)
            let selection = iTermSelection()
            selection.delegate = delegate

            // Pre-existing subselection on a non-bidi row far below.
            selection.begin(at: VT100GridAbsCoordMake(0, 4),
                            mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                            resume: false,
                            append: false)
            selection.moveEndpoint(to: VT100GridAbsCoordMake(3, 4))
            selection.endLive()

            // Now a live visual drag on the bidi row, appended to the existing one.
            selection.begin(at: VT100GridAbsCoordMake(3, 1),
                            mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                            resume: false,
                            append: true)
            selection.moveEndpoint(to: VT100GridAbsCoordMake(10, 1))

            let sca1 = screen.screenCharArray(forLine: 1)
            let sel1 = IndexSet(selection.selectedIndexes(onAbsoluteLine: 1))
            let lit1 = litVisuals(forSelected: sel1, sca: sca1, bidi: bidi1)
            XCTAssertEqual(lit1, Set(3..<10),
                           "live drag over visual 3..<10 with an existing subselection must light exactly those columns, got \(lit1.sorted())")
        }
    }

    // Dragging over visual columns must light exactly those columns, on a line
    // with ZWNJs (فیکس‌ها، این‌ها) like real Claude Code output. Mimics the
    // mouse path: per dragged visual column, logicalForVisual builds the
    // selected set; the background-run builder maps it back to visual runs.
    private func litVisuals(forDragging vRange: ClosedRange<Int>,
                            sca: ScreenCharArray,
                            bidi: BidiDisplayInfoObjc) -> Set<Int> {
        var selected = IndexSet()
        for v in vRange {
            if v < Int(bidi.numberOfCells) {
                selected.insert(Int(bidi.logicalForVisual(Int32(v))))
            } else {
                selected.insert(v)
            }
        }
        return litVisuals(forSelected: selected, sca: sca, bidi: bidi)
    }

    private func litVisuals(forSelected selected: IndexSet,
                            sca: ScreenCharArray,
                            bidi: BidiDisplayInfoObjc) -> Set<Int> {
        let width = Int(sca.length)
        var anyBlink: ObjCBool = false
        guard let runs = iTermBackgroundColorRunsInLine.backgroundRuns(
            inLine: sca.line, lineLength: Int32(width), sourceLineNumber: 0,
            displayLineNumber: 0, selectedIndexes: selected,
            within: NSRange(location: 0, length: width), matches: nil,
            anyBlink: &anyBlink, y: 0, bidi: bidi, eaIndex: nil, darkMode: false) else {
            return []
        }
        var lit = Set<Int>()
        for boxed in runs.array where boxed.valuePointer.pointee.selected.boolValue {
            let r = boxed.valuePointer.pointee.visualRange
            for v in r.location..<(r.location + r.length) { lit.insert(v) }
        }
        return lit
    }

    func testDragOverZWNJLineHighlightsExactlyDraggedColumns() {
        withShippedDefaults {
            let line = "همان حالتی که فیکس‌ها برایش ساخته شده‌اند. بعد از باز کردن، این‌ها را امتحان کن:"
            let screen = makeScreen(width: 100)
            screen.performBlock(joinedThreads: { _, m, _ in
                m.appendString(atCursor: line)
                m.populateRTLStateIfNeeded()
            })
            let sca = screen.screenCharArray(forLine: 0)
            guard let bidi = screen.bidiInfo(forLine: 0) else {
                return XCTFail("ZWNJ line must produce bidi info")
            }
            var lastContent = 0
            let cells = sca.line
            for i in 0..<Int(sca.length) where cells[i].code != 0 { lastContent = i }
            // The final three content cells (ک ن :) and a mid-line word.
            for targetLogicals in [[lastContent - 2, lastContent - 1, lastContent],
                                   [10, 11, 12, 13]] {
                let visuals = targetLogicals.map { Int(bidi.visualForLogical(Int32($0))) }
                let vMin = visuals.min()!, vMax = visuals.max()!
                let lit = litVisuals(forDragging: vMin...vMax, sca: sca, bidi: bidi)
                for v in vMin...vMax {
                    XCTAssertTrue(lit.contains(v),
                                  "dragged visual column \(v) of \(vMin)...\(vMax) not highlighted")
                }
                for v in lit {
                    XCTAssertTrue(v >= vMin && v <= vMax,
                                  "column \(v) lit outside dragged span \(vMin)...\(vMax)")
                }
            }
        }
    }

    // The screenshot case: a long paragraph that soft-wraps. Bidi info is
    // computed for the joined paragraph and split per row; a drag on a
    // continuation row must light exactly the dragged columns there too.
    func testDragOnWrappedContinuationRowHighlightsExactlyDraggedColumns() {
        withShippedDefaults {
            let paragraph = "همان حالتی که فیکس‌ها برایش ساخته شده‌اند. بعد از باز کردن، این‌ها را امتحان کن:"
            let screen = makeScreen(width: 40)
            screen.performBlock(joinedThreads: { _, m, _ in
                m.appendString(atCursor: paragraph)
                m.populateRTLStateIfNeeded()
            })
            for row in 0..<2 {
                let sca = screen.screenCharArray(forLine: Int32(row))
                guard let bidi = screen.bidiInfo(forLine: Int32(row)) else {
                    continue
                }
                var lastContent = 0
                let cells = sca.line
                for i in 0..<Int(sca.length) where cells[i].code != 0 { lastContent = i }
                guard lastContent >= 4 else { continue }
                let targetLogicals = [lastContent - 3, lastContent - 2, lastContent - 1, lastContent]
                let visuals = targetLogicals.map { Int(bidi.visualForLogical(Int32($0))) }
                let vMin = visuals.min()!, vMax = visuals.max()!
                let lit = litVisuals(forDragging: vMin...vMax, sca: sca, bidi: bidi)
                for v in vMin...vMax {
                    XCTAssertTrue(lit.contains(v),
                                  "row \(row): dragged visual \(v) of \(vMin)...\(vMax) not lit")
                }
                for v in lit {
                    XCTAssertTrue(v >= vMin && v <= vMax,
                                  "row \(row): column \(v) lit outside dragged span \(vMin)...\(vMax), lut may be split wrong")
                }
            }
        }
    }

    // Same drag after the line is rewritten in place the way a TUI repaints
    // (carriage return, erase-in-line, rewrite): the refreshed bidi mapping and
    // the highlight conversion must still agree.
    func testDragAfterTUIRepaintHighlightsExactlyDraggedColumns() {
        withShippedDefaults {
            let line = "همان حالتی که فیکس‌ها برایش ساخته شده‌اند. بعد از باز کردن، این‌ها را امتحان کن:"
            let screen = makeScreen(width: 100)
            screen.performBlock(joinedThreads: { _, m, _ in
                m.appendString(atCursor: "placeholder English line first")
                m.appendCarriageReturnLineFeed()
                m.cursorUp(1, andToStartOfLine: true)
                m.eraseLine(beforeCursor: true, afterCursor: true, decProtect: false)
                m.appendString(atCursor: line)
                m.populateRTLStateIfNeeded()
            })
            let sca = screen.screenCharArray(forLine: 0)
            guard let bidi = screen.bidiInfo(forLine: 0) else {
                return XCTFail("repainted ZWNJ line must produce bidi info")
            }
            var lastContent = 0
            let cells = sca.line
            for i in 0..<Int(sca.length) where cells[i].code != 0 { lastContent = i }
            let targetLogicals = [lastContent - 2, lastContent - 1, lastContent]
            let visuals = targetLogicals.map { Int(bidi.visualForLogical(Int32($0))) }
            let vMin = visuals.min()!, vMax = visuals.max()!
            let lit = litVisuals(forDragging: vMin...vMax, sca: sca, bidi: bidi)
            XCTAssertEqual(lit, Set(vMin...vMax),
                           "repainted line: dragged \(vMin)...\(vMax), lit \(lit.sorted())")
        }
    }
}
