import Foundation
import GRDB
import PicazhuCore
import PicazhuData

public struct HybridSearchResult: Sendable {
    public let item: MediaItem
    public let ftsScore: Double
    public let semanticScore: Double
    public let fusedScore: Double
}

public struct HybridSearchEngine: Sendable {
    public let catalog: Catalog
    public let embeddings: EmbeddingStore
    public let ftsWeight: Double
    public let semanticWeight: Double

    public init(
        catalog: Catalog,
        embeddings: EmbeddingStore,
        ftsWeight: Double = 0.6,
        semanticWeight: Double = 0.4
    ) {
        self.catalog = catalog
        self.embeddings = embeddings
        self.ftsWeight = ftsWeight
        self.semanticWeight = semanticWeight
    }

    public func execute(
        _ query: SearchQuery,
        queryEmbedding: [Float]?,
        limit: Int = 500
    ) throws -> [HybridSearchResult] {
        let fts = SearchEngine(catalog: catalog)
        let lexical = try fts.execute(query, limit: limit, offset: 0)

        guard let queryEmbedding, !queryEmbedding.isEmpty else {
            return lexical.enumerated().map { idx, item in
                let n = max(1.0, Double(lexical.count))
                let rank = (n - Double(idx)) / n
                return HybridSearchResult(item: item, ftsScore: rank, semanticScore: 0, fusedScore: ftsWeight * rank)
            }
        }

        let embeddingsForItems = try catalog.reader.read { db -> [(Int64, String)] in
            try Row.fetchAll(db, sql: """
                SELECT item_id, vector_path FROM ai_embeddings
            """).map { row in
                (row["item_id"] as Int64, row["vector_path"] as String)
            }
        }

        var vectors: [MediaItemID: [Float]] = [:]
        for (itemID, path) in embeddingsForItems {
            if let vec = embeddings.read(path: path) {
                vectors[MediaItemID(rawValue: itemID)] = vec
            }
        }

        var semanticScores: [MediaItemID: Double] = [:]
        for (id, vec) in vectors {
            semanticScores[id] = Self.cosine(queryEmbedding, vec)
        }

        let lexicalIDs = Set(lexical.map(\.id))
        var candidates: [MediaItem] = lexical

        if candidates.count < limit {
            let missingIDs = Array(vectors.keys.filter { !lexicalIDs.contains($0) })
                .sorted { (semanticScores[$0] ?? 0) > (semanticScores[$1] ?? 0) }
                .prefix(limit - candidates.count)
            if !missingIDs.isEmpty {
                let items = try catalog.reader.read { db -> [MediaItem] in
                    var result: [MediaItem] = []
                    for id in missingIDs {
                        if let row = try Row.fetchOne(
                            db,
                            sql: "SELECT * FROM media_items WHERE id = ?",
                            arguments: [id.rawValue]
                        ) {
                            result.append(Self.rowToItem(row))
                        }
                    }
                    return result
                }
                candidates.append(contentsOf: items)
            }
        }

        let lexicalRanks: [MediaItemID: Double] = Dictionary(
            uniqueKeysWithValues: lexical.enumerated().map { idx, item in
                let n = max(1.0, Double(lexical.count))
                return (item.id, (n - Double(idx)) / n)
            }
        )

        let maxSem = semanticScores.values.max() ?? 1
        let minSem = semanticScores.values.min() ?? 0
        let semSpan = max(0.0001, maxSem - minSem)

        let results = candidates.map { item -> HybridSearchResult in
            let ftsScore = lexicalRanks[item.id] ?? 0
            let rawSem = semanticScores[item.id] ?? 0
            let normSem = (rawSem - minSem) / semSpan
            let fused = ftsWeight * ftsScore + semanticWeight * normSem
            return HybridSearchResult(
                item: item,
                ftsScore: ftsScore,
                semanticScore: rawSem,
                fusedScore: fused
            )
        }

        return results.sorted { $0.fusedScore > $1.fusedScore }
    }

    private static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var dot: Double = 0
        var na: Double = 0
        var nb: Double = 0
        for i in 0..<n {
            let x = Double(a[i])
            let y = Double(b[i])
            dot += x * y
            na += x * x
            nb += y * y
        }
        let denom = (na.squareRoot()) * (nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }

    private static func rowToItem(_ row: Row) -> MediaItem {
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
}
