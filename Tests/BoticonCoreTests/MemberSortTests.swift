import XCTest
@testable import BoticonCore

final class MemberSortTests: XCTestCase {
    private func catalog(_ rows: [[String: Any]]) throws -> Catalog {
        let members = rows.map { row in
            var member: [String: Any] = ["id": row["id"]!, "name": row["name"]!,
                "aliases": [], "organization": "independent", "branch": "JP",
                "membershipStatus": "listed"]
            member["debutDate"] = row["date"]
            return member
        }
        return try JSONDecoder().decode(Catalog.self, from: JSONSerialization.data(withJSONObject:
            ["schemaVersion": 1, "source": "test", "capturedAt": "2026-10-05", "members": members]))
    }

    func testUnknownDatesStayLastInBothDateDirections() throws {
        let members = try catalog([
            ["id": "unknown", "name": "A"],
            ["id": "new", "name": "C", "date": "2024-01-01"],
            ["id": "old", "name": "B", "date": "2018-01-01"]
        ]).validated().members
        XCTAssertEqual(MemberSortOrder.debutOldest.sorted(members).map(\.id), ["old", "new", "unknown"])
        XCTAssertEqual(MemberSortOrder.debutNewest.sorted(members).map(\.id), ["new", "old", "unknown"])
        XCTAssertEqual(MemberSortOrder.name.sorted(members).map(\.id), ["unknown", "old", "new"])
        XCTAssertNil(members[0].debutDate)
        XCTAssertEqual(members[0].organizationName, "個人勢")
    }

    func testSameDayHasStableNameAndIdentityOrder() throws {
        let members = try catalog([
            ["id": "c", "name": "Z", "date": "2020-01-01"],
            ["id": "b", "name": "A", "date": "2020-01-01"],
            ["id": "a", "name": "A", "date": "2020-01-01"]
        ]).members
        for order in [MemberSortOrder.debutOldest, .debutNewest] {
            XCTAssertEqual(order.sorted(members).map(\.id), ["a", "b", "c"])
        }
    }

    func testInvalidCalendarDatesAreRejected() throws {
        for day in ["2023-02-29", "2024-13-01", "2024-1-01", "2024"] {
            let value = try catalog([["id": "a", "name": "A", "date": day]])
            XCTAssertThrowsError(try value.validated())
        }
        XCTAssertNoThrow(try catalog([["id": "a", "name": "A", "date": "2024-02-29"]]).validated())
    }
}
