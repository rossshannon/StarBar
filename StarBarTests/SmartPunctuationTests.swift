//
//  SmartPunctuationTests.swift
//  StarBarTests
//
//  Typewriter punctuation into typographic punctuation. Pure, so it runs anywhere.
//

import XCTest
@testable import StarBar

final class SmartPunctuationTests: XCTestCase {

    // MARK: - Apostrophes, which is most of what Music's metadata has

    func testAnApostropheInAWordBecomesTypographic() {
        XCTAssertEqual("Silium's Hill".typographicPunctuation, "Silium\u{2019}s Hill")
    }

    func testAnElidedYearBecomesTypographic() {
        // "Live New Orleans '89" -- the leading mark is an elision, the same character
        XCTAssertEqual("New Orleans '89".typographicPunctuation, "New Orleans \u{2019}89")
    }

    func testSeveralApostrophesAreAllConverted() {
        XCTAssertEqual("Don't Stop 'Til You Get Enough".typographicPunctuation,
                       "Don\u{2019}t Stop \u{2019}Til You Get Enough")
    }

    // MARK: - Double quotes open and close

    func testAQuoteAtTheStartOpens() {
        XCTAssertEqual("\"Heroes\"".typographicPunctuation, "\u{201C}Heroes\u{201D}")
    }

    func testAQuoteAfterASpaceOpens() {
        XCTAssertEqual("Live \"Heroes\" Take".typographicPunctuation,
                       "Live \u{201C}Heroes\u{201D} Take")
    }

    func testAQuoteAfterABracketOpens() {
        XCTAssertEqual("(\"Live\")".typographicPunctuation, "(\u{201C}Live\u{201D})")
    }

    func testAQuoteAfterALetterCloses() {
        XCTAssertEqual("Heroes\" (Live)".typographicPunctuation, "Heroes\u{201D} (Live)")
    }

    // MARK: - Ellipsis

    func testThreeDotsBecomeOneCharacter() {
        // One character cannot be split in half by truncation, and it sets better
        XCTAssertEqual("Wait...".typographicPunctuation, "Wait\u{2026}")
    }

    func testASingleDotIsLeftAlone() {
        XCTAssertEqual("Mr. Tambourine Man".typographicPunctuation, "Mr. Tambourine Man")
    }

    func testTwoDotsAreLeftAlone() {
        XCTAssertEqual("Hmm..".typographicPunctuation, "Hmm..")
    }

    func testFourDotsBecomeAnEllipsisAndADot() {
        XCTAssertEqual("So....".typographicPunctuation, "So\u{2026}.")
    }

    // MARK: - Leaving alone what it should

    func testTextWithNoTypewriterMarksIsUnchanged() {
        let text = "Calling My Name (Live New Orleans 89)"
        XCTAssertEqual(text.typographicPunctuation, text)
    }

    func testAlreadyTypographicTextIsUnchanged() {
        let text = "Silium\u{2019}s Hill \u{201C}Live\u{201D}\u{2026}"
        XCTAssertEqual(text.typographicPunctuation, text)
    }

    func testEmptyTextIsUnchanged() {
        XCTAssertEqual("".typographicPunctuation, "")
    }

    func testAccentsAndNonLatinTextSurvive() {
        // The scan walks characters, not bytes, so a multi-byte character must not be split
        XCTAssertEqual("Björk – Jóga".typographicPunctuation, "Björk – Jóga")
        XCTAssertEqual("東京は夜の七時".typographicPunctuation, "東京は夜の七時")
        XCTAssertEqual("Café 'Bleu'".typographicPunctuation, "Café \u{2019}Bleu\u{2019}")
    }

    func testAnEmojiIsNotSplit() {
        XCTAssertEqual("Party 🎉 Don't Stop".typographicPunctuation, "Party 🎉 Don\u{2019}t Stop")
    }

    // MARK: - What it must never be used on

    func testItIsNotAppliedToTrackIdentity() {
        // A track's identity can be `name|artist|album`, and it is compared against itself.
        // Prettifying one side would stop a track matching itself, so this is display only.
        let identity = "Silium's Hill|Daniel Lanois|Calling My Name"

        XCTAssertNotEqual(identity.typographicPunctuation, identity,
                          "it does change the text, which is why identity must not go through it")
    }

}
