//
//  RTLParagraphDirectionRuleTests.swift
//  ModernTests
//
//  The paragraph-direction rules behind “auto-detect each line’s writing
//  direction”: first-strong by default, refined by the two advanced settings
//  that set a minimum number of right-to-left words for a line that starts
//  with a Latin word and for a line that starts with a right-to-left word.
//

import XCTest
@testable import iTerm2SharedARC

class RTLParagraphDirectionRuleTests: XCTestCase {
    private let keys = ["DetectParagraphDirection",
                        "RtlParagraphMinimumWords",
                        "RtlParagraphMinimumWordsForRTLOpeningLines"]

    // Runs `body` with the given minimums and auto-detect on, then restores
    // whatever the test defaults domain held before.
    private func withMinimums(latinOpening: Int,
                              rtlOpening: Int,
                              detect: Bool = true,
                              _ body: () -> Void) {
        let d = iTermUserDefaults.userDefaults()
        let saved = keys.map { d.object(forKey: $0) }
        d.set(detect, forKey: "DetectParagraphDirection")
        d.set(latinOpening, forKey: "RtlParagraphMinimumWords")
        d.set(rtlOpening, forKey: "RtlParagraphMinimumWordsForRTLOpeningLines")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        body()
    }

    private func isRTL(_ line: String, file: StaticString = #filePath, fileLine: UInt = #line) -> Bool {
        let sca = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
        guard let info = BidiDisplayInfoObjc(sca) else {
            XCTFail("no bidi info for «\(line)»", file: file, line: fileLine)
            return false
        }
        return info.paragraphIsRTL
    }

    // A shell prompt followed by three Persian words: opens LTR, RTL words = 3.
    private let promptWithThreeRTLWords = "novid@mac ~ % سلام دنیای زیبا"
    // An English sentence quoting one Persian word: opens LTR, RTL words = 1.
    private let englishWithOneRTLWord = "The word سلام means hello in Persian."
    // Persian opening, two RTL words, then an English tail.
    private let persianOpeningTwoWords = "سلام دنیا means hello world"
    // Persian opening, five RTL words (ZWNJ inside دانش‌آموزان counts once).
    private let persianOpeningFiveWords = "دانش‌آموزان کلاس ما امروز آمدند to school"

    func testDefaultIsPureFirstStrong() {
        withMinimums(latinOpening: 0, rtlOpening: 0) {
            XCTAssertFalse(isRTL(promptWithThreeRTLWords), "opens LTR, stays LTR")
            XCTAssertFalse(isRTL(englishWithOneRTLWord), "opens LTR, stays LTR")
            XCTAssertTrue(isRTL(persianOpeningTwoWords), "opens RTL, is RTL")
            XCTAssertTrue(isRTL(persianOpeningFiveWords), "opens RTL, is RTL")
        }
    }

    func testLatinOpeningMinimumFlipsAtTheThreshold() {
        withMinimums(latinOpening: 3, rtlOpening: 0) {
            XCTAssertTrue(isRTL(promptWithThreeRTLWords), "three RTL words meet a minimum of 3")
            XCTAssertFalse(isRTL(englishWithOneRTLWord), "one RTL word is below a minimum of 3")
            XCTAssertTrue(isRTL(persianOpeningTwoWords), "the Latin-opening minimum does not touch RTL-opening lines")
        }
        withMinimums(latinOpening: 1, rtlOpening: 0) {
            XCTAssertTrue(isRTL(englishWithOneRTLWord), "one RTL word meets a minimum of 1")
        }
    }

    func testRTLOpeningMinimumKeepsShortRTLOpeningLinesLTR() {
        withMinimums(latinOpening: 0, rtlOpening: 3) {
            XCTAssertFalse(isRTL(persianOpeningTwoWords), "opens RTL with two words, below a minimum of 3")
            XCTAssertTrue(isRTL(persianOpeningFiveWords), "opens RTL with five words, meets a minimum of 3")
            XCTAssertFalse(isRTL(promptWithThreeRTLWords), "the RTL-opening minimum does not touch Latin-opening lines")
        }
    }

    func testRTLOpeningMinimumOfOneEqualsFirstStrong() {
        withMinimums(latinOpening: 0, rtlOpening: 1) {
            XCTAssertTrue(isRTL(persianOpeningTwoWords), "a minimum of 1 is always met by an RTL-opening line")
            XCTAssertFalse(isRTL(promptWithThreeRTLWords), "opens LTR: LTR")
        }
    }

    func testBothMinimumsApplyToTheirOwnKindOfLine() {
        withMinimums(latinOpening: 2, rtlOpening: 3) {
            XCTAssertTrue(isRTL(promptWithThreeRTLWords), "Latin-opening with three RTL words meets its minimum of 2")
            XCTAssertFalse(isRTL(englishWithOneRTLWord), "Latin-opening with one RTL word is below its minimum of 2")
            XCTAssertFalse(isRTL(persianOpeningTwoWords), "RTL-opening with two words is below its minimum of 3")
            XCTAssertTrue(isRTL(persianOpeningFiveWords), "RTL-opening with five words meets its minimum of 3")
        }
    }

    func testZWNJAndMarksDoNotSplitAWord() {
        // «دانش‌آموزان» holds a ZWNJ and «کاملاً» a combining fathatan; each is one word.
        withMinimums(latinOpening: 3, rtlOpening: 0) {
            XCTAssertFalse(isRTL("ok دانش‌آموزان کاملاً"), "two RTL words, not four, below a minimum of 3")
        }
        withMinimums(latinOpening: 2, rtlOpening: 0) {
            XCTAssertTrue(isRTL("ok دانش‌آموزان کاملاً"), "two RTL words meet a minimum of 2")
        }
    }

    func testDetectionOffMeansLTR() {
        withMinimums(latinOpening: 1, rtlOpening: 0, detect: false) {
            XCTAssertFalse(isRTL(persianOpeningFiveWords), "rules only apply when auto-detect is on")
        }
    }
}
