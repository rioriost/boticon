import SwiftUI

struct PacksView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editing: Bool
    @State private var urlText = ""
    @State private var hashText = ""
    @State private var pending: VerifiedPack?
    @State private var source: URL?
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/wallpapers.bwp.zip", text: $urlText)
                        .focused($editing).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("壁紙パックのURL").accessibilityIdentifier("packURL")
                        .disabled(busy || pending != nil)
                    TextField("SHA-256（任意）", text: $hashText)
                        .focused($editing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("packHash").disabled(busy || pending != nil)
                    if busy {
                        HStack { ProgressView(); Text("ダウンロード・検証中") }
                        Button("キャンセル", role: .cancel) { task?.cancel() }
                    } else if pending == nil {
                        Button("パックを確認") { download() }
                            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("checkPack")
                    }
                } header: { Text("URLから追加") } footer: {
                    Text("BWP v1形式のZIPを取得します。接続先にはIPアドレスなどの通信情報が伝わります。信頼できる配布元のURLを入力してください。別の信頼できる経路で案内されたSHA-256があれば照合できます。")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("packError") }
                }
                if let pending, let source {
                    Section("追加するパック") {
                        PackSummary(manifest: pending.manifest, source: source)
                        LabeledContent("版", value: String(pending.manifest.revision))
                        LabeledContent("壁紙", value: "\(pending.manifest.wallpapers.count)枚")
                        Text("SHA-256: \(pending.archiveSHA256)").font(.caption).textSelection(.enabled)
                        Text("配布元と利用条件を確認してください。検証の成功は、配布者の身元や画像の利用許諾を保証しません。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("このパックを追加") {
                            do {
                                try library.install(pending, source: source)
                                self.pending = nil; self.source = nil; urlText = ""; hashText = ""; error = nil
                            } catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("installPack")
                        Button("取り込みをやめる", role: .cancel) { self.pending = nil; self.source = nil }
                    }
                }
                Section("追加済みのパック") {
                    if library.packs.isEmpty { Text("パックはまだありません").foregroundStyle(.secondary) }
                    ForEach(library.packs) { pack in
                        NavigationLink {
                            InstalledPackDetailView(pack: pack).environmentObject(library)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(pack.manifest.name)
                                Text("\(pack.manifest.wallpapers.count)枚・版\(pack.manifest.revision)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Link("壁紙パックの公開仕様", destination: URL(string: "https://github.com/rioriost/boticon/blob/main/docs/wallpaper-pack-v1.md")!)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("壁紙パック")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { task?.cancel(); dismiss() } } }
        }
        .onDisappear { task?.cancel() }
    }

    private func download() {
        editing = false
        error = nil
        do {
            let url = try PackURL.validated(urlText)
            let hash = hashText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard hash.isEmpty || WallpaperPack.validHash(hash) else {
                throw PackError.invalid("SHA-256は64桁の16進数で入力してください。")
            }
            busy = true
            task = Task {
                defer { busy = false; task = nil }
                do {
                    let configuration = URLSessionConfiguration.ephemeral
                    #if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.environment["BOTICON_PACK_FIXTURE_BASE64"] != nil {
                        configuration.protocolClasses = [PackFixtureProtocol.self]
                    }
                    #endif
                    let file = try await PackDownload(configuration: configuration).fetch(url)
                    defer { try? FileManager.default.removeItem(at: file) }
                    let worker = Task.detached(priority: .userInitiated) {
                        try Task.checkCancellation()
                        return try VerifiedPack(data: Data(contentsOf: file, options: .mappedIfSafe),
                                                expectedSHA256: hash.isEmpty ? nil : hash)
                    }
                    let verified = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                    try Task.checkCancellation()
                    try library.validateInstall(verified, source: url)
                    pending = verified; source = url
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}

private struct PackSummary: View {
    let manifest: PackManifest
    let source: URL
    var body: some View {
        Text(manifest.name).font(.headline)
        LabeledContent("作成者", value: manifest.author)
        Text("配布元: \(source.host ?? "")").font(.footnote).textSelection(.enabled)
        Text(manifest.license).textSelection(.enabled)
        if let homepage = manifest.homepage { Link("配布者の案内", destination: homepage) }
        if manifest.wallpapers.contains(where: \.aiGenerated) {
            Text("生成AIを使った画像を含みます").font(.footnote)
        }
    }
}

struct PackArtworkInfoView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @Environment(\.dismiss) private var dismiss
    let id: String
    var body: some View {
        NavigationStack {
            List {
                if let (pack, item) = library.packInfo(for: id) {
                    Section("壁紙") {
                        Text(item.name).font(.headline)
                        Text(item.attribution).textSelection(.enabled)
                        Text(item.aiGenerated ? "生成AIを使用した画像" : "生成AIの使用なし（配布者の申告）")
                    }
                    Section("パックと利用条件") { PackSummary(manifest: pack.manifest, source: pack.source) }
                    Section { Text("出典・生成AIの使用・利用条件は配布者の申告です。画像の再配布や外部での利用には、権利者の条件を別途確認してください。") }
                }
            }
            .navigationTitle("画像の情報")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}

private struct InstalledPackDetailView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var error: String?
    let pack: InstalledPack
    var body: some View {
        List {
            PackSummary(manifest: pack.manifest, source: pack.source)
            LabeledContent("版", value: String(pack.manifest.revision))
            Text("\(pack.manifest.wallpapers.count)枚")
            if let error { Text(error).foregroundStyle(.red) }
            Button("パックを削除", role: .destructive) { confirmingDelete = true }
                .accessibilityIdentifier("deletePack")
        }
        .navigationTitle(pack.manifest.name)
        .alert("このパックを削除しますか？", isPresented: $confirmingDelete) {
            Button("削除", role: .destructive) {
                do { try library.removePack(pack.id); dismiss() }
                catch { self.error = error.localizedDescription }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("パック内の壁紙と選択を削除します。写真に保存した画像、設定済みの壁紙、ショートカットは残ります。") }
    }
}
