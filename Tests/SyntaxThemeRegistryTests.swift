import XCTest
@testable import ItsypadCore

final class SyntaxThemeRegistryTests: XCTestCase {

    func testThemeCount() {
        XCTAssertEqual(SyntaxThemeRegistry.themes.count, 9)
    }

    func testItsypadDarkResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "itsypad", isDark: true)
        XCTAssertEqual(resource, "itsypad-dark.min")
    }

    func testItsypadLightResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "itsypad", isDark: false)
        XCTAssertEqual(resource, "itsypad-light.min")
    }

    func testAtomOneDarkResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "atom-one", isDark: true)
        XCTAssertEqual(resource, "atom-one-dark.min")
    }

    func testAtomOneLightResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "atom-one", isDark: false)
        XCTAssertEqual(resource, "atom-one-light.min")
    }

    func testGitHubDarkResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "github", isDark: true)
        XCTAssertEqual(resource, "github-dark.min")
    }

    func testGitHubLightResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "github", isDark: false)
        XCTAssertEqual(resource, "github.min")
    }

    func testTokyoNightDarkResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "tokyo-night", isDark: true)
        XCTAssertEqual(resource, "tokyo-night-dark.min")
    }

    func testTokyoNightLightResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "tokyo-night", isDark: false)
        XCTAssertEqual(resource, "tokyo-night-light.min")
    }

    func testCatppuccinDarkResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "catppuccin", isDark: true)
        XCTAssertEqual(resource, "catppuccin-mocha.min")
    }

    func testCatppuccinLightResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "catppuccin", isDark: false)
        XCTAssertEqual(resource, "catppuccin-latte.min")
    }

    func testStackOverflowDarkResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "stackoverflow", isDark: true)
        XCTAssertEqual(resource, "stackoverflow-dark.min")
    }

    func testStackOverflowLightResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "stackoverflow", isDark: false)
        XCTAssertEqual(resource, "stackoverflow-light.min")
    }

    func testGruvboxDarkResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "gruvbox", isDark: true)
        XCTAssertEqual(resource, "gruvbox-dark.min")
    }

    func testGruvboxLightResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "gruvbox", isDark: false)
        XCTAssertEqual(resource, "gruvbox-light.min")
    }

    func testIntelliJDarkResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "intellij", isDark: true)
        XCTAssertEqual(resource, "androidstudio.min")
    }

    func testIntelliJLightResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "intellij", isDark: false)
        XCTAssertEqual(resource, "intellij-light.min")
    }

    func testVSDarkResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "vs", isDark: true)
        XCTAssertEqual(resource, "vs2015.min")
    }

    func testVSLightResource() {
        let resource = SyntaxThemeRegistry.cssResource(for: "vs", isDark: false)
        XCTAssertEqual(resource, "vs.min")
    }

    func testUnknownIdFallsBackToItsypadDark() {
        let resource = SyntaxThemeRegistry.cssResource(for: "nonexistent", isDark: true)
        XCTAssertEqual(resource, "itsypad-dark.min")
    }

    func testUnknownIdFallsBackToItsypadLight() {
        let resource = SyntaxThemeRegistry.cssResource(for: "nonexistent", isDark: false)
        XCTAssertEqual(resource, "itsypad-light.min")
    }
}
