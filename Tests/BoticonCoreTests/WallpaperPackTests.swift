import XCTest
import ImageIO
@testable import BoticonCore

final class WallpaperPackTests: XCTestCase {
    private func png() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 3, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func manifest(image: Data, id: String = "sample", revision: Int = 1) -> [String: Any] {
        ["format": "boticon-wallpaper-pack", "schemaVersion": 1, "id": id, "revision": revision,
         "name": "Sample pack", "author": "Example author", "license": "CC0-1.0",
         "wallpapers": [["id": "star", "name": "Star", "file": "wallpapers/star.png",
            "sha256": WallpaperPack.sha256(image), "bytes": image.count, "width": 2, "height": 3,
            "mediaType": "image/png", "anchor": "lowerLeft", "attribution": "Original example", "aiGenerated": false]]]
    }

    /// Independent ZIP fixture writer; exercises local/central records and malicious metadata.
    private func zip(_ rows: [(String, Data)], method: UInt16 = 0, flags: UInt16 = 0, mode: UInt32 = 0o100644) -> Data {
        func int(_ value: UInt32, _ count: Int) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }) }
        var body = Data(), central = Data()
        for (path, content) in rows {
            let name = Data(path.utf8), offset = body.count, crc = StoredZIP.crc32(content)
            body += int(0x04034b50, 4) + int(20, 2) + int(UInt32(flags), 2) + int(UInt32(method), 2)
            body += int(0, 4) + int(crc, 4) + int(UInt32(content.count), 4) + int(UInt32(content.count), 4)
            body += int(UInt32(name.count), 2) + int(0, 2) + name + content
            central += int(0x02014b50, 4) + int(0x314, 2) + int(20, 2) + int(UInt32(flags), 2) + int(UInt32(method), 2)
            central += int(0, 4) + int(crc, 4) + int(UInt32(content.count), 4) + int(UInt32(content.count), 4)
            central += int(UInt32(name.count), 2) + int(0, 8) + int(mode << 16, 4) + int(UInt32(offset), 4) + name
        }
        let end = int(0x06054b50, 4) + int(0, 4) + int(UInt32(rows.count), 2) + int(UInt32(rows.count), 2)
            + int(UInt32(central.count), 4) + int(UInt32(body.count), 4) + int(0, 2)
        return body + central + end
    }

    private func archive(id: String = "sample", revision: Int = 1, edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        let image = try png()
        var record = manifest(image: image, id: id, revision: revision)
        edit(&record)
        return zip([("manifest.json", try JSONSerialization.data(withJSONObject: record)), ("wallpapers/star.png", image)])
    }

    func testVerifiedPackAndIndependentArchiveHash() throws {
        let data = try archive()
        let result = try VerifiedPack(data: data, expectedSHA256: WallpaperPack.sha256(data))
        XCTAssertEqual(result.manifest.wallpapers.count, 1)
        XCTAssertThrowsError(try VerifiedPack(data: data, expectedSHA256: String(repeating: "0", count: 64)))
        XCTAssertThrowsError(try VerifiedPack(data: data, expectedSHA256: "bad"))
    }

    func testImageHashSizeDimensionsAndDateMustMatch() throws {
        for change in [["sha256": String(repeating: "0", count: 64)], ["bytes": 1], ["width": 8193],
                       ["width": 3], ["height": Int.max], ["debutDate": "2023-02-29"],
                       ["mediaType": "image/svg+xml"], ["file": "../star.png"]] as [[String: Any]] {
            let data = try archive { record in
                var items = record["wallpapers"] as! [[String: Any]]
                items[0].merge(change) { _, new in new }
                record["wallpapers"] = items
            }
            XCTAssertThrowsError(try VerifiedPack(data: data), "\(change)")
        }
    }

    func testUndecodableImageEvenWithMatchingHashIsRejected() throws {
        let image = Data("not an image".utf8)
        let record = manifest(image: image)
        let data = zip([("manifest.json", try JSONSerialization.data(withJSONObject: record)), ("wallpapers/star.png", image)])
        XCTAssertThrowsError(try VerifiedPack(data: data))
    }

    func testZIPRejectsTraversalAbsoluteCaseDuplicateAndUnlistedFiles() throws {
        let image = try png(), record = try JSONSerialization.data(withJSONObject: manifest(image: png()))
        for path in ["../star.png", "/wallpapers/star.png", "wallpapers/../star.png", "wallpapers\\star.png",
                     "Wallpapers/star.png", "wallpapers/.hidden.png", "script.js", "manifest.json"] {
            XCTAssertThrowsError(try VerifiedPack(data: zip([("manifest.json", record), (path, image)])), path)
        }
        XCTAssertThrowsError(try VerifiedPack(data: zip([("manifest.json", record), ("wallpapers/star.png", image), ("wallpapers/extra.png", image)])))
    }

    func testZIPRejectsLinksEncryptionCompressionAndDescriptors() throws {
        let rows = [("manifest.json", Data("{}".utf8)), ("wallpapers/star.png", Data([1]))]
        XCTAssertThrowsError(try StoredZIP(data: zip(rows, mode: 0o120777)))
        XCTAssertThrowsError(try StoredZIP(data: zip(rows, mode: 0o040755)))
        XCTAssertThrowsError(try StoredZIP(data: zip(rows, method: 8)))
        XCTAssertThrowsError(try StoredZIP(data: zip(rows, flags: 1)))
        XCTAssertThrowsError(try StoredZIP(data: zip(rows, flags: 8)))
    }

    func testZIPRejectsTruncationTamperingAndTrailingData() throws {
        let data = try archive()
        for length in [0, 5, 21, data.count - 1, data.count - 22] {
            XCTAssertThrowsError(try StoredZIP(data: data.prefix(length)))
        }
        var tampered = data
        tampered[31] ^= 1
        XCTAssertThrowsError(try StoredZIP(data: tampered))
        XCTAssertThrowsError(try StoredZIP(data: data + Data([0])))
        // Deterministic arbitrary input should never trigger an out-of-bounds access.
        for count in 22...150 { XCTAssertThrowsError(try StoredZIP(data: Data(repeating: 255, count: count))) }
    }

    func testZIPManifestAndEntryCountLimits() throws {
        let rows = [("manifest.json", Data(repeating: 32, count: WallpaperPack.maximumManifestBytes + 1)),
                    ("wallpapers/star.png", Data([1]))]
        XCTAssertThrowsError(try StoredZIP(data: zip(rows)))
        let data = try archive { $0["wallpapers"] = [] }
        XCTAssertThrowsError(try VerifiedPack(data: data))
        XCTAssertThrowsError(try VerifiedPack(data: archive { $0["schemaVersion"] = 2 }))
    }

    func testAtomicPersistenceUpdateOriginAndDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = URL(string: "https://example.com/sample.bwp.zip")!
        let store = try PackStore(root: root)
        let first = try VerifiedPack(data: archive())
        try store.install(first, source: source)
        let id = first.manifest.members[0].id
        let original = try XCTUnwrap(store.imageURL(for: id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try PackStore(root: root).packs.count, 1)
        XCTAssertThrowsError(try store.install(first, source: source))
        let update = try VerifiedPack(data: archive(revision: 2))
        XCTAssertThrowsError(try store.install(update, source: URL(string: "https://other.example.com/sample.zip")!))
        XCTAssertEqual(store.packs[0].manifest.revision, 1)
        XCTAssertEqual(store.imageURL(for: id), original)
        // A failed atomic index commit must leave the original pack and no staging directory.
        let index = root.appendingPathComponent("index.json")
        let backup = root.appendingPathComponent("index.backup")
        try FileManager.default.moveItem(at: index, to: backup)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.install(update, source: source))
        XCTAssertEqual(store.imageURL(for: id), original)
        XCTAssertEqual(store.packs[0].manifest.revision, 1)
        try FileManager.default.removeItem(at: index)
        try FileManager.default.moveItem(at: backup, to: index)
        XCTAssertEqual(try PackStore(root: root).packs[0].manifest.revision, 1)
        try store.install(update, source: source)
        XCTAssertEqual(store.packs[0].manifest.revision, 2)
        XCTAssertEqual(update.manifest.members[0].id, id)
        XCTAssertNotEqual(store.imageURL(for: id), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        try store.remove(id: first.manifest.id)
        XCTAssertTrue(try PackStore(root: root).packs.isEmpty)
        XCTAssertNil(store.imageURL(for: id))
    }

    func testPackIDsNamespaceWallpaperIDsAndRetainOriginal() throws {
        let first = try VerifiedPack(data: archive(id: "first")).manifest
        let second = try VerifiedPack(data: archive(id: "second")).manifest
        XCTAssertEqual(first.wallpapers[0].id, "star")
        XCTAssertNotEqual(first.members[0].id, second.members[0].id)
        XCTAssertTrue(Catalog.safeID(first.members[0].id))
    }

    func testInvalidURLAndCredentialsNeverStartDownload() throws {
        for url in ["http://example.com/a.zip", "file:///tmp/a.zip", "https://user:pass@example.com/a.zip",
                    "https://localhost/a.zip", "https://localhost./a.zip", "https://example.local./a.zip", "https://127.0.0.1/a.zip", "https://[::1]/a.zip",
                    "https://example.local/a.zip", "https://example.com:8443/a.zip", "https://example.com/a.zip#secret"] {
            XCTAssertThrowsError(try PackURL.validated(url), url)
        }
        XCTAssertNoThrow(try PackURL.validated("https://example.com/a.zip?download=1"))
    }

    func testCorruptIndexDoesNotBecomeEmptyLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("index.json"))
        XCTAssertThrowsError(try PackStore(root: root))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("index.json"), encoding: .utf8), "broken")
    }
}
