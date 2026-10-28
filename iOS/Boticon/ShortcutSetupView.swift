import SwiftUI

struct ShortcutSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var library: WallpaperLibrary
    @EnvironmentObject private var shortcut: ShortcutConnection
    @AppStorage("wallpaperShortcutName") private var shortcutName = WallpaperShortcut.defaultName
    @AppStorage("wallpaperShortcutConfigured") private var configured = false
    @State private var name = ""

    private var templateURL: URL? {
        Bundle.main.url(forResource: "Boticon壁紙を変更", withExtension: "shortcut", subdirectory: "Shortcuts")
    }

    private func openShortcuts(_ url: URL) {
        openURL(url) { opened in
            if !opened { shortcut.failure = "この端末ではショートカットを開けません。ショートカットアプリを確認してください。" }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("画像とカタログを用意し、ショートカットを設定すると、選択した壁紙をiPhoneへ渡せます。写真やファイルへの書き出しは不要です。初回の許可と変更先の指定はiPhone側で行います。")
                }
                Section {
                    if let url = templateURL {
                        ShareLink(item: url, preview: SharePreview(WallpaperShortcut.defaultName)) {
                            Label("ショートカットを追加", systemImage: "plus.app")
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("importWallpaperShortcut")
                    } else {
                        Text("公開版には署名済みショートカットを同梱していません。READMEの手順でテンプレートを作るか、下の「手動で作る場合」を開いて設定してください。")
                            .accessibilityIdentifier("unsignedShortcutNotice")
                    }
                    Text("共有画面で「ショートカット」を選び、表示される内容を確認して追加してください。アプリで選んだ画像を取得し、壁紙に設定するショートカットです。")
                    Text("追加したショートカットを一度実行し、画像取得と壁紙変更を許可してください。テンプレートはプレビュー・自動切り抜き・ぼかしをオフにしてあります。変更する壁紙を指定する場合は、ショートカットを編集します。")
                    Button("ショートカットを開く", systemImage: "arrow.up.right.square") {
                        openShortcuts(URL(string: "shortcuts://")!)
                    }
                } header: { Text("1. 用意済みのショートカットを追加") } footer: {
                    Text("追加しただけでは壁紙は変わりません。共有画面にショートカットがない場合は「その他」も確認してください。「壁紙を出力する」の確認は、実行結果をアプリへ返すためのものです。写真・ファイルへの保存ではありません。許可する範囲はiOSの画面で選択します。")
                }
                Section {
                    TextField("追加したショートカット名", text: $name)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("wallpaperShortcutName")
                    Button("この名前で試す", systemImage: "play") {
                        shortcut.run(named: name, openURL: openURL)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library.selected.isEmpty)
                    Button("連携設定を完了", systemImage: "checkmark") {
                        shortcutName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        configured = true
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveWallpaperShortcut")
                } header: { Text("2. 動作を確認して連携") } footer: {
                    Text("追加時に名前を変えた場合は、その名前を入力してください。動作を確認してから完了してください。アプリはショートカットの一覧や、壁紙自体の変更結果を読み取れません。")
                }
                Section {
                    Button("連携設定を解除して追加し直す") { shortcut.reconfigure() }
                        .accessibilityIdentifier("resetWallpaperShortcut")
                } header: { Text("削除・改名した場合") } footer: {
                    Text("アプリ内の連携設定だけを解除します。選択したメンバーや画像は保持されます。上の「ショートカットを追加」から作り直せます。")
                }
                Section {
                    DisclosureGroup("手動で作る場合") {
                        Text("「ショートカット」で新規作成し、上の名前を付けます。Boticon壁紙の「次のBoticon壁紙を取得」、続けて「壁紙に写真を設定」を追加し、取得した画像を入力にします。iOSの版によっては後者は「壁紙の写真を設定」という名前です。")
                    }
                }
                Section {
                    Picker("希望する頻度", selection: Binding(get: { library.state.frequency },
                        set: { value in library.update { $0.frequency = value } })) {
                        ForEach(RotationFrequency.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("「ショートカット」の「オートメーション」で時刻を指定し、作成したショートカットを実行するよう設定します。確認なしで動かすには「すぐに実行」を選びます。")
                    Text("毎週は曜日を指定します。毎時にする場合は、実行したい各時刻のオートメーションを作ります。写真への保存を選ぶ場合は、iOSの写真シャッフルでも毎時・毎日の切り替えができます。")
                    Link("Appleのオートメーション設定ガイド", destination: URL(string: "https://support.apple.com/ja-jp/guide/shortcuts/apd602971e63/ios")!)
                } header: { Text("毎日・毎週などの自動切り替え") } footer: {
                    Text("希望する頻度の選択だけでは自動実行されません。実行時刻やロック中の動作は、実機で確認してください。")
                }
            }
            .navigationTitle("壁紙変更の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
            .onAppear { name = shortcutName }
            .alert("壁紙を変更できませんでした", isPresented: Binding(
                get: { shortcut.failure != nil },
                set: { if !$0, shortcut.failure != nil { shortcut.failure = nil } })) {
                Button("設定を確認する") { shortcut.failure = nil }
            } message: { Text(shortcut.failure ?? "") }
        }
    }
}
