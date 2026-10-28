import XCTest
@testable import BoticonCore

final class WallpaperLayoutTests: XCTestCase {
    func testMiniCanvasKeepsTheLastNativePixel() {
        let points = CGSize(width: 375, height: 812)
        XCTAssertEqual(WallpaperLayout.canvas(window: points, screen: points,
            native: CGSize(width: 1080, height: 2340)), CGSize(width: 1080, height: 2340))
    }

    func testCanvasUsesWindowFractionOfTheScreen() {
        XCTAssertEqual(WallpaperLayout.canvas(window: CGSize(width: 390, height: 422),
            screen: CGSize(width: 390, height: 844), native: CGSize(width: 1170, height: 2532)),
            CGSize(width: 1170, height: 1266))
    }

    func testLeftPeekingPreservesLowerLeftForEveryAspect() {
        let source = CGSize(width: 1320, height: 2868)
        for canvas in [CGSize(width: 750, height: 1334), CGSize(width: 1170, height: 2532),
                       CGSize(width: 1600, height: 3200), CGSize(width: 2400, height: 1800)] {
            let origin = WallpaperLayout.origin(source: source, canvas: canvas, anchor: .lowerLeft)
            XCTAssertEqual(origin.x, 0)
            XCTAssertEqual(origin.y + source.height, canvas.height)
        }
    }

    func testRightPeekingPreservesLowerRightForEveryAspect() {
        let source = CGSize(width: 1320, height: 2868)
        for canvas in [CGSize(width: 750, height: 1334), CGSize(width: 1170, height: 2532),
                       CGSize(width: 1600, height: 3200), CGSize(width: 2400, height: 1800)] {
            let origin = WallpaperLayout.origin(source: source, canvas: canvas, anchor: .lowerRight)
            XCTAssertEqual(origin.x + source.width, canvas.width)
            XCTAssertEqual(origin.y + source.height, canvas.height)
        }
    }

    func testOldSelectionDataKeepsItsSelections() throws {
        let data = Data(#"{"selectedIDs":["a"],"lastID":"a","order":"random","frequency":"daily"}"#.utf8)
        let state = try JSONDecoder().decode(SelectionState.self, from: data)
        XCTAssertEqual(state.selectedIDs, ["a"])
        XCTAssertEqual(state.lastID, "a")
        XCTAssertTrue(state.anchors.isEmpty)
    }
}
