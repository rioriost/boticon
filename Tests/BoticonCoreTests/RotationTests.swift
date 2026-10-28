import XCTest
@testable import BoticonCore

final class RotationTests: XCTestCase {
    func testOnlySelectedAndAvailableMembersCanAppear() throws {
        var state = SelectionState()
        state.selectedIDs = ["a", "missing"]
        XCTAssertEqual(try Rotation.next(availableIDs: ["a", "b"], state: state), "a")
        state.selectedIDs = ["missing"]
        XCTAssertThrowsError(try Rotation.next(availableIDs: ["a", "b"], state: state))
    }

    func testRandomAvoidsImmediateRepeat() throws {
        var state = SelectionState()
        state.selectedIDs = ["a", "b", "c"]
        state.lastID = "a"
        XCTAssertEqual(try Rotation.next(availableIDs: ["a", "b", "c"], state: state,
                                        chooseIndex: { _ in 0 }), "b")
    }

    func testSequentialWrapAndRemovedLastMember() throws {
        var state = SelectionState()
        state.selectedIDs = ["a", "b"]
        state.order = .sequential
        state.lastID = "b"
        XCTAssertEqual(try Rotation.next(availableIDs: ["b", "a", "a"], state: state), "a")
        state.lastID = "removed"
        XCTAssertEqual(try Rotation.next(availableIDs: ["b", "a"], state: state), "a")
    }

    func testStateRoundTrip() throws {
        var state = SelectionState()
        state.selectedIDs = ["sample-a", "sample-b"]
        state.frequency = .weekly
        state.anchors["sample-a"] = .lowerRight
        XCTAssertEqual(try JSONDecoder().decode(SelectionState.self,
                         from: JSONEncoder().encode(state)), state)
    }

    func testPublicCatalogStartsWithoutMembers() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf:
            root.appendingPathComponent("iOS/Boticon/Resources/catalog.json"))).validated()
        XCTAssertTrue(catalog.members.isEmpty)
        XCTAssertTrue(catalog.source.isEmpty)
        XCTAssertFalse(Catalog.safeID("../escape"))
    }
}
