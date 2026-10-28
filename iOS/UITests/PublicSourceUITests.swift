import XCTest

final class PublicSourceUITests: XCTestCase {
    @MainActor
    func testEmptySourceDistributionLaunchesAndExplainsItsScope() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.example.boticon")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.buttons["galleryFilters"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["壁紙は同梱していません"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'select-'")).count, 0)
        app.tabBars.buttons["選択中"].tap()
        XCTAssertFalse(app.buttons["nextWallpaperPreview"].isEnabled)
        app.buttons["setupWallpaperShortcut"].tap()
        XCTAssertTrue(app.staticTexts["unsignedShortcutNotice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["importWallpaperShortcut"].exists)
        app.buttons["閉じる"].tap()
        app.tabBars.buttons["このアプリ"].tap()
        XCTAssertTrue(app.staticTexts["sourceOnlyDisclosure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "privacyPolicyLink").firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
