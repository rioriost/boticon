import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MembersView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var organization = "all"
    @State private var selectedOnly = false
    @AppStorage("gallerySortOrder") private var sortOrder = MemberSortOrder.debutOldest

    private var filtered: [Member] {
        sortOrder.sorted(library.available.filter {
            (organization == "all" || $0.organization == organization)
            && (!selectedOnly || library.state.selectedIDs.contains($0.id))
            && $0.matches(query)
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("所属", selection: $organization) {
                        Text("すべて").tag("all")
                        ForEach(Array(Set(library.available.map(\.organization))).sorted(), id: \.self) { org in
                            Text(library.available.first { $0.organization == org }?.organizationName ?? org).tag(org)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("agencyPicker")
                    if library.members.isEmpty {
                        ContentUnavailableView("壁紙は同梱していません", systemImage: "photo",
                            description: Text("この公開版はソースコードのみです。利用する画像とカタログをご自身で追加してください。"))
                            .accessibilityIdentifier("emptyPublicCatalog")
                    } else if filtered.isEmpty {
                        ContentUnavailableView("該当なし", systemImage: "magnifyingglass")
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(filtered) { member in WallpaperCard(member: member) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("壁紙")
            .searchable(text: $query, prompt: "検索")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("並び順", selection: $sortOrder) {
                            ForEach(MemberSortOrder.allCases, id: \.self) { order in
                                Text(order.title).tag(order)
                            }
                        }
                        Divider()
                        Toggle("選択中のみ", isOn: $selectedOnly)
                    } label: {
                        Label("表示設定", systemImage: "line.3.horizontal.decrease")
                    }.accessibilityIdentifier("galleryFilters")
                }
            }
        }
    }

    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 145), spacing: 16)]
    }
}

private struct WallpaperCard: View {
    @EnvironmentObject private var library: WallpaperLibrary
    let member: Member
    private var selected: Bool { library.state.selectedIDs.contains(member.id) }
    private var ready: Bool { library.imageURL(for: member.id) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                MemberDetailView(member: member)
            } label: {
                ArtworkView(id: member.id, square: true)
                    .aspectRatio(0.78, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(member.name)、プレビュー")
            .accessibilityIdentifier("preview-\(member.id)")
            .overlay(alignment: .topTrailing) {
                if ready {
                    Button { library.toggle(member.id) } label: {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2.weight(.medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(selected ? Color.black : Color.white, Color.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel("\(member.name)、\(selected ? "選択を解除" : "選択")")
                    .accessibilityValue(selected ? "選択中" : "未選択")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("select-\(member.id)")
                }
            }
            Text(member.name).font(.headline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ArtworkView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    let id: String
    var square = false
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .secondarySystemGroupedBackground)
            if square {
                if let url = library.imageURL(for: id), let image = UIImage(contentsOfFile: url.path) {
                    GeometryReader { proxy in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height,
                                   alignment: library.anchor(for: id) == .lowerLeft ? .bottomLeading : .bottomTrailing)
                            .clipped()
                    }
                }
            } else if let image = library.wallpaperImage(for: id) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
        .id("\(id)-\(library.revision)")
    }
}

struct MemberDetailView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    let member: Member
    @State private var photo: PhotosPickerItem?
    @State private var importingFile = false
    @State private var busy = false
    private var selected: Bool { library.state.selectedIDs.contains(member.id) }

    var body: some View {
        WallpaperPreview(id: member.id)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("配置", selection: Binding(get: { library.anchor(for: member.id) },
                        set: { value in library.update { $0.anchors[member.id] = value } })) {
                        ForEach(WallpaperAnchor.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("写真から読み込む", systemImage: "photo")
                    }.disabled(busy)
                    Button { importingFile = true } label: {
                        Label("ファイルから読み込む", systemImage: "folder")
                    }.disabled(busy)
                    if let url = member.officialProfileURL {
                        Link(destination: url) { Label("公式サイト", systemImage: "arrow.up.right.square") }
                    }
                } label: {
                    Label("その他", systemImage: "ellipsis")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { library.toggle(member.id) } label: {
                Label(selected ? "選択済み" : "選択", systemImage: selected ? "checkmark" : "plus")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(library.imageURL(for: member.id) == nil)
            .accessibilityValue(selected ? "選択中" : "未選択")
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.bar)
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try library.importImage(Data(contentsOf: url), for: member)
            } catch { library.message = error.localizedDescription }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            busy = true
            Task { @MainActor in
                defer { busy = false; photo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ImportError.invalidImage
                    }
                    try library.importImage(data, for: member)
                } catch { library.message = error.localizedDescription }
            }
        }
    }
}

struct WallpaperPreview: View {
    let id: String
    var body: some View {
        GeometryReader { proxy in
            let canvas = WallpaperRenderer.deviceCanvas
            let width = max(1, min(320, proxy.size.width - 48,
                                   (proxy.size.height - 48) * canvas.width / canvas.height))
            ArtworkView(id: id)
                .frame(width: width, height: width * canvas.height / canvas.width)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}
