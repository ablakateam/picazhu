import SwiftUI
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

            SearchBar(text: $model.searchText, onSubmit: {
                Task { await model.reloadCurrentFolder() }
            })
            .padding(DesignTokens.Spacing.md)

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
                    thumbnailForItem: { item in model.thumbnail(for: item) },
                    onOpen: { _ in Task { await model.openSelection() } }
                )
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
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search filenames, folders, tags…", text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
            if !text.isEmpty {
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
    }
}
