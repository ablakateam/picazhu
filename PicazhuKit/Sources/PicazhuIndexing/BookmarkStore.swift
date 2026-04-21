import Foundation
import AppKit
import PicazhuCore
import PicazhuData

public struct ResolvedRoot: Sendable {
    public let root: WatchedRoot
    public let url: URL
    public let isStale: Bool
}

public actor BookmarkStore {
    private let catalog: Catalog
    private let writer: CatalogWriter

    public init(catalog: Catalog, writer: CatalogWriter) {
        self.catalog = catalog
        self.writer = writer
    }

    public func addRoot(from url: URL, displayName: String? = nil) async throws -> WatchedRootID {
        let data: Data
        do {
            data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw PicazhuError.bookmarkResolveFailed(underlying: "\(error)")
        }
        let name = displayName ?? url.lastPathComponent
        return try await writer.insertWatchedRoot(displayName: name, bookmark: data)
    }

    public func resolve(_ root: WatchedRoot) async throws -> ResolvedRoot {
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: root.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                try await writer.updateRootAccessState(root.id, .stale)
            } else if root.accessState != .ok {
                try await writer.updateRootAccessState(root.id, .ok)
            }
            return ResolvedRoot(root: root, url: url, isStale: stale)
        } catch {
            try await writer.updateRootAccessState(root.id, .denied)
            throw PicazhuError.bookmarkResolveFailed(underlying: "\(error)")
        }
    }

    public func removeRoot(_ id: WatchedRootID) async throws {
        try await writer.deleteWatchedRoot(id)
    }
}
