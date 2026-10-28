import Foundation

public enum WallpaperAnchor: String, Codable, CaseIterable, Sendable {
    case lowerLeft, lowerRight
    public var title: String { self == .lowerLeft ? "左下" : "右下" }
}

public enum WallpaperLayout {
    /// Use the native extent on each axis: rounded point sizes and a fractional
    /// nativeScale can otherwise lose a pixel on downsampled displays (13 mini).
    public static func canvas(window: CGSize, screen: CGSize, native: CGSize) -> CGSize {
        guard window.width > 0, window.height > 0, screen.width > 0, screen.height > 0,
              native.width > 0, native.height > 0 else { return CGSize(width: 1320, height: 2868) }
        return CGSize(width: (window.width / screen.width * native.width).rounded(),
                      height: (window.height / screen.height * native.height).rounded())
    }

    /// Preserve source pixels. Resize the canvas only, never the character.
    /// Left peeking: adjust top/right. Right peeking: adjust top/left.
    public static func origin(source: CGSize, canvas: CGSize, anchor: WallpaperAnchor) -> CGPoint {
        CGPoint(x: anchor == .lowerLeft ? 0 : canvas.width - source.width,
                y: canvas.height - source.height)
    }
}
