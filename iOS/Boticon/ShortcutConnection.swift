import SwiftUI

@MainActor
final class ShortcutConnection: ObservableObject {
    @Published var showingSetup = false
    @Published var failure: String?
    @Published private(set) var resultMessage: String?
    @Published private(set) var returnedWithoutResult = false
    private var leftApp = false
    private let defaults = UserDefaults.standard

    init() {
        returnedWithoutResult = defaults.string(forKey: "wallpaperShortcutPendingRequest") != nil
    }

    private var pendingID: UUID? {
        defaults.string(forKey: "wallpaperShortcutPendingRequest").flatMap(UUID.init(uuidString:))
    }

    func run(named name: String, openURL: OpenURLAction) {
        let requestID = UUID()
        guard let url = WallpaperShortcut.runURL(named: name, requestID: requestID) else {
            showingSetup = true
            return
        }
        defaults.set(requestID.uuidString, forKey: "wallpaperShortcutPendingRequest")
        failure = nil
        resultMessage = nil
        returnedWithoutResult = false
        leftApp = false
        openURL(url) { [weak self] opened in
            guard let self, !opened, self.pendingID == requestID else { return }
            self.clearPending()
            self.failure = "ショートカットを開けませんでした。ショートカットアプリと連携設定を確認してください。"
        }
    }

    func receive(_ url: URL) {
        guard let requestID = pendingID,
              let outcome = WallpaperShortcut.outcome(from: url, requestID: requestID) else { return }
        clearPending()
        switch outcome {
        case .success:
            resultMessage = "ショートカットの実行が完了しました。変更結果は壁紙で確認してください。"
        case .cancelled:
            resultMessage = "ショートカットの実行をキャンセルしました。"
        case .failure(let detail):
            let guidance = "ショートカットが削除・改名されたか、実行中に問題が起きました。連携設定で名前を確認するか、追加し直してください。"
            failure = detail.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }.map { guidance + "\n\n" + $0 } ?? guidance
        }
    }

    func sceneChanged(_ phase: ScenePhase) {
        guard pendingID != nil else { return }
        if phase == .background { leftApp = true }
        if phase == .active, leftApp {
            // Some iOS failures do not deliver a callback. Returning alone proves no result.
            returnedWithoutResult = true
        }
    }

    func reconfigure() {
        clearPending()
        failure = nil
        resultMessage = nil
        defaults.set(false, forKey: "wallpaperShortcutConfigured")
        showingSetup = true
    }

    private func clearPending() {
        defaults.removeObject(forKey: "wallpaperShortcutPendingRequest")
        returnedWithoutResult = false
        leftApp = false
    }
}
