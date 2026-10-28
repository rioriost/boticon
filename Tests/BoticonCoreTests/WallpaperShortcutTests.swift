import XCTest
@testable import BoticonCore

final class WallpaperShortcutTests: XCTestCase {
    func testShortcutNameIsOneEncodedParameterWithoutImageOrClipboardInput() throws {
        let name = " 壁紙 & input=clipboard / 毎日? "
        let id = UUID()
        let url = try XCTUnwrap(WallpaperShortcut.runURL(named: name, requestID: id))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "shortcuts")
        XCTAssertEqual(parts.host, "x-callback-url")
        XCTAssertEqual(parts.path, "/run-shortcut")
        XCTAssertEqual(parts.queryItems?.first, URLQueryItem(name: "name", value: name.trimmingCharacters(in: .whitespaces)))
        XCTAssertEqual(parts.queryItems?.count, 4)
        XCTAssertFalse(parts.queryItems!.contains { ["input", "text"].contains($0.name) })
        for result in ["success", "cancel", "error"] {
            let value = try XCTUnwrap(parts.queryItems?.first { $0.name == "x-\(result)" }?.value)
            let callback = try XCTUnwrap(URL(string: value))
            XCTAssertNotNil(WallpaperShortcut.outcome(from: callback, requestID: id))
            XCTAssertNil(WallpaperShortcut.outcome(from: callback, requestID: UUID()))
        }
        XCTAssertNil(WallpaperShortcut.runURL(named: " \n ", requestID: id))
    }

    func testCallbackRejectsWrongRouteDuplicatesAndForeignRequests() throws {
        let id = UUID()
        let request = "request=\(id.uuidString)"
        let failure = URL(string: "boticon://shortcut/error?\(request)&errorMessage=Not%20found")!
        XCTAssertEqual(WallpaperShortcut.outcome(from: failure, requestID: id), .failure("Not found"))
        for url in ["https://shortcut/error?\(request)", "boticon://other/error?\(request)",
                    "boticon://shortcut/unknown?\(request)", "boticon://shortcut/error?\(request)&\(request)",
                    "boticon://shortcut/error", "boticon://someone@shortcut/error?\(request)"] {
            XCTAssertNil(WallpaperShortcut.outcome(from: URL(string: url)!, requestID: id))
        }
    }
}
