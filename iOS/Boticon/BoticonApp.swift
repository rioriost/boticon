import SwiftUI

@main
struct BoticonApp: App {
    @StateObject private var library = WallpaperLibrary.shared
    @StateObject private var shortcut = ShortcutConnection()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                MembersView()
                    .tabItem { Label("壁紙", systemImage: "square.grid.2x2") }
                RotationView()
                    .tabItem { Label("選択中", systemImage: "checkmark.circle") }
                    .badge(library.selected.count)
                AboutView()
                    .tabItem { Label("このアプリ", systemImage: "info.circle") }
            }
            .tint(.primary)
            .environmentObject(library)
            .environmentObject(shortcut)
            .sheet(isPresented: $shortcut.showingSetup) { ShortcutSetupView().environmentObject(library).environmentObject(shortcut) }
            .onOpenURL { shortcut.receive($0) }
            .onChange(of: scenePhase) { _, value in shortcut.sceneChanged(value) }
            .alert(shortcut.failure == nil ? "Boticon壁紙" : "壁紙を変更できませんでした", isPresented: Binding(
                get: { library.message != nil || (shortcut.failure != nil && !shortcut.showingSetup) },
                set: { presented in
                    if !presented {
                        // SwiftUI also dismisses this alert while presenting the repair sheet.
                        // Avoid publishing redundant nil values during that view update.
                        if library.message != nil { library.message = nil }
                        if shortcut.failure != nil { shortcut.failure = nil }
                    }
                })) {
                if shortcut.failure != nil {
                    Button("連携設定を開く") { shortcut.failure = nil; shortcut.showingSetup = true }
                }
                Button("OK", role: .cancel) { library.message = nil }
            } message: { Text(shortcut.failure ?? library.message ?? "") }
        }
    }
}
