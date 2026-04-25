import Foundation
import SwiftUI
import AppKit
import GRDB
import PicazhuCore
import PicazhuData
import PicazhuIndexing
import PicazhuMedia
import PicazhuPreview
import PicazhuSearch
import PicazhuAI
import PicazhuUI

@MainActor
@Observable
final class LibraryViewModel {
    let env: AppEnvironment

    var watchedRoots: [WatchedRoot] = []
    var currentFolderID: FolderID?
    var currentFolder: Folder?
    var childFolders: [Folder] = []
    var items: [MediaItem] = []
    var selection: Set<MediaItemID> = []
    var pinned: [Folder] = []
    var recent: [Folder] = []
    var savedSearches: [SavedSearch] = []
    var searchText: String = ""
    var searchGlobal: Bool = false
    var filterState: FilterState = FilterState()
    var cellSize: CGFloat = DesignTokens.Grid.defaultCellSize
    var inspectorVisible: Bool = true
    var diagnosticsDisplay: DiagnosticsDisplay?
    var isBootstrapping: Bool = true
    var bootStatus: String = "Opening catalog…"
    var isIndexing: Bool = false
    var indexingStatus: String = ""
    var sidebarRefreshToken: UInt32 = 0

    var aiProgress: AIProgressSnapshot = AIProgressSnapshot()
    var ollamaStatus: OllamaStatus = OllamaStatus()
    var showAISettings: Bool = false
    let debugLog = DebugLog.shared
    private var aiCoordinator: AIEnrichmentCoordinator?
    private var aiConsumerTask: Task<Void, Never>?
    private var aiRateTimer: Task<Void, Never>?
    private var aiLastCompletedTimestamp: Date?
    private var aiRateEMA: Double = 0
    private var aiItemStartTime: Date = Date()
    private var ollamaHealthTimer: Task<Void, Never>?

    private var thumbnailImageCache: [MediaItemID: NSImage] = [:]
    private var observations: [AnyObject] = []

    init(env: AppEnvironment) {
        self.env = env
    }

    func bootstrap() async {
        isBootstrapping = true
        bootStatus = "Opening catalog…"

        await reloadRoots()
        bootStatus = "Loading folders…"
        await refreshSidebar()
        await env.folderWatchManager.refresh()

        bootStatus = "Preparing library…"
        if let first = watchedRoots.first,
           let target = bestLandingFolder(for: first.id) {
            await selectFolder(target)
        }

        bootStatus = "Connecting AI…"
        try? await env.writer.resetStuckJobs()
        startOllamaHealthMonitor()

        if env.aiConfig.mode == .local {
            bootStatus = "Loading AI model…"
            debugLog.info("Warming up local model: \(env.aiConfig.visionModel)")
            do {
                try await env.aiProvider.warmup()
                debugLog.info("Model loaded into RAM")
            } catch {
                debugLog.warn("Model warmup failed: \(error.localizedDescription)")
            }
        }

        bootStatus = "Scanning for changes…"
        runBackgroundIndex()

        isBootstrapping = false

        Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            let pending = (try? self.env.mediaRepo.pendingAIJobs(limit: 1).count) ?? 0
            if pending > 0 {
                await self.startEnrichmentWorkerIfNeeded()
            }
        }
    }

    private func bestLandingFolder(for rootID: WatchedRootID) -> Folder? {
        if let nonEmpty = try? env.folderRepo.firstNonEmpty(rootID: rootID) {
            return nonEmpty
        }
        return (try? env.folderRepo.children(of: nil, rootID: rootID))?.first
    }

    func reloadRoots() async {
        do {
            watchedRoots = try env.rootRepo.all()
            sidebarRefreshToken &+= 1
        } catch {
            PicazhuLog.ui.error("reloadRoots failed: \(error.localizedDescription)")
        }
    }

    func refreshSidebar() async {
        do {
            pinned = try env.folderRepo.pinned()
            recent = try env.folderRepo.recent()
            savedSearches = try env.savedSearches.all()
        } catch {
            PicazhuLog.ui.error("refreshSidebar failed: \(error.localizedDescription)")
        }
    }

    func selectFolder(_ folder: Folder) async {
        if currentFolderID != folder.id {
            thumbnailImageCache.removeAll()
            selection = []
        }
        currentFolderID = folder.id
        currentFolder = folder
        try? await env.writer.recordRecentFolder(folder.id)
        await reloadCurrentFolder()
    }

    func reloadCurrentFolder() async {
        guard let folderID = currentFolderID else {
            items = []
            childFolders = []
            return
        }
        do {
            let hasSearch = !searchText.isEmpty
            let hasFilters = filterState.isActive

            if hasSearch || hasFilters {
                let scope: FolderScope = searchGlobal ? .all : .folder(folderID)
                let query = SearchQuery(
                    text: searchText,
                    kinds: filterState.kinds,
                    dateRange: filterState.datePreset.dateRange,
                    sizeRange: filterState.sizePreset.sizeRange,
                    folderScope: scope
                )
                if hasSearch {
                    var queryEmbedding: [Float]? = nil
                    do {
                        let emb = try await env.aiProvider.embedText(searchText)
                        if emb.dim > 0 { queryEmbedding = emb.vector }
                    } catch {
                        queryEmbedding = nil
                    }
                    let engine = HybridSearchEngine(catalog: env.catalog, embeddings: env.embeddings)
                    let hybrid = try engine.execute(query, queryEmbedding: queryEmbedding)
                    items = hybrid.map(\.item)
                } else {
                    items = try env.searchEngine.execute(query)
                }

                if filterState.aiOnly {
                    items = items.filter { $0.aiState == .ready }
                }
            } else {
                items = try env.mediaRepo.items(in: folderID)
            }
            if let cf = currentFolder {
                childFolders = try env.folderRepo.children(of: cf.id, rootID: cf.rootID)
            }
            sidebarRefreshToken &+= 1
        } catch {
            PicazhuLog.ui.error("reloadCurrentFolder failed: \(error.localizedDescription)")
        }
    }

    func breadcrumbTrail() -> [Folder] {
        guard let current = currentFolder else { return [] }
        var trail: [Folder] = [current]
        var parentID = current.parentID
        while let pid = parentID, let parent = try? env.folderRepo.find(id: pid) {
            trail.insert(parent, at: 0)
            parentID = parent.parentID
        }
        return trail
    }

    func addDroppedFolder(_ url: URL) async {
        debugLog.info("Folder dropped: \(url.lastPathComponent)")
        do {
            let newRootID = try await env.bookmarks.addRoot(from: url)
            await reloadRoots()
            await env.folderWatchManager.refresh()
            isIndexing = true
            indexingStatus = "Scanning \(url.lastPathComponent)…"
            guard let root = try env.rootRepo.find(id: newRootID) else {
                isIndexing = false
                return
            }
            let progressActor = ScanProgress()
            await env.coordinator.scanRootStreaming(root) { batchCount in
                await progressActor.add(batchCount)
            }
            await reloadRoots()
            if let target = bestLandingFolder(for: newRootID) {
                await selectFolder(target)
            }
            indexingStatus = "Generating thumbnails…"
            await runEnrichmentLoop(for: newRootID)
            isIndexing = false
            indexingStatus = ""
        } catch {
            isIndexing = false
            debugLog.error("Drop folder failed: \(error)")
        }
    }

    func addWatchedRoot() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        panel.message = "Choose a folder for PICAZHU to index."

        let response = await MainActor.run { panel.runModal() }
        guard response == .OK, let url = panel.url else { return }

        do {
            let newRootID = try await env.bookmarks.addRoot(from: url)
            await reloadRoots()
            await env.folderWatchManager.refresh()

            isIndexing = true
            indexingStatus = "Scanning \(url.lastPathComponent)…"

            guard let root = try env.rootRepo.find(id: newRootID) else {
                isIndexing = false
                indexingStatus = ""
                return
            }

            let progressActor = ScanProgress()
            let selectorTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard let self else { return }
                    let count = await progressActor.current
                    await MainActor.run {
                        self.indexingStatus = "Scanning… \(count) files"
                    }
                    if self.currentFolder == nil {
                        if let target = self.bestLandingFolder(for: newRootID) {
                            await self.selectFolder(target)
                        } else {
                            await self.reloadRoots()
                        }
                    } else {
                        await self.reloadCurrentFolder()
                    }
                }
            }

            await env.coordinator.scanRootStreaming(root) { batchCount in
                await progressActor.add(batchCount)
            }

            selectorTask.cancel()

            await reloadRoots()
            if currentFolder == nil, let target = bestLandingFolder(for: newRootID) {
                await selectFolder(target)
            } else {
                await reloadCurrentFolder()
            }

            indexingStatus = "Generating thumbnails…"
            await runEnrichmentLoop(for: newRootID)

            isIndexing = false
            indexingStatus = ""
        } catch {
            isIndexing = false
            indexingStatus = ""
            PicazhuLog.ui.error("addWatchedRoot failed: \(error.localizedDescription)")
        }
    }

    private func runBackgroundIndex() {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.isIndexing = true }
            let roots = (try? self.env.rootRepo.all()) ?? []
            for root in roots {
                await self.env.coordinator.scanRootStreaming(root) { [weak self] _ in
                    guard let self else { return }
                    await self.reloadCurrentFolder()
                }
            }
            await self.reloadCurrentFolder()
            await self.runEnrichmentLoop(for: nil)
            await MainActor.run {
                self.isIndexing = false
                self.indexingStatus = ""
            }
        }
    }

    private actor ScanProgress {
        private(set) var current: Int = 0
        func add(_ n: Int) { current += n }
    }

    private func runEnrichmentLoop(for rootID: WatchedRootID?) async {
        _ = rootID
        var idleChecks = 0
        while idleChecks < 3 {
            let pendingThumb = (try? env.mediaRepo.pendingThumbnailJobs(limit: 1).count) ?? 0
            let pendingMeta = (try? env.mediaRepo.pendingMetadataJobs(limit: 1).count) ?? 0
            if pendingThumb == 0 && pendingMeta == 0 {
                idleChecks += 1
                continue
            }
            idleChecks = 0
            await env.coordinator.runEnrichmentPass()
            thumbnailImageCache.removeAll()
            await reloadCurrentFolder()
            let total = (try? env.mediaRepo.pendingThumbnailJobs(limit: 10000).count) ?? 0
            await MainActor.run {
                self.indexingStatus = "Generating thumbnails… \(total) remaining"
            }
        }
    }

    func removeRoot(_ id: WatchedRootID) async {
        do {
            await cancelAI()
            try await env.bookmarks.removeRoot(id)
            try await env.writer.cleanOrphanJobs()
            await reloadRoots()
            await refreshSidebar()
            await env.folderWatchManager.refresh()
            if currentFolder?.rootID == id {
                currentFolderID = nil
                currentFolder = nil
                items = []
                childFolders = []
                selection = []
            }
            thumbnailImageCache.removeAll()
            resetAIProgress()
            debugLog.info("Root removed, AI queue cleaned")
        } catch {
            PicazhuLog.ui.error("removeRoot failed: \(error.localizedDescription)")
        }
    }

    func clearLibrary() async {
        do {
            await cancelAI()
            for root in watchedRoots {
                try await env.bookmarks.removeRoot(root.id)
            }
            try await env.writer.rebuildCatalog()
            try await env.writer.clearAllAI()
            try await env.thumbnailCache.purge()
            await env.folderWatchManager.refresh()
            currentFolderID = nil
            currentFolder = nil
            items = []
            childFolders = []
            selection = []
            thumbnailImageCache.removeAll()
            resetAIProgress()
            await reloadRoots()
            await refreshSidebar()
            debugLog.info("Library cleared, AI queue reset")
        } catch {
            PicazhuLog.ui.error("clearLibrary failed: \(error.localizedDescription)")
        }
    }

    private func resetAIProgress() {
        aiProgress = AIProgressSnapshot()
        aiRateEMA = 0
        aiLastCompletedTimestamp = nil
    }

    func rootFolders(for rootID: WatchedRootID) -> [Folder] {
        (try? env.folderRepo.children(of: nil, rootID: rootID)) ?? []
    }

    func children(of folder: Folder) -> [Folder] {
        (try? env.folderRepo.children(of: folder.id, rootID: folder.rootID)) ?? []
    }

    func thumbnail(for item: MediaItem) -> NSImage? {
        if let cached = thumbnailImageCache[item.id] { return cached }
        let key = ThumbnailService.cacheKey(
            rootID: item.rootID,
            relativePath: item.relativePath,
            modifiedAt: item.modifiedAt,
            size: item.size
        )
        Task.detached { [cache = env.thumbnailCache] in
            if let data = await cache.read(key: key),
               let image = NSImage(data: data) {
                await MainActor.run {
                    self.thumbnailImageCache[item.id] = image
                }
            }
        }
        return thumbnailImageCache[item.id]
    }

    func inspectorInfo() -> InspectorItemInfo? {
        guard let id = selection.first,
              let item = items.first(where: { $0.id == id }) else { return nil }
        let dims: String?
        if let w = item.width, let h = item.height {
            dims = "\(w) × \(h)"
        } else {
            dims = nil
        }
        let dur: String?
        if let d = item.duration, d > 0 {
            let total = Int(d)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            dur = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        } else {
            dur = nil
        }
        return InspectorItemInfo(
            filename: item.filename,
            relativePath: item.relativePath,
            sizeText: formattedSize(item.size),
            kindLabel: item.kind == .image ? "Image" : "Video",
            dimensionsText: dims,
            durationText: dur,
            modifiedText: formattedDate(item.modifiedAt),
            cameraText: nil
        )
    }

    func urlForSelectedItem() async -> URL? {
        guard let id = selection.first,
              let item = items.first(where: { $0.id == id }),
              let root = try? env.rootRepo.find(id: item.rootID) else { return nil }
        do {
            let resolved = try await env.bookmarks.resolve(root)
            return resolved.url.appendingPathComponent(item.relativePath)
        } catch {
            return nil
        }
    }

    func quickLookSelection() async {
        guard let url = await urlForSelectedItem() else { return }
        let scope = try? SecurityScope(url: url.deletingLastPathComponent())
        _ = scope
        QuickLookController.shared.show(urls: [url])
    }

    func revealSelection() async {
        guard let url = await urlForSelectedItem() else { return }
        FileActions.revealInFinder(url)
    }

    func openSelection() async {
        guard let url = await urlForSelectedItem() else { return }
        FileActions.open(url)
    }

    func copyPathSelection() async {
        guard let url = await urlForSelectedItem() else { return }
        FileActions.copyPath(url)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    func refreshDiagnostics() async {
        do {
            let snap = try await env.healthChecks.snapshot()
            let rootRows = snap.roots.enumerated().map { idx, r in
                DiagnosticsRootRow(id: idx, name: r.displayName, access: r.accessState.rawValue)
            }
            diagnosticsDisplay = DiagnosticsDisplay(
                roots: rootRows,
                imageCount: snap.countsByKind[.image] ?? 0,
                videoCount: snap.countsByKind[.video] ?? 0,
                pendingThumbs: snap.pendingThumbs,
                pendingMetadata: snap.pendingMetadata,
                cacheSizeText: formattedSize(snap.thumbCacheBytes),
                dbSizeText: formattedSize(snap.dbFileBytes),
                integrity: snap.dbIntegrity,
                activeAIProvider: env.aiProvider.info.displayName,
                aiEnriched: snap.aiEnriched,
                aiPending: snap.aiPending,
                aiFailed: snap.aiFailed,
                aiEmbeddings: snap.aiEmbeddings
            )
        } catch {
            PicazhuLog.ui.error("refreshDiagnostics failed: \(error.localizedDescription)")
        }
    }

    func refreshOllamaStatus() async {
        debugLog.info("Checking Ollama: \(env.aiConfig.host) model=\(env.aiConfig.visionModel) hasKey=\(env.aiConfig.hasAPIKey)")
        ollamaStatus.state = .checking
        ollamaStatus.visionModel = env.aiConfig.visionModel
        ollamaStatus.embeddingModel = env.aiConfig.embeddingModel
        do {
            let tags = try await env.aiProvider.listModels()
            let names = tags.map(\.name)
            let visionPresent = names.contains(env.aiConfig.visionModel)
                || names.contains("\(env.aiConfig.visionModel):latest")
                || names.contains { $0.split(separator: ":").first.map(String.init) == env.aiConfig.visionModel }
            let embedPresent = env.aiConfig.embeddingModel.isEmpty
                || names.contains(env.aiConfig.embeddingModel)
                || names.contains("\(env.aiConfig.embeddingModel):latest")
                || names.contains { $0.split(separator: ":").first.map(String.init) == env.aiConfig.embeddingModel }
            if !visionPresent {
                ollamaStatus.state = .modelMissing(env.aiConfig.visionModel)
                ollamaStatus.lastCheckedAt = Date()
                return
            }
            if !embedPresent {
                ollamaStatus.state = .modelMissing(env.aiConfig.embeddingModel)
                ollamaStatus.lastCheckedAt = Date()
                return
            }

            let loaded = (try? await env.aiProvider.loadedModels()) ?? []
            if let match = loaded.first(where: { $0.name.contains(env.aiConfig.visionModel) || $0.model.contains(env.aiConfig.visionModel) }),
               let vram = match.sizeVRAM {
                ollamaStatus.state = .loaded(vramMB: Int(vram / 1_000_000))
            } else {
                ollamaStatus.state = .ready
            }
            ollamaStatus.lastCheckedAt = Date()
        } catch {
            ollamaStatus.state = .unreachable(error.localizedDescription)
            ollamaStatus.lastCheckedAt = Date()
            PicazhuLog.ai.error("Ollama status check failed: \(error.localizedDescription)")
        }
    }

    private func startOllamaHealthMonitor() {
        ollamaHealthTimer?.cancel()
        ollamaHealthTimer = Task { [weak self] in
            guard let self else { return }
            await self.refreshOllamaStatus()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.refreshOllamaStatus()
            }
        }
    }

    func clearAllAI() async {
        do {
            try await env.writer.clearAllAI()
            try? await env.embeddings.purge()
            await refreshDiagnostics()
        } catch {
            PicazhuLog.ui.error("clearAllAI failed: \(error.localizedDescription)")
        }
    }

    func purgeThumbnailCache() async {
        do {
            try await env.thumbnailCache.purge()
            await refreshDiagnostics()
        } catch {
            PicazhuLog.ui.error("purgeThumbnailCache failed: \(error.localizedDescription)")
        }
    }

    func rebuildCatalog() async {
        do {
            try await env.writer.rebuildCatalog()
            await env.coordinator.scanAllRoots()
            await env.coordinator.runEnrichmentPass()
            await reloadCurrentFolder()
            await refreshDiagnostics()
        } catch {
            PicazhuLog.ui.error("rebuildCatalog failed: \(error.localizedDescription)")
        }
    }

    private struct AIEnrichmentRow {
        let caption: String
        let tagsJSON: String
        let objectsJSON: String
        let scene: String
        let ocrText: String
        let confidence: Double
        let modelVersion: String
    }

    // MARK: - AI enrichment

    func enableAIForFolder(_ folder: Folder) async {
        debugLog.info("enableAIForFolder: \(folder.name) (id=\(folder.id.rawValue))")
        do {
            try await env.writer.setFolderAIEnabled(folder.id, enabled: true)

            let descendants = collectDescendantFolderIDs(from: folder)
            for id in descendants {
                try await env.writer.setFolderAIEnabled(id, enabled: true)
            }

            var itemIDs: [MediaItemID] = []
            for folderID in [folder.id] + descendants {
                let items = (try? env.mediaRepo.items(in: folderID)) ?? []
                itemIDs.append(contentsOf: items.map(\.id))
            }
            guard !itemIDs.isEmpty else { return }

            try await env.writer.enqueueAIJobs(itemIDs: itemIDs)
            debugLog.info("Enqueued \(itemIDs.count) AI jobs")
            await reloadCurrentFolder()

            aiProgress = AIProgressSnapshot(
                total: itemIDs.count,
                completed: 0,
                failed: 0,
                stage: .idle,
                currentItemName: "",
                ratePerSecond: 0,
                isPaused: false,
                isActive: true
            )

            await startEnrichmentWorkerIfNeeded()
        } catch {
            PicazhuLog.ui.error("enableAIForFolder failed: \(error.localizedDescription)")
        }
    }

    private func collectDescendantFolderIDs(from folder: Folder) -> [FolderID] {
        var result: [FolderID] = []
        let children = (try? env.folderRepo.children(of: folder.id, rootID: folder.rootID)) ?? []
        for child in children {
            result.append(child.id)
            result.append(contentsOf: collectDescendantFolderIDs(from: child))
        }
        return result
    }

    func pauseResumeAI() async {
        guard let coord = aiCoordinator else { return }
        if aiProgress.isPaused {
            aiProgress.isPaused = false
            await coord.resume()
            await startEnrichmentWorkerIfNeeded()
        } else {
            aiProgress.isPaused = true
            await coord.pause()
        }
    }

    func cancelAI() async {
        guard let coord = aiCoordinator else { return }
        await coord.stop()
        aiConsumerTask?.cancel()
        aiConsumerTask = nil
        aiRateTimer?.cancel()
        aiRateTimer = nil
        aiCoordinator = nil
        aiProgress.isActive = false
    }

    func invalidateAICoordinator() {
        if let coord = aiCoordinator {
            Task { await coord.stop() }
        }
        aiConsumerTask?.cancel()
        aiConsumerTask = nil
        aiRateTimer?.cancel()
        aiRateTimer = nil
        aiCoordinator = nil
        resetAIProgress()
        lastGridRefreshCompletion = 0
        debugLog.info("AI coordinator invalidated and stopped")
    }

    func applyAIConfig(_ cfg: OllamaProviderConfig) {
        invalidateAICoordinator()
        debugLog.info("Applying config: \(cfg.mode.rawValue) \(cfg.visionModel) host=\(cfg.host) hasKey=\(cfg.hasAPIKey)")
        Task {
            do {
                try await env.updateAIConfig(cfg)
                debugLog.info("Config saved to DB successfully")
                await refreshOllamaStatus()
            } catch {
                debugLog.error("applyAIConfig failed: \(error)")
            }
        }
    }

    private func startEnrichmentWorkerIfNeeded() async {
        if aiCoordinator == nil {
            debugLog.info("Creating new AI coordinator (provider=\(env.aiConfig.visionModel) host=\(env.aiConfig.host))")
            aiCoordinator = env.makeEnrichmentCoordinator()
            consumeProgressStream()
            startRateTicker()
        }
        guard let coord = aiCoordinator else { return }
        Task { [weak self] in
            await coord.run()
            guard let self else { return }
            self.aiProgress.stage = .idle
            self.aiProgress.currentItemName = ""
            self.aiProgress.isActive = self.aiProgress.completed < self.aiProgress.total
            if !self.aiProgress.isActive {
                self.aiConsumerTask?.cancel()
                self.aiRateTimer?.cancel()
                self.aiCoordinator = nil
            }
            await self.reloadCurrentFolder()
            self.debugLog.info("AI run finished: \(self.aiProgress.completed)/\(self.aiProgress.total) done")
        }
    }

    private func consumeProgressStream() {
        guard let coord = aiCoordinator else { return }
        aiConsumerTask?.cancel()
        aiConsumerTask = Task { [weak self] in
            guard let self else { return }
            for await tick in await coord.progressStream {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.applyProgressTick(tick)
                }
            }
        }
    }

    private var lastGridRefreshCompletion: Int = 0

    private func applyProgressTick(_ tick: ProgressTick) {
        let tickItemName = tick.currentItemName ?? ""
        if tickItemName.hasPrefix("Error:") {
            debugLog.error(tickItemName)
        } else if !tickItemName.isEmpty {
            debugLog.info("\(tick.stage.rawValue): \(tickItemName) (\(tick.completed)/\(tick.total))")
        }

        if tick.completed > lastGridRefreshCompletion {
            lastGridRefreshCompletion = tick.completed
            Task { await reloadCurrentFolder() }
        }

        if tickItemName != aiProgress.currentItemName && !tickItemName.isEmpty {
            aiItemStartTime = Date()
        }

        let now = Date()
        if tick.completed > aiProgress.completed {
            if let last = aiLastCompletedTimestamp {
                let dt = now.timeIntervalSince(last)
                if dt > 0 {
                    let instantRate = 1.0 / dt
                    if aiRateEMA == 0 {
                        aiRateEMA = instantRate
                    } else {
                        aiRateEMA = 0.2 * instantRate + 0.8 * aiRateEMA
                    }
                }
            }
            aiLastCompletedTimestamp = now
        }

        let itemName = tick.currentItemName ?? ""
        let isError = itemName.hasPrefix("Error:")
        aiProgress = AIProgressSnapshot(
            total: max(tick.total, aiProgress.total),
            completed: tick.completed,
            failed: tick.failed,
            stage: AIProgressSnapshot.Stage(rawValue: tick.stage.rawValue) ?? .idle,
            currentItemName: itemName,
            ratePerSecond: aiRateEMA,
            isPaused: aiProgress.isPaused,
            isActive: !isError && (tick.stage != .idle || tick.completed < tick.total),
            itemElapsed: Date().timeIntervalSince(aiItemStartTime)
        )
    }

    private func startRateTicker() {
        aiRateTimer?.cancel()
        aiRateTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await MainActor.run {
                    guard self.aiProgress.isActive else { return }
                    self.aiProgress = AIProgressSnapshot(
                        total: self.aiProgress.total,
                        completed: self.aiProgress.completed,
                        failed: self.aiProgress.failed,
                        stage: self.aiProgress.stage,
                        currentItemName: self.aiProgress.currentItemName,
                        ratePerSecond: self.aiRateEMA,
                        isPaused: self.aiProgress.isPaused,
                        isActive: self.aiProgress.isActive,
                        itemElapsed: Date().timeIntervalSince(self.aiItemStartTime)
                    )
                }
            }
        }
    }

    func inspectorAIInfo() -> AIInspectorInfo? {
        guard let id = selection.first else { return nil }
        do {
            let row: AIEnrichmentRow? = try env.catalog.reader.read { db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT caption, tags_json, objects_json, scene, ocr_text, confidence, model_version
                        FROM ai_enrichment WHERE item_id = ?
                    """,
                    arguments: [id.rawValue]
                ).map { row in
                    AIEnrichmentRow(
                        caption: row["caption"] as String? ?? "",
                        tagsJSON: row["tags_json"] as String? ?? "",
                        objectsJSON: row["objects_json"] as String? ?? "",
                        scene: row["scene"] as String? ?? "",
                        ocrText: row["ocr_text"] as String? ?? "",
                        confidence: row["confidence"] as Double? ?? 0,
                        modelVersion: row["model_version"] as String? ?? ""
                    )
                }
            }
            guard let row else { return nil }
            let tags = (try? JSONDecoder().decode([String].self, from: Data(row.tagsJSON.utf8))) ?? []
            let objects = (try? JSONDecoder().decode([String].self, from: Data(row.objectsJSON.utf8))) ?? []
            return AIInspectorInfo(
                caption: row.caption,
                tags: tags,
                objects: objects,
                scene: row.scene,
                ocrText: row.ocrText,
                confidence: row.confidence,
                modelVersion: row.modelVersion
            )
        } catch {
            return nil
        }
    }

    func pinFolder(_ folder: Folder) async {
        try? await env.writer.pinFolder(folder.id)
        await refreshSidebar()
    }

    func reanalyzeSelection() async {
        guard let id = selection.first,
              let item = try? env.mediaRepo.find(id: id) else { return }
        do {
            try await env.writer.setFolderAIEnabled(item.folderID, enabled: true)
            try await env.writer.enqueueAIJobs(itemIDs: [id])
            aiProgress = AIProgressSnapshot(
                total: max(1, aiProgress.total + 1),
                completed: aiProgress.completed,
                failed: aiProgress.failed,
                stage: .idle,
                currentItemName: item.filename,
                ratePerSecond: aiRateEMA,
                isPaused: false,
                isActive: true
            )
            await startEnrichmentWorkerIfNeeded()
        } catch {
            PicazhuLog.ui.error("reanalyze failed: \(error.localizedDescription)")
        }
    }

    func analyzeCurrentFolder() async {
        if !selection.isEmpty {
            await analyzeSelection()
            return
        }
        guard let folder = currentFolder else { return }
        await enableAIForFolder(folder)
    }

    func analyzeSelection() async {
        guard !selection.isEmpty else { return }
        let ids = Array(selection)
        do {
            for id in ids {
                if let item = try? env.mediaRepo.find(id: id) {
                    try await env.writer.setFolderAIEnabled(item.folderID, enabled: true)
                }
            }
            try await env.writer.enqueueAIJobs(itemIDs: ids)
            let firstName = (try? env.mediaRepo.find(id: ids[0])?.filename) ?? ""
            aiProgress = AIProgressSnapshot(
                total: max(ids.count, aiProgress.total),
                completed: aiProgress.completed,
                failed: aiProgress.failed,
                stage: .idle,
                currentItemName: firstName ?? "",
                ratePerSecond: aiRateEMA,
                isPaused: false,
                isActive: true
            )
            await startEnrichmentWorkerIfNeeded()
        } catch {
            PicazhuLog.ui.error("analyzeSelection failed: \(error.localizedDescription)")
        }
    }

    func clearSelectionAI() async {
        guard let id = selection.first else { return }
        do {
            try await env.catalog.writer.write { db in
                try db.execute(sql: "DELETE FROM ai_enrichment WHERE item_id = ?", arguments: [id.rawValue])
                try db.execute(sql: "DELETE FROM ai_embeddings WHERE item_id = ?", arguments: [id.rawValue])
            }
            try await env.writer.setItemAIState(id, .none)
        } catch {
            PicazhuLog.ui.error("clearSelectionAI failed: \(error.localizedDescription)")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
