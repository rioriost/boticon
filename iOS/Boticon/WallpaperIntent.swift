import AppIntents
import UniformTypeIdentifiers

struct NextWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "次のBoticon壁紙を取得"
    static let description = IntentDescription("アプリで選択したメンバーから画像を1枚返します。「壁紙に写真を設定」につなげて使います。写真やファイルへの保存は不要です。")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (data, name) = try WallpaperLibrary.shared.nextWallpaper()
        #if DEBUG
        // Inspect the actual App Intent output separately from the OS wallpaper rendering.
        try? data.write(to: URL.cachesDirectory.appendingPathComponent("last-intent-output.png"), options: .atomic)
        #endif
        return .result(value: IntentFile(data: data, filename: name, type: .png))
    }
}

struct BoticonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextWallpaperIntent(),
                    phrases: ["\(.applicationName)で次の壁紙を取得"],
                    shortTitle: "次の壁紙を取得", systemImageName: "photo.on.rectangle.angled")
    }
}
