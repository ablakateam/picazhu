import Foundation
import PicazhuCore
import PicazhuData
import PicazhuMedia

actor FolderPathMap {
    private var map: [String: FolderID] = [:]
    func get(_ key: String) -> FolderID? { map[key] }
    func set(_ key: String, _ id: FolderID) { map[key] = id }
    func contains(_ key: String) -> Bool { map[key] != nil }
}

public actor IndexingCoordinator {
    private let catalog: Catalog
    private let writer: CatalogWriter
    private let bookmarks: BookmarkStore
    private let thumbnails: ThumbnailService
    private let mediaRepo: MediaItemRepository
    private let rootRepo: WatchedRootRepository

    private var activeTasks: Set<WatchedRootID> = []

    public init(
        catalog: Catalog,
        writer: CatalogWriter,
        bookmarks: BookmarkStore,
        thumbnails: ThumbnailService
    ) {
        self.catalog = catalog
        self.writer = writer
        self.bookmarks = bookmarks
        self.thumbnails = thumbnails
        self.mediaRepo = MediaItemRepository(catalog: catalog)
        self.rootRepo = WatchedRootRepository(catalog: catalog)
    }

    public func scanAllRoots() async {
        let roots: [WatchedRoot]
        do {
            roots = try rootRepo.all()
        } catch {
            PicazhuLog.indexing.error("Failed to load roots: \(error.localizedDescription)")
            return
        }
        for root in roots {
            await scanRoot(root)
        }
    }

    public func scanRoot(_ root: WatchedRoot) async {
        guard !activeTasks.contains(root.id) else { return }
        activeTasks.insert(root.id)
        defer { activeTasks.remove(root.id) }

        do {
            let resolved = try await bookmarks.resolve(root)
            guard !resolved.isStale else {
                PicazhuLog.indexing.warning("Skipping stale root \(root.displayName)")
                return
            }
            let scope = try SecurityScope(url: resolved.url)
            _ = scope
            try await runFastScan(url: resolved.url, rootID: root.id)
            try await writer.markRootScanned(root.id)
        } catch {
            PicazhuLog.indexing.error("Scan failed for \(root.displayName): \(error.localizedDescription)")
        }
    }

    public func scanRootStreaming(
        _ root: WatchedRoot,
        onBatch: @Sendable (Int) async -> Void = { _ in }
    ) async {
        guard !activeTasks.contains(root.id) else { return }
        activeTasks.insert(root.id)
        defer { activeTasks.remove(root.id) }

        do {
            let resolved = try await bookmarks.resolve(root)
            guard !resolved.isStale else { return }
            let scope = try SecurityScope(url: resolved.url)
            _ = scope

            let rootURL = resolved.url
            let rootID = root.id
            let folderMap = FolderPathMap()
            let writer = self.writer

            _ = await Self.ensureFolderChain(
                path: "",
                rootID: rootID,
                rootURL: rootURL,
                folderMap: folderMap,
                writer: writer
            )

            let total = try await FileSystemScanner.scanStreaming(
                rootURL: rootURL,
                rootID: rootID
            ) { batch in
                for path in batch.folderRelativePaths {
                    _ = await Self.ensureFolderChain(
                        path: path,
                        rootID: rootID,
                        rootURL: rootURL,
                        folderMap: folderMap,
                        writer: writer
                    )
                }

                let grouped = Dictionary(grouping: batch.drafts) { $0.folderRelativePath }
                for (folderPath, batchDrafts) in grouped {
                    guard let folderID = await Self.ensureFolderChain(
                        path: folderPath,
                        rootID: rootID,
                        rootURL: rootURL,
                        folderMap: folderMap,
                        writer: writer
                    ) else {
                        PicazhuLog.indexing.error("Could not resolve folder for path \(folderPath)")
                        continue
                    }
                    do {
                        try await writer.insertMediaDrafts(batchDrafts, folderID: folderID)
                    } catch {
                        PicazhuLog.indexing.error("insertMediaDrafts failed for \(folderPath): \(error.localizedDescription)")
                    }
                }

                await onBatch(batch.drafts.count)
            }
            try await writer.markRootScanned(rootID)
            PicazhuLog.indexing.info("Streaming scan complete: \(total) media items for root \(rootID.rawValue)")
        } catch {
            PicazhuLog.indexing.error("Streaming scan failed for \(root.displayName): \(error.localizedDescription)")
        }
    }

    private static func ensureFolderChain(
        path: String,
        rootID: WatchedRootID,
        rootURL: URL,
        folderMap: FolderPathMap,
        writer: CatalogWriter
    ) async -> FolderID? {
        if let existing = await folderMap.get(path) {
            return existing
        }
        let parts = path.isEmpty ? [] : path.split(separator: "/").map(String.init)
        let parentID: FolderID?
        if parts.isEmpty {
            parentID = nil
        } else {
            let parentPath = parts.dropLast().joined(separator: "/")
            parentID = await ensureFolderChain(
                path: parentPath,
                rootID: rootID,
                rootURL: rootURL,
                folderMap: folderMap,
                writer: writer
            )
        }
        let name = parts.last ?? rootURL.lastPathComponent
        do {
            let id = try await writer.upsertFolder(
                rootID: rootID,
                parentID: parentID,
                relativePath: path,
                name: name,
                depth: parts.count
            )
            await folderMap.set(path, id)
            return id
        } catch {
            PicazhuLog.indexing.error("upsertFolder failed for \(path): \(error.localizedDescription)")
            return nil
        }
    }

    private func runFastScan(url: URL, rootID: WatchedRootID) async throws {
        let result = try FileSystemScanner.scan(rootURL: url, rootID: rootID)

        var folderIDMap: [String: FolderID] = [:]
        let sortedPaths = result.folderRelativePaths.sorted { $0.count < $1.count }
        for relPath in sortedPaths {
            let parts = relPath.isEmpty ? [] : relPath.split(separator: "/").map(String.init)
            let parentPath = parts.dropLast().joined(separator: "/")
            let parentID = parts.isEmpty ? nil : folderIDMap[parentPath]
            let name = parts.last ?? url.lastPathComponent
            let folderID = try await writer.upsertFolder(
                rootID: rootID,
                parentID: parentID,
                relativePath: relPath,
                name: name,
                depth: parts.count
            )
            folderIDMap[relPath] = folderID
        }

        let grouped = Dictionary(grouping: result.drafts) { $0.folderRelativePath }
        for (folderPath, drafts) in grouped {
            guard let folderID = folderIDMap[folderPath] else { continue }
            for chunk in drafts.chunked(into: 200) {
                try await writer.insertMediaDrafts(chunk, folderID: folderID)
            }
        }
        PicazhuLog.indexing.info("Fast scan finished for root \(rootID.rawValue): \(result.drafts.count) items, \(result.folderRelativePaths.count) folders")
    }

    public func runEnrichmentPass(maxConcurrency: Int = 4) async {
        do {
            let thumbJobs = try mediaRepo.pendingThumbnailJobs(limit: 64)
            await withTaskGroup(of: Void.self) { group in
                var inflight = 0
                for item in thumbJobs {
                    if inflight >= maxConcurrency {
                        await group.next()
                        inflight -= 1
                    }
                    group.addTask { [self] in
                        await self.generateThumbnail(for: item)
                    }
                    inflight += 1
                }
                await group.waitForAll()
            }

            let metaJobs = try mediaRepo.pendingMetadataJobs(limit: 64)
            for item in metaJobs {
                await extractMetadata(for: item)
            }
        } catch {
            PicazhuLog.indexing.error("Enrichment pass failed: \(error.localizedDescription)")
        }
    }

    private func generateThumbnail(for item: MediaItem) async {
        do {
            guard let root = try rootRepo.find(id: item.rootID) else { return }
            let resolved = try await bookmarks.resolve(root)
            let fileURL = resolved.url.appendingPathComponent(item.relativePath)
            let scope = try SecurityScope(url: resolved.url)
            _ = scope
            let result = try await thumbnails.thumbnail(
                for: fileURL,
                rootID: item.rootID,
                relativePath: item.relativePath,
                modifiedAt: item.modifiedAt,
                size: item.size
            )
            try await writer.insertThumbnailRecord(
                itemID: item.id,
                cacheKey: result.cacheKey,
                pixelSize: result.pixelSize
            )
            try await writer.setMediaState(item.id, thumb: .ready)
        } catch {
            try? await writer.setMediaState(item.id, thumb: .failed)
            PicazhuLog.indexing.error("Thumb failed for \(item.filename): \(error.localizedDescription)")
        }
    }

    private func extractMetadata(for item: MediaItem) async {
        do {
            guard let root = try rootRepo.find(id: item.rootID) else { return }
            let resolved = try await bookmarks.resolve(root)
            let fileURL = resolved.url.appendingPathComponent(item.relativePath)

            let scope = try SecurityScope(url: resolved.url)
            _ = scope
            switch item.kind {
            case .image:
                let m = try ImageMetadataReader.read(url: fileURL)
                try await writer.updateMediaDimensions(
                    item.id,
                    width: m.width,
                    height: m.height,
                    duration: nil,
                    orientation: m.orientation
                )
                try await writer.upsertMetadata(
                    itemID: item.id,
                    exifJSON: m.exifJSON,
                    cameraMake: m.cameraMake,
                    cameraModel: m.cameraModel,
                    lens: m.lens,
                    iso: m.iso,
                    fNumber: m.fNumber,
                    exposureTime: m.exposureTime,
                    focalLength: m.focalLength,
                    captureTime: m.captureTime,
                    gpsLat: m.gpsLat,
                    gpsLon: m.gpsLon,
                    codec: nil
                )
            case .video:
                let m = try await VideoMetadataReader.read(url: fileURL)
                try await writer.updateMediaDimensions(
                    item.id,
                    width: m.width,
                    height: m.height,
                    duration: m.duration,
                    orientation: nil
                )
                try await writer.upsertMetadata(
                    itemID: item.id,
                    exifJSON: nil,
                    cameraMake: nil,
                    cameraModel: nil,
                    lens: nil,
                    iso: nil,
                    fNumber: nil,
                    exposureTime: nil,
                    focalLength: nil,
                    captureTime: nil,
                    gpsLat: nil,
                    gpsLon: nil,
                    codec: m.codec
                )
            }
            try await writer.setMediaState(item.id, meta: .ready)

            let folderPath = (item.relativePath as NSString).deletingLastPathComponent
            try await writer.insertFTSRow(
                itemID: item.id,
                filename: item.filename,
                folderPath: folderPath
            )
        } catch {
            try? await writer.setMediaState(item.id, meta: .failed)
            PicazhuLog.indexing.error("Meta failed for \(item.filename): \(error.localizedDescription)")
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
