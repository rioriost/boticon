import Foundation
import SwiftUI
import Photos
import UniformTypeIdentifiers

@MainActor
final class WallpaperLibrary: ObservableObject {
    static let shared = WallpaperLibrary()
    @Published private(set) var catalog: Catalog?
    @Published private(set) var state = SelectionState()
    @Published private(set) var revision = 0
    @Published var message: String?
    private var startupError: Error?
    private let directory: URL
    private let renderedCache = NSCache<NSString, NSData>()

    init() {
        directory = URL.applicationSupportDirectory.appendingPathComponent("Boticon", isDirectory: true)
        do {
            guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
                throw CatalogError.invalidCatalog
            }
            catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)).validated()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let stateURL = directory.appendingPathComponent("selection.json")
            if FileManager.default.fileExists(atPath: stateURL.path) {
                do { state = try JSONDecoder().decode(SelectionState.self, from: Data(contentsOf: stateURL)) }
                catch { throw CatalogError.corruptState }
            }
        } catch {
            startupError = error
            message = error.localizedDescription
        }
    }

    var members: [Member] { catalog?.members ?? [] }
    var available: [Member] { members.filter { imageURL(for: $0.id) != nil } }
    var selected: [Member] { available.filter { state.selectedIDs.contains($0.id) } }

    func imageURL(for id: String) -> URL? {
        guard Catalog.safeID(id) else { return nil }
        let local = directory.appendingPathComponent("\(id).png")
        if FileManager.default.fileExists(atPath: local.path) { return local }
        return Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "Wallpapers")
    }

    func anchor(for id: String) -> WallpaperAnchor {
        if let override = state.anchors[id] { return override }
        if let url = Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "Wallpapers"),
           let data = try? Data(contentsOf: url),
           let record = try? JSONDecoder().decode(PlacementMetadata.self, from: data),
           let anchor = record.anchor { return anchor }
        return .lowerLeft
    }

    func wallpaperImage(for id: String) -> UIImage? {
        guard let data = try? wallpaperData(for: id) else { return nil }
        return UIImage(data: data)
    }

    private func wallpaperData(for id: String) throws -> Data {
        let canvas = WallpaperRenderer.deviceCanvas
        let anchor = anchor(for: id)
        let key = "\(id)-\(revision)-\(anchor.rawValue)-\(canvas.width)x\(canvas.height)" as NSString
        if let cached = renderedCache.object(forKey: key) { return cached as Data }
        guard let url = imageURL(for: id), let source = UIImage(contentsOfFile: url.path) else {
            throw ImportError.invalidImage
        }
        let data = WallpaperRenderer.png(source, canvas: canvas, anchor: anchor)
        renderedCache.countLimit = 8
        renderedCache.setObject(data as NSData, forKey: key)
        return data
    }

    func update(_ mutation: (inout SelectionState) -> Void) {
        do {
            try checkReady()
            var next = state
            mutation(&next)
            try save(next)
        } catch { message = error.localizedDescription }
    }

    func toggle(_ id: String) {
        guard imageURL(for: id) != nil else { return }
        update {
            if $0.selectedIDs.contains(id) { $0.selectedIDs.remove(id) }
            else { $0.selectedIDs.insert(id) }
        }
    }

    func importImage(_ data: Data, for member: Member) throws {
        try checkReady()
        guard members.contains(where: { $0.id == member.id }), Catalog.safeID(member.id),
              data.count <= 40_000_000, let image = UIImage(data: data) else {
            throw ImportError.invalidImage
        }
        let png = WallpaperRenderer.normalizedPNG(image)
        let url = directory.appendingPathComponent("\(member.id).png")
        try png.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        revision += 1
        renderedCache.removeAllObjects()
    }

    /// A preview does not advance the durable rotation history.
    func previewNextMember() throws -> Member {
        try checkReady()
        let id = try Rotation.next(availableIDs: available.map(\.id), state: state)
        guard let member = members.first(where: { $0.id == id }) else { throw CatalogError.noWallpapers }
        return member
    }

    /// Actual image requests advance the shared rotation history.
    func nextWallpaper() throws -> (Data, String) {
        try checkReady()
        let id = try Rotation.next(availableIDs: available.map(\.id), state: state)
        let data = try wallpaperData(for: id)
        var next = state
        next.lastID = id
        try save(next)
        return (data, "\(id).png")
    }

    func exportToPhotos() async throws -> Int {
        try checkReady()
        let ids = selected.map(\.id)
        guard !ids.isEmpty else { throw CatalogError.noWallpapers }
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else { throw ImportError.photoPermission }
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        let urls = try ids.map { id in
            let url = exportDirectory.appendingPathComponent("\(id).png")
            try wallpaperData(for: id).write(to: url)
            return url
        }
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            for url in urls { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
        }
        return urls.count
    }

    private func checkReady() throws {
        if let startupError { throw startupError }
    }

    private func save(_ next: SelectionState) throws {
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("selection.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        state = next
    }
}

private struct PlacementMetadata: Decodable {
    let anchor: WallpaperAnchor?
}

enum ImportError: Error, LocalizedError {
    case invalidImage, photoPermission
    var errorDescription: String? {
        switch self {
        case .invalidImage: "40MB以下の完成済みボットアイコンか、縦長の壁紙を選択してください。"
        case .photoPermission: "設定アプリからBoticon壁紙への写真の追加を許可してください。"
        }
    }
}

@MainActor
enum WallpaperRenderer {
    static var deviceCanvas: CGSize {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let screen = scene?.screen ?? UIScreen.main
        let bounds = scene?.windows.first(where: \.isKeyWindow)?.bounds.size ?? screen.bounds.size
        return WallpaperLayout.canvas(window: bounds, screen: screen.bounds.size,
                                      native: screen.nativeBounds.size)
    }

    static func normalizedPNG(_ image: UIImage) -> Data {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The source corner stays fixed; only the background canvas changes.
    static func png(_ image: UIImage, canvas: CGSize, anchor: WallpaperAnchor) -> Data {
        let source = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let origin = WallpaperLayout.origin(source: source, canvas: canvas, anchor: anchor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).pngData { context in
            backgroundColor(image, anchor: anchor).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            image.draw(in: CGRect(origin: origin, size: source))
        }
    }

    private static func backgroundColor(_ image: UIImage, anchor: WallpaperAnchor) -> UIColor {
        let fallback = UIColor(red: 18/255, green: 18/255, blue: 20/255, alpha: 1)
        guard let cg = image.cgImage else { return fallback }
        let x = anchor == .lowerLeft ? cg.width - 1 : 0
        guard let corner = cg.cropping(to: CGRect(x: x, y: 0, width: 1, height: 1)) else { return fallback }
        var rgba = [UInt8](repeating: 0, count: 4)
        let sampled = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard sampled, rgba[3] > 0 else { return fallback }
        let alpha = CGFloat(rgba[3])
        return UIColor(red: CGFloat(rgba[0]) / alpha, green: CGFloat(rgba[1]) / alpha,
                       blue: CGFloat(rgba[2]) / alpha, alpha: 1)
    }
}
