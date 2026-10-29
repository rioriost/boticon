import Foundation

public struct VerifiedPack: Sendable {
    public let manifest: PackManifest
    public let archiveSHA256: String
    private let archive: StoredZIP

    public init(data: Data, expectedSHA256: String? = nil) throws {
        let hash = WallpaperPack.sha256(data)
        if let expectedSHA256 {
            guard WallpaperPack.validHash(expectedSHA256), hash == expectedSHA256 else {
                throw PackError.invalid("パック全体のSHA-256が指定値と一致しません。")
            }
        }
        let archive = try StoredZIP(data: data)
        let manifest = try JSONDecoder().decode(PackManifest.self, from: archive.contents("manifest.json")).validated()
        guard archive.paths == Set(["manifest.json"] + manifest.wallpapers.map(\.file)) else {
            throw PackError.invalid("未登録のファイル、または不足している壁紙があります。")
        }
        for item in manifest.wallpapers {
            try Task.checkCancellation()
            let image = try archive.contents(item.file)
            guard image.count == item.bytes, WallpaperPack.sha256(image) == item.sha256 else {
                throw PackError.invalid("壁紙のサイズまたはSHA-256が一致しません。")
            }
            try WallpaperPack.validateImage(image, width: item.width, height: item.height, mediaType: item.mediaType)
        }
        self.manifest = manifest
        self.archive = archive
        self.archiveSHA256 = hash
    }

    func contents(_ path: String) throws -> Data { try archive.contents(path) }
}

public struct InstalledPack: Codable, Identifiable, Sendable {
    public let manifest: PackManifest
    public let source: URL
    public let archiveSHA256: String
    public let installedAt: Date
    let folder: String
    public var id: String { manifest.id }
}

/// Only the atomic index makes an installation visible. Incomplete installs never replace a valid pack.
/// Callers serialize mutations (the app uses a single MainActor-owned library).
public final class PackStore {
    public private(set) var packs: [InstalledPack] = []
    private var lookup: [String: (InstalledPack, PackWallpaper)] = [:]
    private let root: URL
    private var indexURL: URL { root.appendingPathComponent("index.json") }
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            guard data.count <= 16 * 1024 * 1024 else { throw CatalogError.corruptState }
            let records = try JSONDecoder().decode([InstalledPack].self, from: data)
            guard records.count <= 100, Set(records.map(\.id)).count == records.count else { throw CatalogError.corruptState }
            for record in records {
                _ = try record.manifest.validated()
                guard UUID(uuidString: record.folder) != nil, WallpaperPack.validHash(record.archiveSHA256),
                      PackURL.isHTTPS(record.source),
                      FileManager.default.fileExists(atPath: root.appendingPathComponent(record.folder).path) else {
                    throw CatalogError.corruptState
                }
            }
            packs = records
        }
        rebuildLookup()
        cleanup()
    }

    public func imageURL(for runtimeID: String) -> URL? {
        guard let (record, item) = lookup[runtimeID] else { return nil }
        let ext = item.mediaType == "image/png" ? "png" : "jpg"
        let url = root.appendingPathComponent(record.folder).appendingPathComponent("\(item.id).\(ext)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func wallpaper(for runtimeID: String) -> (InstalledPack, PackWallpaper)? { lookup[runtimeID] }

    private func rebuildLookup() {
        lookup = [:]
        for pack in packs {
            let prefix = "p-" + WallpaperPack.sha256(Data(pack.id.utf8)) + "-"
            for item in pack.manifest.wallpapers { lookup[prefix + item.id] = (pack, item) }
        }
    }

    public func checkInstall(_ pack: VerifiedPack, source: URL) throws {
        _ = try PackURL.validated(source.absoluteString)
        if let current = packs.first(where: { $0.id == pack.manifest.id }) {
            guard PackURL.origin(current.source) == PackURL.origin(source) else {
                throw PackError.invalid("同じIDのパックが別の配布元から追加されています。更新元を確認してください。")
            }
            guard pack.manifest.revision > current.manifest.revision else {
                throw PackError.invalid("同じ版、または古い版のパックは追加できません。")
            }
        } else if packs.count >= 100 { throw PackError.invalid("追加できるパックは100個までです。") }
        let others = packs.filter { $0.id != pack.manifest.id }
        let total = (others.flatMap { $0.manifest.wallpapers } + pack.manifest.wallpapers).reduce(0) { $0 + $1.bytes }
        guard total <= 2 * 1024 * 1024 * 1024 else { throw PackError.invalid("壁紙の保存容量の上限（2GiB）を超えます。") }
    }

    public func install(_ pack: VerifiedPack, source: URL) throws {
        try checkInstall(pack, source: source)
        let folder = UUID().uuidString
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: directory) } }
        for item in pack.manifest.wallpapers {
            let ext = item.mediaType == "image/png" ? "png" : "jpg"
            try pack.contents(item.file).write(to: directory.appendingPathComponent("\(item.id).\(ext)"), options: .atomic)
        }
        let record = InstalledPack(manifest: pack.manifest, source: source, archiveSHA256: pack.archiveSHA256,
                                   installedAt: Date(), folder: folder)
        let next = packs.filter { $0.id != record.id } + [record]
        let index = try JSONEncoder().encode(next)
        guard index.count <= 16 * 1024 * 1024 else { throw PackError.invalid("保存するカタログの容量上限を超えます。") }
        try index.write(to: indexURL, options: .atomic)
        committed = true
        packs = next
        rebuildLookup()
        cleanup()
    }

    public func remove(id: String) throws {
        let next = packs.filter { $0.id != id }
        try JSONEncoder().encode(next).write(to: indexURL, options: .atomic)
        packs = next
        rebuildLookup()
        cleanup()
    }

    private func cleanup() {
        let active = Set(packs.map(\.folder))
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if UUID(uuidString: url.lastPathComponent) != nil && !active.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
