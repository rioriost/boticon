import Foundation
import CryptoKit
import ImageIO

public enum PackError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        if case let .invalid(reason) = self { return reason }
        return nil
    }
}

/// BWP v1 deliberately supports only stored ZIP entries: PNG/JPEG are already compressed.
public enum WallpaperPack {
    public static let maximumArchiveBytes = 256 * 1024 * 1024
    public static let maximumImageBytes = 20 * 1024 * 1024
    public static let maximumManifestBytes = 1024 * 1024
    public static let maximumWallpapers = 500

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func validHash(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    public static func validID(_ value: String) -> Bool {
        value.count <= 64 && Catalog.safeID(value) && value.first != "-" && value.last != "-"
    }

    public static func text(_ value: String, max: Int = 200) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= max
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0 != "\n" }
    }

    /// Only raster PNG/JPEG, one frame, with a bounded, fully decodable pixel buffer.
    public static func validateImage(_ data: Data, width: Int, height: Int, mediaType: String) throws {
        guard data.count <= maximumImageBytes, width > 0, height > 0,
              width <= 8192, height <= 8192, width * height <= 24_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              type == (mediaType == "image/png" ? "public.png" : "public.jpeg"),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? Int) == width,
              (properties[kCGImagePropertyPixelHeight] as? Int) == height,
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width == width, image.height == height,
              CGImageSourceGetStatus(source) == .statusComplete else {
            throw PackError.invalid("画像の形式・サイズを確認できませんでした。")
        }
    }
}

public struct PackManifest: Codable, Sendable {
    public let format: String
    public let schemaVersion: Int
    public let id: String
    public let revision: Int
    public let name: String
    public let author: String
    public let license: String
    public let homepage: URL?
    public let wallpapers: [PackWallpaper]

    public func validated() throws -> Self {
        guard format == "boticon-wallpaper-pack", schemaVersion == 1,
              WallpaperPack.validID(id), revision > 0,
              WallpaperPack.text(name), WallpaperPack.text(author), WallpaperPack.text(license, max: 4000),
              homepage.map({ PackURL.isHTTPS($0) }) ?? true,
              (1...WallpaperPack.maximumWallpapers).contains(wallpapers.count),
              Set(wallpapers.map(\.id)).count == wallpapers.count,
              Set(wallpapers.map(\.file)).count == wallpapers.count else {
            throw PackError.invalid("対応していないマニフェスト、または重複した壁紙です。")
        }
        for item in wallpapers { try item.validate() }
        // Reuse the calendar validation used by the catalog.
        _ = try Catalog(schemaVersion: 1, source: "", capturedAt: "", members: members).validated()
        return self
    }

    /// Runtime IDs are pack-scoped; the manifest's original id remains unchanged.
    public func runtimeID(_ item: PackWallpaper) -> String {
        "p-" + WallpaperPack.sha256(Data(id.utf8)) + "-" + item.id
    }

    public var members: [Member] {
        wallpapers.map { item in
            Member(id: runtimeID(item), name: item.name, aliases: item.aliases ?? [],
                   organization: item.organization ?? "未分類", branch: "", membershipStatus: "listed",
                   officialProfileURL: nil, debutDate: item.debutDate)
        }
    }
}

public struct PackWallpaper: Codable, Sendable {
    public let id: String
    public let name: String
    public let file: String
    public let sha256: String
    public let bytes: Int
    public let width: Int
    public let height: Int
    public let mediaType: String
    public let anchor: WallpaperAnchor
    public let organization: String?
    public let aliases: [String]?
    public let debutDate: String?
    public let attribution: String
    public let aiGenerated: Bool

    func validate() throws {
        let suffix = mediaType == "image/png" ? ".png" : ".jpg"
        guard WallpaperPack.validID(id), WallpaperPack.text(name),
              file == "wallpapers/\(id)\(suffix)",
              ["image/png", "image/jpeg"].contains(mediaType),
              WallpaperPack.validHash(sha256), bytes > 0, bytes <= WallpaperPack.maximumImageBytes,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 24_000_000,
              WallpaperPack.text(attribution, max: 4000),
              organization.map({ WallpaperPack.text($0) }) ?? true,
              (aliases?.count ?? 0) <= 20,
              aliases?.allSatisfy({ WallpaperPack.text($0) }) ?? true else {
            throw PackError.invalid("壁紙のファイル名・チェックサム・メタデータが不正です。")
        }
    }
}

public enum PackURL {
    public static func isHTTPS(_ url: URL) -> Bool {
        guard url.absoluteString.count <= 4096, url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443 else { return false }
        return true
    }

    public static func validated(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), isHTTPS(url),
              let rawHost = url.host?.lowercased() else {
            throw PackError.invalid("認証情報を含まない、公開配布元のHTTPS URLを入力してください。")
        }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host.contains("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              host != "localhost", !host.contains(":"),
              !host.allSatisfy({ $0.isNumber || $0 == "." }) else {
            throw PackError.invalid("認証情報を含まない、公開配布元のHTTPS URLを入力してください。")
        }
        return url
    }

    public static func origin(_ url: URL) -> String {
        "https://" + (url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? "")
    }
}
