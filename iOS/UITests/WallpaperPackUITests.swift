import XCTest
import UIKit
import CryptoKit

/// Uses a DEBUG-simulator-only transport with invented, runtime-generated raster data.
/// No fixture images or manifests are shipped in the app or stored in this repository.
final class WallpaperPackUITests: XCTestCase {
    @MainActor
    func testURLImportConfirmationPersistenceSelectionAndRemoval() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.example.boticon")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        let fixture = try archive()
        app.launchEnvironment["BOTICON_PACK_FIXTURE_BASE64"] = fixture.base64EncodedString()
        app.launch()
        XCTAssertTrue(app.buttons["wallpaperPacks"].waitForExistence(timeout: 30))
        app.buttons["wallpaperPacks"].tap()
        if app.staticTexts["Example Stars"].exists {
            app.staticTexts["Example Stars"].tap()
            app.buttons["deletePack"].tap()
            app.alerts.buttons["削除"].tap()
        }
        app.buttons["閉じる"].tap()
        capture(app, "01-empty-library")
        app.buttons["wallpaperPacks"].tap()
        let url = app.textFields["packURL"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap(); url.typeText("https://fixture.example.com/stars.bwp.zip")
        let hash = app.textFields["packHash"]
        hash.tap(); hash.typeText(String(repeating: "0", count: 64))
        app.buttons["checkPack"].tap()
        XCTAssertTrue(app.staticTexts["packError"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["installPack"].exists)
        hash.tap()
        hash.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64))
        app.buttons["checkPack"].tap()
        XCTAssertTrue(app.staticTexts["Example Stars"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Example creator")).firstMatch.exists)
        capture(app, "02-pack-confirmation")
        for _ in 0..<8 {
            if app.buttons["installPack"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["installPack"].exists)
        app.buttons["installPack"].tap()
        XCTAssertTrue(app.staticTexts["Example Stars"].waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        let selection = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'select-p-'")).firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        selection.tap()
        capture(app, "03-imported-library")
        app.terminate(); app.launch()
        XCTAssertTrue(selection.waitForExistence(timeout: 20))
        XCTAssertEqual(selection.value as? String, "選択中")
        app.tabBars.buttons["選択中"].tap()
        XCTAssertTrue(app.buttons["nextWallpaperPreview"].isEnabled)
        app.buttons["nextWallpaperPreview"].tap()
        XCTAssertTrue(app.buttons["完了"].waitForExistence(timeout: 5))
        app.buttons["完了"].tap()
        app.tabBars.buttons["壁紙"].tap()
        app.buttons["wallpaperPacks"].tap()
        app.staticTexts["Example Stars"].tap()
        app.buttons["パックを削除"].tap()
        app.alerts.buttons["削除"].tap()
        app.buttons["閉じる"].tap()
        XCTAssertFalse(selection.exists)
        app.tabBars.buttons["選択中"].tap()
        XCTAssertFalse(app.buttons["nextWallpaperPreview"].isEnabled)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    private func archive() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format).pngData { context in
            UIColor.darkGray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
            UIColor.cyan.setFill(); context.fill(CGRect(x: 0, y: 20, width: 10, height: 10))
        }
        let digest = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let record: [String: Any] = ["format": "boticon-wallpaper-pack", "schemaVersion": 1, "id": "example-stars",
            "revision": 1, "name": "Example Stars", "author": "Example creator", "license": "CC0-1.0",
            "wallpapers": [["id": "star", "name": "Example Star", "file": "wallpapers/star.png", "sha256": digest,
                "bytes": image.count, "width": 20, "height": 30, "mediaType": "image/png", "anchor": "lowerLeft",
                "attribution": "Original procedural test image", "aiGenerated": false]]]
        return zip([("manifest.json", try JSONSerialization.data(withJSONObject: record)), ("wallpapers/star.png", image)])
    }

    private func zip(_ rows: [(String, Data)]) -> Data {
        func int(_ value: UInt32, _ count: Int) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }) }
        func crc(_ data: Data) -> UInt32 {
            var value = UInt32.max
            for byte in data {
                value ^= UInt32(byte)
                for _ in 0..<8 { value = value & 1 == 0 ? value >> 1 : (value >> 1) ^ 0xedb88320 }
            }
            return value ^ UInt32.max
        }
        var body = Data(), central = Data()
        for (path, content) in rows {
            let name = Data(path.utf8), offset = body.count, checksum = crc(content)
            body += int(0x04034b50, 4) + int(20, 2) + int(0, 8) + int(checksum, 4)
            body += int(UInt32(content.count), 4) + int(UInt32(content.count), 4)
            body += int(UInt32(name.count), 2) + int(0, 2) + name + content
            central += int(0x02014b50, 4) + int(0x314, 2) + int(20, 2)
            central += int(0, 8) + int(checksum, 4) + int(UInt32(content.count), 4)
            central += int(UInt32(content.count), 4) + int(UInt32(name.count), 2) + int(0, 8)
            central += int(UInt32(0o100644) << 16, 4) + int(UInt32(offset), 4) + name
        }
        var end = int(0x06054b50, 4) + int(0, 4)
        end += int(UInt32(rows.count), 2) + int(UInt32(rows.count), 2)
        end += int(UInt32(central.count), 4) + int(UInt32(body.count), 4) + int(0, 2)
        return body + central + end
    }
}
