import Foundation

public struct Catalog: Codable, Sendable {
    public let schemaVersion: Int
    public let source: String
    public let capturedAt: String
    public let members: [Member]

    public func validated() throws -> Catalog {
        guard schemaVersion == 1, Set(members.map(\.id)).count == members.count,
              members.allSatisfy({ Self.safeID($0.id) && ($0.debutDate.map(Self.validDate) ?? true) }) else {
            throw CatalogError.invalidCatalog
        }
        return self
    }

    public static func safeID(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            (97...122).contains($0.value) || (48...57).contains($0.value) || $0 == "-"
        }
    }

    private static func validDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard value.count == 10, let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

public struct Member: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let organization: String
    public let branch: String
    public let membershipStatus: String
    public let officialProfileURL: URL?
    public let debutDate: String?

    public var organizationName: String { organization == "independent" ? "個人勢" : organization }

    public var statusName: String {
        switch membershipStatus {
        case "listed": "名簿掲載"
        case "graduated": "卒業"
        case "former": "元所属"
        case "streaming_ended": "配信活動終了"
        default: membershipStatus
        }
    }

    public func matches(_ query: String) -> Bool {
        query.isEmpty || [name, organizationName, branch, aliases.joined(separator: " ")]
            .contains { $0.localizedStandardContains(query) }
    }
}

public enum MemberSortOrder: String, CaseIterable, Sendable {
    case debutOldest, debutNewest, name

    public var title: String {
        switch self {
        case .debutOldest: "デビューが古い順"
        case .debutNewest: "デビューが新しい順"
        case .name: "名前順"
        }
    }

    public func sorted(_ members: [Member]) -> [Member] {
        members.sorted { left, right in
            if self != .name {
                switch (left.debutDate, right.debutDate) {
                case let (a?, b?) where a != b:
                    return self == .debutOldest ? a < b : a > b
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            }
            let comparison = left.name.localizedStandardCompare(right.name)
            return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
        }
    }
}

public enum CatalogError: Error, LocalizedError {
    case invalidCatalog
    case noWallpapers
    case corruptState

    public var errorDescription: String? {
        switch self {
        case .invalidCatalog: "名簿の形式を確認できませんでした。"
        case .noWallpapers: "完成した壁紙を取り込み、切り替えるメンバーを選択してください。"
        case .corruptState: "保存データを読み込めませんでした。データを保護するため更新を停止しました。"
        }
    }
}
