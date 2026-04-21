import Foundation
import GRDB
import PicazhuCore
import PicazhuData
import PicazhuMedia

public struct DiagnosticsSnapshot: Sendable {
    public var roots: [WatchedRoot]
    public var countsByKind: [MediaKind: Int]
    public var pendingThumbs: Int
    public var pendingMetadata: Int
    public var thumbCacheBytes: Int64
    public var dbFileBytes: Int64
    public var dbIntegrity: String
    public var aiEnriched: Int
    public var aiPending: Int
    public var aiFailed: Int
    public var aiEmbeddings: Int
}

public struct HealthChecks: Sendable {
    private let catalog: Catalog
    private let rootRepo: WatchedRootRepository
    private let cache: ThumbnailCache

    public init(catalog: Catalog, cache: ThumbnailCache) {
        self.catalog = catalog
        self.rootRepo = WatchedRootRepository(catalog: catalog)
        self.cache = cache
    }

    public func snapshot() async throws -> DiagnosticsSnapshot {
        let roots = try rootRepo.all()
        let repo = MediaItemRepository(catalog: catalog)
        let counts = try repo.countsByKind()

        let (pendingThumbs, pendingMeta, dbSize, integrity, aiEnriched, aiPending, aiFailed, aiEmbeds): (Int, Int, Int64, String, Int, Int, Int, Int) = try await catalog.reader.read { db in
            let t = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM media_items WHERE thumb_state = 'pending'") ?? 0
            let m = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM media_items WHERE meta_state = 'pending'") ?? 0
            let pageSize = try Int64.fetchOne(db, sql: "PRAGMA page_size") ?? 0
            let pageCount = try Int64.fetchOne(db, sql: "PRAGMA page_count") ?? 0
            let check = try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? "unknown"
            let enriched = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_enrichment") ?? 0
            let pending = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs WHERE kind='ai' AND state='queued'") ?? 0
            let failed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs WHERE kind='ai' AND state='failed'") ?? 0
            let embeds = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_embeddings") ?? 0
            return (t, m, pageSize * pageCount, check, enriched, pending, failed, embeds)
        }

        let cacheBytes = await cache.sizeBytes()

        return DiagnosticsSnapshot(
            roots: roots,
            countsByKind: counts,
            pendingThumbs: pendingThumbs,
            pendingMetadata: pendingMeta,
            thumbCacheBytes: cacheBytes,
            dbFileBytes: dbSize,
            dbIntegrity: integrity,
            aiEnriched: aiEnriched,
            aiPending: aiPending,
            aiFailed: aiFailed,
            aiEmbeddings: aiEmbeds
        )
    }
}
