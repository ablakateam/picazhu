import Foundation
import GRDB
import PicazhuCore

public struct MediaItemRepository: Sendable {
    private let reader: DatabaseReader

    public init(catalog: Catalog) {
        self.reader = catalog.reader
    }

    public func items(in folderID: FolderID, limit: Int = 10000, offset: Int = 0) throws -> [MediaItem] {
        try reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM media_items
                    WHERE folder_id = ?
                    ORDER BY filename COLLATE NOCASE ASC
                    LIMIT ? OFFSET ?
                """,
                arguments: [folderID.rawValue, limit, offset]
            )
            return rows.map(Self.rowToItem)
        }
    }

    public func find(id: MediaItemID) throws -> MediaItem? {
        try reader.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM media_items WHERE id = ?",
                arguments: [id.rawValue]
            ) else { return nil }
            return Self.rowToItem(row)
        }
    }

    public func pendingThumbnailJobs(limit: Int = 64) throws -> [MediaItem] {
        try reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM media_items
                    WHERE thumb_state = 'pending'
                    ORDER BY id ASC
                    LIMIT ?
                """,
                arguments: [limit]
            )
            return rows.map(Self.rowToItem)
        }
    }

    public func pendingAIJobs(limit: Int = 64) throws -> [MediaItem] {
        try reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT m.* FROM media_items m
                    JOIN jobs j ON j.target_id = m.id
                    WHERE j.kind = 'ai' AND j.state IN ('queued', 'running')
                    ORDER BY j.enqueued_at ASC
                    LIMIT ?
                """,
                arguments: [limit]
            )
            return rows.map(Self.rowToItem)
        }
    }

    public func pendingMetadataJobs(limit: Int = 64) throws -> [MediaItem] {
        try reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM media_items
                    WHERE meta_state = 'pending'
                    ORDER BY id ASC
                    LIMIT ?
                """,
                arguments: [limit]
            )
            return rows.map(Self.rowToItem)
        }
    }

    public func countsByKind() throws -> [MediaKind: Int] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT kind, COUNT(*) AS c FROM media_items GROUP BY kind
            """)
            var result: [MediaKind: Int] = [:]
            for row in rows {
                if let k = MediaKind(rawValue: row["kind"]) {
                    result[k] = row["c"]
                }
            }
            return result
        }
    }

    public func observeFolderItems(_ folderID: FolderID) -> ValueObservation<ValueReducers.Fetch<[MediaItem]>> {
        ValueObservation.tracking { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM media_items
                    WHERE folder_id = ?
                    ORDER BY filename COLLATE NOCASE ASC
                """,
                arguments: [folderID.rawValue]
            )
            return rows.map(Self.rowToItem)
        }
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
