import XCTest
@testable import ItsypadCore

final class OpenNotesSearchHelpersTests: XCTestCase {
    func testMatchesReturnsTrueForEmptyQuery() {
        let tab = TabData(name: "My Note", content: "Some content")
        XCTAssertTrue(OpenNotesSearchHelpers.matches(tab, query: ""))
        XCTAssertTrue(OpenNotesSearchHelpers.matches(tab, query: "   "))
    }

    func testMatchesChecksNameAndContentCaseInsensitive() {
        let tab = TabData(name: "Project Notes", content: "TODO: Fix API rate limits")

        XCTAssertTrue(OpenNotesSearchHelpers.matches(tab, query: "project"))
        XCTAssertTrue(OpenNotesSearchHelpers.matches(tab, query: "RATE"))
    }

    func testMatchesSupportsDiacriticInsensitiveSearch() {
        let tab = TabData(name: "Réunion notes", content: "Résumé and coöperate")

        XCTAssertTrue(OpenNotesSearchHelpers.matches(tab, query: "reunion"))
        XCTAssertTrue(OpenNotesSearchHelpers.matches(tab, query: "resume"))
        XCTAssertTrue(OpenNotesSearchHelpers.matches(tab, query: "cooperate"))
    }

    func testFilteredTabsReturnsAllTabsForEmptyQuery() {
        let tabs = [
            TabData(name: "Alpha", content: "one"),
            TabData(name: "Beta", content: "two"),
            TabData(name: "Gamma", content: "three"),
        ]
        XCTAssertEqual(OpenNotesSearchHelpers.filteredTabs(tabs, query: ""), tabs)
    }

    func testFilteredTabsFiltersByNameOrContent() {
        let tabs = [
            TabData(name: "Ideas", content: "shopping list"),
            TabData(name: "Journal", content: "morning reflections"),
            TabData(name: "Meeting", content: "design review"),
            TabData(name: "Ideas for launch", content: "notes"),
        ]

        let actual = OpenNotesSearchHelpers.filteredTabs(tabs, query: "idea")

        XCTAssertEqual(actual, [tabs[0], tabs[3]])
    }
}
