import XCTest
@testable import ItsypadCore

@MainActor
final class SplitPaneTests: XCTestCase {

    // Reproduces https://github.com/nickustinov/itsypad-macos/issues/24
    // 1. Create tab with text → 2. Split right twice → 3. CMD+W twice → content should survive
    func testContentSurvivesAfterSplitRightAndClosePanes() {
        let coordinator = EditorCoordinator()

        // Start with a single new tab and type some text
        coordinator.newTab()
        guard let originalTextView = coordinator.activeTextView() else {
            XCTFail("No active text view after creating tab")
            return
        }
        originalTextView.string = "Hello, world!"

        // Remember how many panes we started with
        let initialPaneCount = coordinator.controller.allPaneIds.count
        XCTAssertEqual(initialPaneCount, 1, "Should start with 1 pane")

        // Split right twice → 3 panes, focus moves to the newest each time
        coordinator.splitRight()
        XCTAssertEqual(coordinator.controller.allPaneIds.count, 2)

        coordinator.splitRight()
        XCTAssertEqual(coordinator.controller.allPaneIds.count, 3)

        // Close the focused (rightmost) pane's tab → pane collapses
        coordinator.closeCurrentTab()
        XCTAssertEqual(coordinator.controller.allPaneIds.count, 2,
                        "Closing the only tab in a pane should collapse it")

        // Close the next focused pane's tab → pane collapses
        coordinator.closeCurrentTab()
        XCTAssertEqual(coordinator.controller.allPaneIds.count, 1,
                        "Should be back to 1 pane")

        // The original tab should still be there with its content
        guard let survivingTextView = coordinator.activeTextView() else {
            XCTFail("No active text view after closing split panes – content disappeared")
            return
        }

        XCTAssertEqual(survivingTextView.string, "Hello, world!",
                        "Original tab content should survive pane split and collapse")
        XCTAssertTrue(survivingTextView === originalTextView,
                        "Should be the exact same NSTextView instance")
    }

    // Variant: split down instead of right
    func testContentSurvivesAfterSplitDownAndClosePanes() {
        let coordinator = EditorCoordinator()

        coordinator.newTab()
        guard let originalTextView = coordinator.activeTextView() else {
            XCTFail("No active text view after creating tab")
            return
        }
        originalTextView.string = "Split down test"

        coordinator.splitDown()
        coordinator.splitDown()
        XCTAssertEqual(coordinator.controller.allPaneIds.count, 3)

        coordinator.closeCurrentTab()
        coordinator.closeCurrentTab()
        XCTAssertEqual(coordinator.controller.allPaneIds.count, 1)

        guard let survivingTextView = coordinator.activeTextView() else {
            XCTFail("Content disappeared after split-down collapse")
            return
        }
        XCTAssertEqual(survivingTextView.string, "Split down test")
    }

    // Variant: mixed splits
    func testContentSurvivesAfterMixedSplitsAndClose() {
        let coordinator = EditorCoordinator()

        coordinator.newTab()
        guard let originalTextView = coordinator.activeTextView() else {
            XCTFail("No active text view after creating tab")
            return
        }
        originalTextView.string = "Mixed split test"

        coordinator.splitRight()
        coordinator.splitDown()
        XCTAssertEqual(coordinator.controller.allPaneIds.count, 3)

        coordinator.closeCurrentTab()
        coordinator.closeCurrentTab()
        XCTAssertEqual(coordinator.controller.allPaneIds.count, 1)

        guard let survivingTextView = coordinator.activeTextView() else {
            XCTFail("Content disappeared after mixed split collapse")
            return
        }
        XCTAssertEqual(survivingTextView.string, "Mixed split test")
    }
}
