import SwiftUI

struct RotationView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @EnvironmentObject private var shortcut: ShortcutConnection
    @Environment(\.openURL) private var openURL
    @State private var exporting = false
    @State private var exported = false
    @State private var preview: Member?
    @AppStorage("wallpaperShortcutName") private var shortcutName = WallpaperShortcut.defaultName
    @AppStorage("wallpaperShortcutConfigured") private var shortcutConfigured = false

    var body: some View {
        NavigationStack {
            List {
                if library.selected.isEmpty {
                    ContentUnavailableView("未選択", systemImage: "checkmark.circle")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(library.selected) { member in
                            HStack(spacing: 16) {
                                NavigationLink {
                                    MemberDetailView(member: member)
                                } label: {
                                    HStack(spacing: 16) {
                                        ArtworkView(id: member.id, square: true)
                                            .frame(width: 56, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                        Text(member.name).font(.body.weight(.medium))
                                    }
                                }
                                Button { library.toggle(member.id) } label: {
                                    Image(systemName: "minus.circle").font(.title3)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                                .accessibilityLabel("\(member.name)、選択を解除")
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("\(library.selected.count)枚") }
                }
                Section {
                    Picker("順序", selection: Binding(get: { library.state.order },
                        set: { value in library.update { $0.order = value } })) {
                        ForEach(RotationOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    if shortcutConfigured {
                        Button {
                            shortcut.run(named: shortcutName, openURL: openURL)
                        } label: {
                            Label("壁紙を変更", systemImage: "iphone.gen3")
                                .frame(minHeight: 44)
                        }
                        .disabled(library.selected.isEmpty)
                        .accessibilityIdentifier("runWallpaperShortcut")
                        Button("自動切り替え・連携設定", systemImage: "slider.horizontal.3") {
                            shortcut.showingSetup = true
                        }.frame(minHeight: 44)
                    } else {
                        Button("壁紙変更を設定", systemImage: "slider.horizontal.3") {
                            shortcut.showingSetup = true
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("setupWallpaperShortcut")
                    }
                } footer: {
                    Text(shortcutConfigured ? "ショートカット「\(shortcutName)」を実行します。壁紙の変更はショートカットが行います。"
                         : "初回はショートカットの設定が必要です。写真・ファイルへの書き出しは不要です。")
                }
                if shortcut.returnedWithoutResult {
                    Section {
                        Text("実行結果を確認できませんでした。壁紙が変わらない場合や、ショートカットを削除・改名した場合は設定し直してください。")
                        Button("ショートカットを設定し直す") { shortcut.reconfigure() }
                            .accessibilityIdentifier("repairWallpaperShortcut")
                    }
                } else if let message = shortcut.resultMessage {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Button {
                        exporting = true
                        exported = false
                        Task { @MainActor in
                            defer { exporting = false }
                            do {
                                _ = try await library.exportToPhotos()
                                exported = true
                            } catch { library.message = error.localizedDescription }
                        }
                    } label: {
                        HStack {
                            Label(exported ? "保存済み" : "写真に保存",
                                  systemImage: exported ? "checkmark" : "square.and.arrow.down")
                            Spacer()
                            if exporting { ProgressView() }
                        }.frame(minHeight: 44)
                    }.disabled(exporting || library.selected.isEmpty)
                } header: { Text("写真シャッフルを使う場合") }
                  footer: { Text("iOSの写真シャッフルを使う場合だけ、写真への保存が必要です。保存した写真は、iPhoneの「設定」→「壁紙」→「写真シャッフル」で選びます。") }
            }
            .navigationTitle("選択中")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        do {
                            preview = try library.previewNextMember()
                        } catch { library.message = error.localizedDescription }
                    } label: { Label("候補を見る", systemImage: "photo.on.rectangle.angled") }
                    .labelStyle(.titleAndIcon)
                    .disabled(library.selected.isEmpty)
                    .accessibilityIdentifier("nextWallpaperPreview")
                }
            }
            .sheet(item: $preview) { member in
                NavigationStack {
                    VStack(spacing: 12) {
                        WallpaperPreview(id: member.id)
                        Text("候補のプレビューです。壁紙の変更は「選択中」画面から行います。")
                            .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    }
                        .navigationTitle(member.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完了") { preview = nil }
                            }
                        }
                }
            }
            .onChange(of: library.state.selectedIDs) { _, _ in exported = false }
        }
    }
}
