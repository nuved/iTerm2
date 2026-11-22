//
//  BidiTableCellTests.swift
//  ModernTests
//
//  A line that holds vertical box-drawing lines is a row of a table or of
//  side-by-side panes. With the “reorder each table cell or pane on its own”
//  advanced setting, each part between dividers is reordered by itself and the
//  dividers keep their cells.
//

import XCTest
@testable import iTerm2SharedARC

class BidiTableCellTests: XCTestCase {
    private let keys = ["DetectParagraphDirection", "BidiTableCells"]

    private func withTableCells(_ enabled: Bool, _ body: () -> Void) {
        let d = iTermUserDefaults.userDefaults()
        let saved = keys.map { d.object(forKey: $0) }
        d.set(true, forKey: "DetectParagraphDirection")
        d.set(enabled, forKey: "BidiTableCells")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        body()
    }

    private func bidiInfo(_ line: String) -> BidiDisplayInfoObjc? {
        return BidiDisplayInfoObjc(screenCharArrayWithDefaultStyle(line, eol: EOL_HARD))
    }

    // Every character below is one cell wide, so a character's index is its cell.
    //                       0123456789012345678
    private let twoCells = "│ کد اصلی │ ۵ خط │"
    private let latinAndPersian = "│ Docker │ نصب شده │"

    private func visual(_ info: BidiDisplayInfoObjc, _ cells: ClosedRange<Int32>) -> [Int32] {
        return cells.map { info.visualForLogical($0) }
    }

    func testDividersKeepTheirCellsAndTextStaysInItsCell() {
        withTableCells(true) {
            guard let info = bidiInfo(twoCells) else {
                XCTFail("no bidi info")
                return
            }
            XCTAssertFalse(info.paragraphIsRTL, "the row is not justified as a right-to-left line")
            XCTAssertEqual(visual(info, 0...0) + visual(info, 10...10) + visual(info, 17...17), [0, 10, 17],
                           "dividers keep their cells")
            XCTAssertEqual(visual(info, 1...9).sorted(), Array(1...9), "the first cell's text stays inside it")
            XCTAssertEqual(visual(info, 11...16).sorted(), Array(11...16), "the second cell's text stays inside it")
        }
    }

    func testEachCellReadsRightToLeft() {
        withTableCells(true) {
            guard let info = bidiInfo(twoCells) else {
                XCTFail("no bidi info")
                return
            }
            // « کد اصلی » mirrored inside cells 1...9.
            XCTAssertEqual(visual(info, 1...9), Array((1...9).reversed()))
            // « ۵ خط » mirrored inside cells 11...16: the digit leads on the right.
            XCTAssertEqual(visual(info, 11...16), Array((11...16).reversed()))
        }
    }

    func testLatinCellIsUntouchedNextToAPersianCell() {
        withTableCells(true) {
            guard let info = bidiInfo(latinAndPersian) else {
                XCTFail("no bidi info")
                return
            }
            XCTAssertEqual(visual(info, 0...9), Array(0...9), "the Latin cell and both dividers keep their cells")
            XCTAssertEqual(visual(info, 10...18), Array((10...18).reversed()), "the Persian cell is mirrored in place")
            XCTAssertEqual(info.visualForLogical(19), 19, "the closing divider keeps its cell")
        }
    }

    func testMixedCellKeepsLatinOnTheLeftOfPersian() {
        //          0123456789012345678901234567
        let row = "│ ۵ خط در VT100Grid.m │ ۳۸ │"
        withTableCells(true) {
            guard let info = bidiInfo(row) else {
                XCTFail("no bidi info")
                return
            }
            XCTAssertEqual(visual(info, 1...21).sorted(), Array(1...21), "nothing leaves the first cell")
            XCTAssertEqual(info.visualForLogical(22), 22, "the middle divider keeps its cell")
            let v = info.visualForLogical(10)       // V
            let kh = info.visualForLogical(4)       // خ
            XCTAssertLessThan(v, kh, "in a right-to-left cell the trailing Latin word sits to the left")
            XCTAssertEqual(visual(info, 10...20), Array(visual(info, 10...10)[0]...visual(info, 20...20)[0]),
                           "the Latin word keeps its left-to-right order")
        }
    }

    func testSettingOffReordersTheWholeLine() {
        withTableCells(false) {
            guard let info = bidiInfo(twoCells) else {
                XCTFail("no bidi info")
                return
            }
            XCTAssertTrue(info.paragraphIsRTL, "probe: without the setting the row is one right-to-left line")
            XCTAssertNotEqual(info.visualForLogical(0), 0, "and its first divider moves")
        }
    }

    func testLineWithoutDividersIsUnaffected() {
        withTableCells(true) {
            XCTAssertEqual(bidiInfo("کد اصلی")?.paragraphIsRTL, true)
            XCTAssertNil(bidiInfo("plain | English"), "no right-to-left text: no bidi info")
        }
    }
}
