//
//  RTLParagraphDirectionRuleTests.swift
//  ModernTests
//
//  The paragraph-direction rules behind “auto-detect paragraph writing
//  direction”: first-strong by default, refined by the optional advanced
//  settings “minimum right-to-left words” and “keep lines that start with a
//  Latin word left-to-right”.
//

import XCTest
@testable import iTerm2SharedARC

class RTLParagraphDirectionRuleTests: XCTestCase {
    private let keys = ["DetectParagraphDirection",
                        "RtlParagraphMinimumWords",
                        "RtlParagraphLatinFirstWordStaysLTR"]

    // Runs `body` with the given rule configuration and auto-detect on, then
    // restores whatever the test defaults domain held before.
    private func withRules(minimumWords: Int,
                           latinFirstWordStaysLTR: Bool,
                           _ body: () -> Void) {
        let d = iTermUserDefaults.userDefaults()
        let saved = keys.map { d.object(forKey: $0) }
        d.set(true, forKey: "DetectParagraphDirection")
        d.set(minimumWords, forKey: "RtlParagraphMinimumWords")
        d.set(latinFirstWordStaysLTR, forKey: "RtlParagraphLatinFirstWordStaysLTR")
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
        withRules(minimumWords: 0, latinFirstWordStaysLTR: false) {
            XCTAssertFalse(isRTL(promptWithThreeRTLWords), "opens LTR, stays LTR")
            XCTAssertFalse(isRTL(englishWithOneRTLWord), "opens LTR, stays LTR")
            XCTAssertTrue(isRTL(persianOpeningTwoWords), "opens RTL, is RTL")
            XCTAssertTrue(isRTL(persianOpeningFiveWords), "opens RTL, is RTL")
        }
    }

    func testMinimumWordsFlipsLatinOpeningLinesAtTheThreshold() {
        withRules(minimumWords: 3, latinFirstWordStaysLTR: false) {
            XCTAssertTrue(isRTL(promptWithThreeRTLWords), "three RTL words meet a minimum of 3")
            XCTAssertFalse(isRTL(englishWithOneRTLWord), "one RTL word is below a minimum of 3")
            XCTAssertTrue(isRTL(persianOpeningTwoWords),
                          "a line that opens RTL stays RTL below the minimum when the Latin-first rule is off")
        }
        withRules(minimumWords: 1, latinFirstWordStaysLTR: false) {
            XCTAssertTrue(isRTL(englishWithOneRTLWord), "one RTL word meets a minimum of 1")
        }
    }

    func testLatinFirstWordStaysLTRIgnoresTheMinimum() {
        withRules(minimumWords: 1, latinFirstWordStaysLTR: true) {
            XCTAssertFalse(isRTL(promptWithThreeRTLWords), "Latin first word wins over three RTL words")
            XCTAssertFalse(isRTL(englishWithOneRTLWord), "Latin first word wins over one RTL word")
        }
    }

    func testLatinFirstRuleAloneKeepsRTLOpeningLinesRTL() {
        withRules(minimumWords: 0, latinFirstWordStaysLTR: true) {
            XCTAssertTrue(isRTL(persianOpeningTwoWords), "opens RTL, no minimum: RTL")
            XCTAssertFalse(isRTL(promptWithThreeRTLWords), "opens LTR: LTR")
        }
    }

    func testBothRulesApplyTheMinimumOnlyToRTLOpeningLines() {
        withRules(minimumWords: 3, latinFirstWordStaysLTR: true) {
            XCTAssertFalse(isRTL(persianOpeningTwoWords), "opens RTL with two words, below a minimum of 3")
            XCTAssertTrue(isRTL(persianOpeningFiveWords), "opens RTL with five words, meets a minimum of 3")
            XCTAssertFalse(isRTL(promptWithThreeRTLWords), "opens LTR: always LTR under the Latin-first rule")
        }
    }

    func testZWNJAndMarksDoNotSplitAWord() {
        // «دانش‌آموزان» holds a ZWNJ and «کاملاً» a combining fathatan; each is one word.
        withRules(minimumWords: 3, latinFirstWordStaysLTR: false) {
            XCTAssertFalse(isRTL("ok دانش‌آموزان کاملاً"), "two RTL words, not four, below a minimum of 3")
        }
        withRules(minimumWords: 2, latinFirstWordStaysLTR: false) {
            XCTAssertTrue(isRTL("ok دانش‌آموزان کاملاً"), "two RTL words meet a minimum of 2")
        }
    }

    func testDetectionOffMeansLTR() {
        let d = iTermUserDefaults.userDefaults()
        let saved = keys.map { d.object(forKey: $0) }
        d.set(false, forKey: "DetectParagraphDirection")
        d.set(1, forKey: "RtlParagraphMinimumWords")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        XCTAssertFalse(isRTL(persianOpeningFiveWords), "rules only apply when auto-detect is on")
    }
}
