import Foundation

/// A strict, non-extracting ZIP reader. It never interprets archive paths as filesystem paths.
/// Rejects ZIP64, compression, links, extra fields, descriptors, overlaps, prepended/trailing bytes.
public struct StoredZIP: Sendable {
    private let data: Data
    private let entries: [String: Range<Int>]
    public var paths: Set<String> { Set(entries.keys) }

    public init(data: Data) throws {
        guard data.startIndex == 0, data.count >= 22, data.count <= WallpaperPack.maximumArchiveBytes else {
            throw PackError.invalid("壁紙パックは256MiB以下のZIPにしてください。")
        }
        let end = data.count - 22
        func u16(_ offset: Int) throws -> Int { Int(try Self.number(data, offset, 2)) }
        func u32(_ offset: Int) throws -> Int { Int(try Self.number(data, offset, 4)) }
        guard try u32(end) == 0x06054b50, try u16(end + 4) == 0, try u16(end + 6) == 0,
              try u16(end + 20) == 0 else { throw Self.invalid }
        let count = try u16(end + 10)
        let size = try u32(end + 12), start = try u32(end + 16)
        guard count > 1, count <= WallpaperPack.maximumWallpapers + 1,
              try u16(end + 8) == count, start + size == end else { throw Self.invalid }
        var cursor = start, nextLocal = 0
        var entries: [String: Range<Int>] = [:]
        for _ in 0..<count {
            try Task.checkCancellation()
            guard try u32(cursor) == 0x02014b50 else { throw Self.invalid }
            let flags = try u16(cursor + 8), method = try u16(cursor + 10)
            let crc = try u32(cursor + 16), compressed = try u32(cursor + 20), length = try u32(cursor + 24)
            let nameLength = try u16(cursor + 28), extra = try u16(cursor + 30), comment = try u16(cursor + 32)
            let external = try u32(cursor + 38), local = try u32(cursor + 42)
            let mode = (external >> 16) & 0xf000
            guard try u16(cursor + 6) <= 20, flags == 0 || flags == 0x800, method == 0,
                  length == compressed, length > 0, length <= WallpaperPack.maximumImageBytes,
                  nameLength > 0, nameLength <= 100, extra == 0, comment == 0,
                  try u16(cursor + 34) == 0, external & 0x10 == 0,
                  mode == 0 || mode == 0x8000,
                  local == nextLocal, cursor + 46 + nameLength <= end else { throw Self.invalid }
            let nameBytes = data.subdata(in: cursor + 46..<cursor + 46 + nameLength)
            guard nameBytes.allSatisfy({ $0 < 128 }), let name = String(data: nameBytes, encoding: .utf8),
                  name == "manifest.json" || Self.imagePath(name), entries[name] == nil else { throw Self.invalid }
            if name == "manifest.json" && length > WallpaperPack.maximumManifestBytes { throw Self.invalid }
            guard try u32(local) == 0x04034b50, try u16(local + 4) <= 20,
                  try u16(local + 6) == flags, try u16(local + 8) == method,
                  try u32(local + 14) == crc, try u32(local + 18) == compressed,
                  try u32(local + 22) == length, try u16(local + 26) == nameLength,
                  try u16(local + 28) == 0 else { throw Self.invalid }
            let from = local + 30 + nameLength, to = from + length
            guard to <= start, data.subdata(in: local + 30..<from) == nameBytes,
                  Self.crc32(data[from..<to]) == UInt32(crc) else { throw Self.invalid }
            entries[name] = from..<to
            nextLocal = to
            cursor += 46 + nameLength
        }
        guard cursor == end, nextLocal == start, entries["manifest.json"] != nil else { throw Self.invalid }
        self.data = data
        self.entries = entries
    }

    public func contents(_ path: String) throws -> Data {
        guard let range = entries[path] else { throw Self.invalid }
        return data.subdata(in: range)
    }

    private static var invalid: PackError { .invalid("ZIPの構造が不正か、BWP v1で許可されていない内容です。") }

    private static func imagePath(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "wallpapers" else { return false }
        let file = String(parts[1])
        guard file.hasSuffix(".png") || file.hasSuffix(".jpg") else { return false }
        return WallpaperPack.validID(String(file.dropLast(4)))
    }

    private static func number(_ data: Data, _ offset: Int, _ bytes: Int) throws -> UInt32 {
        guard offset >= 0, offset <= data.count - bytes else { throw invalid }
        var value: UInt32 = 0
        for i in 0..<bytes { value |= UInt32(data[offset + i]) << (8 * i) }
        return value
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 0 ? value >> 1 : (value >> 1) ^ 0xedb88320 }
        return value
    }
    public static func crc32(_ data: Data) -> UInt32 {
        var value = UInt32.max
        for byte in data { value = crcTable[Int((value ^ UInt32(byte)) & 255)] ^ (value >> 8) }
        return value ^ UInt32.max
    }
}
