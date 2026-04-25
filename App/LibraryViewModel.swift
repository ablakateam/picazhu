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
    var showAbout: Bool = false
    var showHelp: Bool = false
    var showDeviceImport: Bool = false
    var showDuplicates: Bool = false
    var duplicateGroups: [DuplicateGroup] = []
    var isScanningDuplicates: Bool = false
    var aiProviderError: String? = nil
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

        loadFavorites()
        refreshTags()
        env.deviceImporter.startBrowsing()
        bootStatus = "Connecting AI…"
        try? await env.writer.resetStuckJobs()
        startOllamaHealthMonitor()

        if env.providerKind == "ollama" && env.ollamaConfig.mode == .local,
           let ollama = env.activeProvider as? OllamaVisionProvider {
            bootStatus = "Connecting to Ollama…"
            debugLog.info("Warming up local model: \(env.activeProvider.info.modelVersion)")
            do {
                try await ollama.warmup()
                debugLog.info("Model loaded into RAM")
            } catch {
                debugLog.warn("Ollama not available — AI features disabled until connected")
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
                        let emb = try await env.activeProvider.embedText(searchText)
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
                if filterState.favoritesOnly {
                    items = items.filter { favorites.contains($0.id) }
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
            refreshTags()
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
            cachedTags = []
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

    private func resolveSelectedItemWithScope() async -> (url: URL, rootURL: URL)? {
        guard let id = selection.first,
              let item = items.first(where: { $0.id == id }),
              let root = try? env.rootRepo.find(id: item.rootID) else { return nil }
        do {
            let resolved = try await env.bookmarks.resolve(root)
            let fileURL = resolved.url.appendingPathComponent(item.relativePath)
            return (fileURL, resolved.url)
        } catch {
            return nil
        }
    }

    func quickLookSelection() async {
        guard let result = await resolveSelectedItemWithScope() else { return }
        _ = result.rootURL.startAccessingSecurityScopedResource()
        QuickLookController.shared.show(urls: [result.url])
    }

    func revealSelection() async {
        guard let result = await resolveSelectedItemWithScope() else { return }
        let started = result.rootURL.startAccessingSecurityScopedResource()
        FileActions.revealInFinder(result.url)
        if started { result.rootURL.stopAccessingSecurityScopedResource() }
    }

    func openSelection() async {
        guard let result = await resolveSelectedItemWithScope() else { return }
        let started = result.rootURL.startAccessingSecurityScopedResource()
        FileActions.open(result.url)
        if started {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                result.rootURL.stopAccessingSecurityScopedResource()
            }
        }
    }

    func copyPathSelection() async {
        guard let result = await resolveSelectedItemWithScope() else { return }
        FileActions.copyPath(result.url)
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
                activeAIProvider: env.activeProvider.info.displayName,
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
        ollamaStatus.isCloud = env.isCloud
        ollamaStatus.providerLabel = env.providerKind == "openai" ? "OpenAI" : (env.isCloud ? "Cloud" : "Local")
        ollamaStatus.state = .checking
        ollamaStatus.visionModel = env.activeProvider.info.modelVersion

        if env.providerKind == "openai" {
            debugLog.info("Checking OpenAI: \(env.openaiConfig.visionModel)")
            do {
                try await env.activeProvider.validate()
                ollamaStatus.state = .ready
                ollamaStatus.lastCheckedAt = Date()
            } catch {
                ollamaStatus.state = .unreachable(error.localizedDescription)
                ollamaStatus.lastCheckedAt = Date()
            }
            return
        }

        debugLog.info("Checking Ollama: \(env.ollamaConfig.host) model=\(env.activeProvider.info.modelVersion)")
        ollamaStatus.embeddingModel = env.ollamaConfig.embeddingModel
        guard let ollama = env.activeProvider as? OllamaVisionProvider else {
            ollamaStatus.state = .unreachable("No Ollama provider")
            return
        }
        do {
            let tags = try await ollama.listModels()
            let names = tags.map(\.name)
            let modelVersion = env.activeProvider.info.modelVersion
            let visionPresent = names.contains(modelVersion)
                || names.contains("\(modelVersion):latest")
                || names.contains { $0.split(separator: ":").first.map(String.init) == modelVersion }
            let embedModel = env.ollamaConfig.embeddingModel
            let embedPresent = embedModel.isEmpty
                || names.contains(embedModel)
                || names.contains("\(embedModel):latest")
                || names.contains { $0.split(separator: ":").first.map(String.init) == embedModel }
            if !visionPresent {
                ollamaStatus.state = .modelMissing(modelVersion)
                ollamaStatus.lastCheckedAt = Date()
                return
            }
            if !embedPresent {
                ollamaStatus.state = .modelMissing(embedModel)
                ollamaStatus.lastCheckedAt = Date()
                return
            }

            let loaded = (try? await ollama.loadedModels()) ?? []
            if let match = loaded.first(where: { $0.name.contains(modelVersion) || $0.model.contains(modelVersion) }),
               let vram = match.sizeVRAM {
                ollamaStatus.state = .loaded(vramMB: Int(vram / 1_000_000))
            } else {
                ollamaStatus.state = .ready
            }
            ollamaStatus.lastCheckedAt = Date()
        } catch {
            ollamaStatus.state = .unreachable(error.localizedDescription)
            ollamaStatus.lastCheckedAt = Date()
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

    func inspectorLocation() -> PhotoLocation? {
        guard let id = selection.first else { return nil }
        do {
            return try env.catalog.reader.read { db -> PhotoLocation? in
                guard let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT gps_lat, gps_lon, camera_make, camera_model, lens,
                               focal_length, f_number, iso, exposure_time, capture_time
                        FROM metadata WHERE item_id = ?
                    """,
                    arguments: [id.rawValue]
                ) else { return nil }
                guard let lat = row["gps_lat"] as Double?,
                      let lon = row["gps_lon"] as Double?,
                      lat != 0, lon != 0 else { return nil }
                return PhotoLocation(
                    latitude: lat, longitude: lon,
                    cameraMake: row["camera_make"] as String?,
                    cameraModel: row["camera_model"] as String?,
                    lens: row["lens"] as String?,
                    focalLength: row["focal_length"] as Double?,
                    fNumber: row["f_number"] as Double?,
                    iso: row["iso"] as Int?,
                    exposureTime: row["exposure_time"] as Double?,
                    captureTime: (row["capture_time"] as Double?).map { Date(timeIntervalSince1970: $0) }
                )
            }
        } catch {
            return nil
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
            try await env.activeProvider.validate()
        } catch {
            debugLog.error("AI provider not available: \(error.localizedDescription)")
            aiProviderError = providerSetupMessage
            return
        }
        aiProviderError = nil

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

    var providerSetupMessage: String {
        switch env.providerKind {
        case "openai":
            return "OpenAI API key required. Open Settings (⚙) to configure."
        default:
            if env.ollamaConfig.mode == .cloud {
                return "Ollama Cloud API key required. Open Settings (⚙) to configure."
            } else {
                return "Ollama is not running. Install it from ollama.com and run \"ollama pull qwen3-vl:8b\" to enable AI features."
            }
        }
    }

    private func startEnrichmentWorkerIfNeeded() async {
        if aiCoordinator == nil {
            debugLog.info("Creating new AI coordinator (provider=\(env.activeProvider.info.modelVersion) host=\(env.ollamaConfig.host))")
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
            self.refreshTags()
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
            try await env.activeProvider.validate()
        } catch {
            aiProviderError = providerSetupMessage
            return
        }
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

    // MARK: - Batch operations

    func analyzeSelectedItems() async {
        await analyzeSelection()
    }

    func clearAIForSelected() async {
        for id in selection {
            do {
                try await env.catalog.writer.write { db in
                    try db.execute(sql: "DELETE FROM ai_enrichment WHERE item_id = ?", arguments: [id.rawValue])
                    try db.execute(sql: "DELETE FROM ai_embeddings WHERE item_id = ?", arguments: [id.rawValue])
                }
                try await env.writer.setItemAIState(id, .none)
            } catch {
                debugLog.error("clearAI for \(id.rawValue) failed: \(error)")
            }
        }
        await reloadCurrentFolder()
        debugLog.info("Cleared AI data for \(selection.count) items")
    }

    func copyPathsForSelected() {
        let paths = selection.compactMap { id -> String? in
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            return item.relativePath
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: "\n"), forType: .string)
        debugLog.info("Copied \(paths.count) paths")
    }

    func selectAll() {
        selection = Set(items.map(\.id))
    }

    func selectNone() {
        selection = []
    }

    // MARK: - Saved searches

    func saveCurrentSearch(name: String) async {
        guard !searchText.isEmpty || filterState.isActive else { return }
        let query = SearchQuery(
            text: searchText,
            kinds: filterState.kinds,
            dateRange: filterState.datePreset.dateRange,
            sizeRange: filterState.sizePreset.sizeRange,
            folderScope: searchGlobal ? .all : (currentFolderID.map { .folder($0) } ?? .all)
        )
        do {
            _ = try env.savedSearches.save(name: name, query: query)
            await refreshSidebar()
            debugLog.info("Saved search: \(name)")
        } catch {
            debugLog.error("Save search failed: \(error)")
        }
    }

    func applySavedSearch(_ search: SavedSearch) async {
        searchText = search.query.text
        filterState.kinds = search.query.kinds
        searchGlobal = search.query.folderScope == .all
        await reloadCurrentFolder()
    }

    // MARK: - Favorites

    var favorites: Set<MediaItemID> = []
    var cachedTags: [TagItem] = []

    func toggleFavorite(_ id: MediaItemID) async {
        if favorites.contains(id) {
            favorites.remove(id)
            try? await env.catalog.writer.write { db in
                try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: ["fav.\(id.rawValue)"])
            }
        } else {
            favorites.insert(id)
            try? await env.catalog.writer.write { db in
                try db.execute(sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, '1')", arguments: ["fav.\(id.rawValue)"])
            }
        }
    }

    func loadFavorites() {
        do {
            let rows = try env.catalog.reader.read { db in
                try Row.fetchAll(db, sql: "SELECT key FROM settings WHERE key LIKE 'fav.%' AND value = '1'")
            }
            favorites = Set(rows.compactMap { row -> MediaItemID? in
                let key: String = row["key"]
                guard let id = Int64(key.replacingOccurrences(of: "fav.", with: "")) else { return nil }
                return MediaItemID(rawValue: id)
            })
        } catch {
            debugLog.error("loadFavorites failed: \(error)")
        }
    }

    func isFavorite(_ id: MediaItemID) -> Bool {
        favorites.contains(id)
    }

    // MARK: - Tags

    func allTags() -> [(tag: String, count: Int)] {
        do {
            let rows = try env.catalog.reader.read { db in
                try Row.fetchAll(db, sql: "SELECT tags_json FROM ai_enrichment WHERE tags_json IS NOT NULL")
            }
            var tagCounts: [String: Int] = [:]
            for row in rows {
                let json: String = row["tags_json"]
                if let data = json.data(using: .utf8),
                   let tags = try? JSONDecoder().decode([String].self, from: data) {
                    for tag in tags {
                        tagCounts[tag, default: 0] += 1
                    }
                }
            }
            return tagCounts.map { (tag: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        } catch {
            return []
        }
    }

    func refreshTags() {
        cachedTags = allTags().prefix(60).map { TagItem(tag: $0.tag, count: $0.count) }
    }

    // MARK: - Duplicate detection

    func scanForDuplicates() async {
        guard !isScanningDuplicates else { return }
        isScanningDuplicates = true
        debugLog.info("Scanning for duplicates…")

        var hashPairs: [(id: MediaItemID, hash: UInt64)] = []
        for item in items {
            let key = ThumbnailService.cacheKey(
                rootID: item.rootID,
                relativePath: item.relativePath,
                modifiedAt: item.modifiedAt,
                size: item.size
            )
            if let data = await env.thumbnailCache.read(key: key),
               let hash = DuplicateDetector.pHash(imageData: data) {
                hashPairs.append((id: item.id, hash: hash))
            }
        }

        let groups = DuplicateDetector.findDuplicates(items: hashPairs, threshold: 0.9)
        duplicateGroups = groups
        isScanningDuplicates = false
        debugLog.info("Found \(groups.count) duplicate groups from \(hashPairs.count) items")

        if !groups.isEmpty {
            showDuplicates = true
        }
    }

    func searchByTag(_ tag: String) async {
        do {
            let rows: [Row] = try await env.catalog.reader.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT m.* FROM media_items m
                    JOIN ai_enrichment e ON e.item_id = m.id
                    WHERE e.tags_json LIKE ? OR e.objects_json LIKE ?
                    ORDER BY m.modified_at DESC
                """, arguments: ["%\"\(tag)\"%", "%\"\(tag)\"%"])
            }
            items = rows.map { row in
                MediaItem(
                    id: MediaItemID(rawValue: row["id"]),
                    folderID: FolderID(rawValue: row["folder_id"]),
                    rootID: WatchedRootID(rawValue: row["root_id"]),
                    filename: row["filename"],
                    relativePath: row["relative_path"],
                    fileExtension: row["extension"],
                    kind: MediaKind(rawValue: row["kind"]) ?? .image,
                    size: row["size"],
                    createdAt: (row["created_at"] as Double?).map { Date(timeIntervalSince1970: $0) },
                    modifiedAt: Date(timeIntervalSince1970: row["modified_at"]),
                    width: row["width"] as Int?,
                    height: row["height"] as Int?,
                    duration: row["duration"] as Double?,
                    orientation: row["orientation"] as Int?,
                    contentHash: row["content_hash"] as String?,
                    thumbState: LifecycleState(rawValue: row["thumb_state"]) ?? .pending,
                    metaState: LifecycleState(rawValue: row["meta_state"]) ?? .pending,
                    aiState: AIState(rawValue: row["ai_state"]) ?? .none,
                    indexedAt: Date(timeIntervalSince1970: row["indexed_at"])
                )
            }
            searchText = "#\(tag)"
            searchGlobal = true
            thumbnailImageCache.removeAll()
            debugLog.info("Tag search '\(tag)': \(items.count) results")
        } catch {
            debugLog.error("Tag search failed: \(error)")
        }
    }

    func deleteSavedSearch(_ search: SavedSearch) async {
        do {
            try env.savedSearches.delete(search.id)
            await refreshSidebar()
        } catch {
            debugLog.error("Delete search failed: \(error)")
        }
    }

    func analyzeSelection() async {
        guard !selection.isEmpty else { return }
        do {
            try await env.activeProvider.validate()
        } catch {
            aiProviderError = providerSetupMessage
            return
        }
        aiProviderError = nil
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
