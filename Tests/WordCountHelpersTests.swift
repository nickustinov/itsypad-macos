import XCTest
@testable import ItsypadCore

final class WordCountHelpersTests: XCTestCase {

    func testWordCountCountsPlainText() {
        let count = WordCountHelpers.wordCount(in: "Hello world from Itsypad")
        XCTAssertEqual(count, 4)
    }

    func testWordCountTreatsUnderscoreAsWordCharacter() {
        let count = WordCountHelpers.wordCount(in: "hello_world and hello-world")
        XCTAssertEqual(count, 4)
    }

    func testWordCountCountsUnicodeLetters() {
        let count = WordCountHelpers.wordCount(in: "café naïve résumé")
        XCTAssertEqual(count, 3)
    }

    func testWordCountIgnoresWhitespaceAndPunctuation() {
        let count = WordCountHelpers.wordCount(in: "one, two! three?   four... five")
        XCTAssertEqual(count, 5)
    }

    func testWordCountReturnsZeroForEmptyText() {
        XCTAssertEqual(WordCountHelpers.wordCount(in: ""), 0)
    }
}
