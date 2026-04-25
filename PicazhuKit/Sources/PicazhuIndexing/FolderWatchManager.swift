import Foundation
import PicazhuCore
import PicazhuData

public actor FolderWatchManager {
    private let bookmarks: BookmarkStore
    private let coordinator: IndexingCoordinator
    private let rootRepo: WatchedRootRepository

    private var watchers: [WatchedRootID: FolderWatcher] = [:]
    private var debounceTasks: [WatchedRootID: Task<Void, Never>] = [:]

    public init(
        catalog: Catalog,
        bookmarks: BookmarkStore,
        coordinator: IndexingCoordinator
    ) {
        self.bookmarks = bookmarks
        self.coordinator = coordinator
        self.rootRepo = WatchedRootRepository(catalog: catalog)
    }

    public func refresh() async {
        let roots: [WatchedRoot]
        do {
            roots = try rootRepo.all()
        } catch {
            PicazhuLog.indexing.error("watcher refresh roots failed: \(error.localizedDescription)")
            return
        }

        let currentIDs = Set(roots.map(\.id))
        for id in watchers.keys where !currentIDs.contains(id) {
            watchers[id]?.stop()
            watchers.removeValue(forKey: id)
        }

        for root in roots where watchers[root.id] == nil {
            do {
                let resolved = try await bookmarks.resolve(root)
                guard !resolved.isStale else { continue }
                let rootID = root.id
                let watcher = FolderWatcher(url: resolved.url) { [weak self] _ in
                    guard let self else { return }
                    Task { await self.onEvent(rootID: rootID) }
                }
                watcher.start()
                watchers[root.id] = watcher
            } catch {
                PicazhuLog.indexing.error("watcher attach failed for \(root.displayName): \(error.localizedDescription)")
            }
        }
    }

    public func stopAll() {
        for (_, w) in watchers { w.stop() }
        watchers.removeAll()
        for (_, t) in debounceTasks { t.cancel() }
        debounceTasks.removeAll()
    }

    private func onEvent(rootID: WatchedRootID) async {
        debounceTasks[rootID]?.cancel()
        debounceTasks[rootID] = Task { [coordinator, rootRepo] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard let root = try? rootRepo.find(id: rootID) else { return }
            await coordinator.scanRoot(root)
            await coordinator.runEnrichmentPass()
        }
    }
}
