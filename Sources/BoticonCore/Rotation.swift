import Foundation

public enum RotationOrder: String, Codable, CaseIterable, Sendable {
    case random, sequential
    public var title: String { self == .random ? "ランダム" : "リスト順" }
}

public enum RotationFrequency: String, Codable, CaseIterable, Sendable {
    case hourly, daily, weekly
    public var title: String {
        switch self { case .hourly: "毎時"; case .daily: "毎日"; case .weekly: "毎週" }
    }
}

public struct SelectionState: Codable, Sendable, Equatable {
    public var selectedIDs: Set<String> = []
    public var lastID: String?
    public var order: RotationOrder = .random
    public var frequency: RotationFrequency = .daily
    public var anchors: [String: WallpaperAnchor] = [:]
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case selectedIDs, lastID, order, frequency, anchors
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectedIDs = try values.decode(Set<String>.self, forKey: .selectedIDs)
        lastID = try values.decodeIfPresent(String.self, forKey: .lastID)
        order = try values.decode(RotationOrder.self, forKey: .order)
        frequency = try values.decode(RotationFrequency.self, forKey: .frequency)
        anchors = try values.decodeIfPresent([String: WallpaperAnchor].self, forKey: .anchors) ?? [:]
    }
}

public enum Rotation {
    /// No fallback to an unselected member. Missing files never enter the pool.
    public static func next(availableIDs: [String], state: SelectionState,
                            chooseIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) throws -> String {
        let pool = Array(Set(availableIDs).intersection(state.selectedIDs)).sorted()
        guard !pool.isEmpty else { throw CatalogError.noWallpapers }
        if state.order == .sequential {
            guard let last = state.lastID, let index = pool.firstIndex(of: last) else { return pool[0] }
            return pool[(index + 1) % pool.count]
        }
        let candidates = pool.count > 1 ? pool.filter { $0 != state.lastID } : pool
        return candidates[chooseIndex(candidates.count)]
    }
}
