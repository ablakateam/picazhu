import SwiftUI
import UniformTypeIdentifiers
import PicazhuCore
import PicazhuUI

struct RootView: View {
    @Bindable var model: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                splitView
                if model.aiProgress.isActive {
                    AIProgressBar(
                        snapshot: model.aiProgress,
                        onPauseToggle: { Task { await model.pauseResumeAI() } },
                        onCancel: { Task { await model.cancelAI() } }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.aiProgress.isActive)

            if model.debugLog.isVisible {
                DebugConsoleView(debugLog: model.debugLog)
                    .transition(.move(edge: .bottom))
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 520, ideal: 820)
        } detail: {
            VStack(spacing: 0) {
                InspectorView(
                    info: model.inspectorInfo(),
                    onReveal: { Task { await model.revealSelection() } },
                    onOpen: { Task { await model.openSelection() } },
                    onCopyPath: { Task { await model.copyPathSelection() } },
                    onQuickLook: { Task { await model.quickLookSelection() } }
                )
                if !model.selection.isEmpty {
                    Divider()
                    ScrollView {
                        VStack(spacing: DesignTokens.Spacing.md) {
                            if let location = model.inspectorLocation() {
                                MapPreviewView(location: location)
                            }
                            AIInspectorSection(
                                info: model.inspectorAIInfo(),
                                isAnalyzing: model.aiProgress.isActive,
                                onReanalyze: { Task { await model.reanalyzeSelection() } },
                                onClear: { Task { await model.clearSelectionAI() } }
                            )
                            .padding(DesignTokens.Spacing.lg)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation { model.debugLog.isVisible.toggle() }
                } label: {
                    Image(systemName: "terminal")
                        .foregroundStyle(model.debugLog.isVisible ? .green : .secondary)
                }
                .help("Toggle debug console")
                OllamaStatusPill(status: model.ollamaStatus, onRefresh: {
                    Task { await model.refreshOllamaStatus() }
                })
                if model.isIndexing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.indexingStatus.isEmpty ? "Indexing…" : model.indexingStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.aiProgress.isActive {
                    AIProgressChip(snapshot: model.aiProgress)
                }
                Slider(value: $model.cellSize,
                       in: DesignTokens.Grid.minCellSize...DesignTokens.Grid.maxCellSize)
                    .frame(width: 160)
                Button {
                    Task { await model.analyzeCurrentFolder() }
                } label: {
                    Label("Analyze", systemImage: "sparkles")
                }
                .disabled(model.currentFolder == nil)
                .help("Analyze current folder with AI")
                Button {
                    model.showAISettings = true
                } label: {
                    Label("AI Settings", systemImage: "gearshape")
                }
                .help("Configure AI provider")
                Button {
                    Task { await model.addWatchedRoot() }
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $model.showAISettings) {
            AISettingsSheet(model: model)
        }
        .sheet(isPresented: $model.showAbout) {
            AboutView()
        }
        .sheet(isPresented: $model.showHelp) {
            HelpView()
        }
        .sheet(isPresented: $model.showDuplicates) {
            DuplicatesView(model: model)
        }
        .sheet(isPresented: $model.showDeviceImport) {
            DeviceImportView(importer: model.env.deviceImporter) { importedFolder in
                Task { await model.addDroppedFolder(importedFolder) }
            }
        }
        .alert("AI Not Available", isPresented: Binding(
            get: { model.aiProviderError != nil },
            set: { if !$0 { model.aiProviderError = nil } }
        )) {
            Button("Open Settings") { model.showAISettings = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.aiProviderError ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.hasDirectoryPath else { return }
                    Task { @MainActor in
                        await model.addDroppedFolder(url)
                    }
                }
            }
            return true
        }
        .task { await model.bootstrap() }
    }

    @ViewBuilder
    private var sidebar: some View {
        List {
            if model.watchedRoots.isEmpty {
                Section("Library") {
                    Text("No folders yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } else {
                Section("Library") {
                    ForEach(model.watchedRoots) { root in
                        RootNode(root: root, model: model)
                    }
                }
            }

            if !model.env.deviceImporter.devices.isEmpty {
                Section("Devices") {
                    ForEach(model.env.deviceImporter.devices) { device in
                        Button {
                            model.env.deviceImporter.selectDevice(device)
                            model.showDeviceImport = true
                        } label: {
                            HStack(spacing: 8) {
                                if let iconData = device.iconData, let icon = NSImage(data: iconData) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "iphone")
                                        .foregroundStyle(.blue)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name)
                                        .font(.callout.weight(.medium))
                                    if !device.model.isEmpty {
                                        Text(device.model)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !model.pinned.isEmpty {
                Section("Pinned") {
                    ForEach(model.pinned) { folder in
                        folderRow(folder)
                    }
                }
            }

            if !model.recent.isEmpty {
                Section("Recent") {
                    ForEach(model.recent) { folder in
                        folderRow(folder)
                    }
                }
            }

            if !model.savedSearches.isEmpty {
                Section("Saved Searches") {
                    ForEach(model.savedSearches, id: \.id) { search in
                        Button {
                            Task { await model.applySavedSearch(search) }
                        } label: {
                            Label(search.name, systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                Task { await model.deleteSavedSearch(search) }
                            }
                        }
                    }
                }
            }

            if !model.cachedTags.isEmpty {
                Section("AI Tags") {
                    TagCloudView(tags: model.cachedTags) { tag in
                        Task { await model.searchByTag(tag) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func folderRow(_ folder: Folder) -> some View {
        Button {
            Task { await model.selectFolder(folder) }
        } label: {
            Label(folder.name.isEmpty ? "(root)" : folder.name, systemImage: "folder")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            BreadcrumbBar(trail: model.breadcrumbTrail(), currentFolder: model.currentFolder) { folder in
                Task { await model.selectFolder(folder) }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.md)

            SearchBar(text: $model.searchText, global: $model.searchGlobal, onSubmit: {
                Task { await model.reloadCurrentFolder() }
            }, onSave: { name in
                Task { await model.saveCurrentSearch(name: name) }
            })
            .padding(DesignTokens.Spacing.md)

            FilterChipsBar(filter: $model.filterState) {
                Task { await model.reloadCurrentFolder() }
            }

            Divider()

            if model.currentFolder == nil && model.watchedRoots.isEmpty {
                EmptyStateView(
                    symbol: "photo.on.rectangle.angled",
                    title: "Welcome to PICAZHU",
                    message: "Add a folder to start browsing your photos and videos.",
                    actionLabel: "Add Folder",
                    action: { Task { await model.addWatchedRoot() } }
                )
            } else if model.items.isEmpty {
                EmptyStateView(
                    symbol: "photo.stack",
                    title: "Nothing here yet",
                    message: "Select a folder in the sidebar to see its contents."
                )
            } else {
                MediaGridView(
                    items: model.items,
                    selection: $model.selection,
                    cellSize: model.cellSize,
                    currentlyAnalyzingName: model.aiProgress.isActive ? model.aiProgress.currentItemName : "",
                    favorites: model.favorites,
                    thumbnailForItem: { item in model.thumbnail(for: item) },
                    onOpen: { _ in Task { await model.openSelection() } },
                    onToggleFavorite: { id in Task { await model.toggleFavorite(id) } }
                )
                .contextMenu {
                    if !model.selection.isEmpty {
                        Button("Analyze Selected (\(model.selection.count))", systemImage: "sparkles") {
                            Task { await model.analyzeSelectedItems() }
                        }
                        Button("Clear AI Data", systemImage: "trash") {
                            Task { await model.clearAIForSelected() }
                        }
                        Divider()
                        Button("Copy Paths", systemImage: "doc.on.clipboard") {
                            model.copyPathsForSelected()
                        }
                        Button("Open", systemImage: "arrow.up.right.square") {
                            Task { await model.openSelection() }
                        }
                        Button("Reveal in Finder", systemImage: "folder") {
                            Task { await model.revealSelection() }
                        }
                        Divider()
                    }
                    Button("Select All", systemImage: "checkmark.circle") {
                        model.selectAll()
                    }
                    .keyboardShortcut("a", modifiers: .command)
                }
            }
        }
    }
}

struct RootNode: View {
    let root: WatchedRoot
    @Bindable var model: LibraryViewModel
    @State private var expanded = true
    @State private var showingRemoveConfirmation = false

    var body: some View {
        let _ = model.sidebarRefreshToken
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(model.rootFolders(for: root.id)) { folder in
                FolderNode(folder: folder, model: model)
            }
        } label: {
            HStack {
                Image(systemName: accessIcon)
                    .foregroundStyle(accessTint)
                Text(root.displayName)
                Spacer()
                Button {
                    showingRemoveConfirmation = true
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove folder from library")
            }
        }
        .contextMenu {
            Button("Remove Folder", role: .destructive) {
                showingRemoveConfirmation = true
            }
        }
        .confirmationDialog(
            "Remove “\(root.displayName)” from the library?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await model.removeRoot(root.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files on disk are not touched. Only PICAZHU's index for this folder is removed.")
        }
    }

    private var accessIcon: String {
        switch root.accessState {
        case .ok: return "externaldrive.fill"
        case .stale: return "exclamationmark.triangle.fill"
        case .denied: return "lock.fill"
        }
    }

    private var accessTint: Color {
        switch root.accessState {
        case .ok: return .accentColor
        case .stale: return .orange
        case .denied: return .red
        }
    }
}

struct FolderNode: View {
    let folder: Folder
    @Bindable var model: LibraryViewModel
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        let kids = model.children(of: folder)
        let _ = model.sidebarRefreshToken
        if kids.isEmpty {
            folderRow
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(kids) { child in
                    FolderNode(folder: child, model: model)
                }
            } label: {
                folderRow
            }
        }
    }

    @ViewBuilder
    private var folderRow: some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text(folder.name)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer(minLength: 4)
            if hovering {
                Button {
                    Task { await model.enableAIForFolder(folder) }
                } label: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Analyze with AI")
            }
            if folder.itemCount > 0 {
                Text("\(folder.itemCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            Task { await model.selectFolder(folder) }
        }
        .contextMenu {
            Button("Analyze with AI", systemImage: "sparkles") {
                Task { await model.enableAIForFolder(folder) }
            }
            Button("Pin Folder", systemImage: "pin") {
                Task { await model.pinFolder(folder) }
            }
        }
    }

    private var isSelected: Bool {
        model.currentFolderID == folder.id
    }
}

struct BreadcrumbBar: View {
    let trail: [Folder]
    let currentFolder: Folder?
    let onTap: (Folder) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            if trail.isEmpty {
                Text("No folder selected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(trail.enumerated()), id: \.element.id) { index, folder in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        onTap(folder)
                    } label: {
                        Text(folder.name.isEmpty ? "Root" : folder.name)
                            .foregroundStyle(index == trail.count - 1 ? Color.primary : Color.secondary)
                            .fontWeight(index == trail.count - 1 ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                }
                if let current = currentFolder {
                    Spacer()
                    Text("\(current.itemCount) items")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }
}

struct SearchBar: View {
    @Binding var text: String
    @Binding var global: Bool
    let onSubmit: () -> Void
    var onSave: ((String) -> Void)? = nil
    @State private var showingSaveDialog = false
    @State private var saveName = ""

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search filenames, folders, tags…", text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    global.toggle()
                    onSubmit()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: global ? "globe" : "folder")
                        Text(global ? "All" : "Folder")
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(global ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                    )
                    .foregroundStyle(global ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(global ? "Searching all folders" : "Searching current folder")

                if let onSave {
                    Button {
                        saveName = text
                        showingSaveDialog = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Save this search")
                }

                Button {
                    text = ""
                    onSubmit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .alert("Save Search", isPresented: $showingSaveDialog) {
            TextField("Search name", text: $saveName)
            Button("Save") { onSave?(saveName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this search a name to find it later in the sidebar.")
        }
    }
}
