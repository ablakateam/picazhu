import Foundation
import GRDB
import PicazhuCore
import PicazhuData

public struct SearchEngine: Sendable {
    private let reader: DatabaseReader

    public init(catalog: Catalog) {
        self.reader = catalog.reader
    }

    public func execute(_ query: SearchQuery, limit: Int = 500, offset: Int = 0) throws -> [MediaItem] {
        try reader.read { db in
            var sql = "SELECT m.* FROM media_items m"
            var args: [DatabaseValueConvertible] = []
            var wheres: [String] = []

            if !query.text.isEmpty {
                sql += " JOIN media_fts f ON f.rowid = m.id"
                wheres.append("media_fts MATCH ?")
                args.append(ftsQueryString(query.text))
            }

            switch query.folderScope {
            case .all:
                break
            case .folder(let folderID):
                wheres.append("m.folder_id = ?")
                args.append(folderID.rawValue)
            case .pinned:
                sql += " JOIN pinned_folders p ON p.folder_id = m.folder_id"
            }

            if !query.kinds.isEmpty {
                let placeholders = Array(repeating: "?", count: query.kinds.count).joined(separator: ",")
                wheres.append("m.kind IN (\(placeholders))")
                args.append(contentsOf: query.kinds.map { $0.rawValue })
            }

            if !query.extensions.isEmpty {
                let placeholders = Array(repeating: "?", count: query.extensions.count).joined(separator: ",")
                wheres.append("m.extension IN (\(placeholders))")
                args.append(contentsOf: query.extensions.map { $0.lowercased() })
            }

            if let range = query.dateRange {
                wheres.append("m.modified_at BETWEEN ? AND ?")
                args.append(range.lowerBound.timeIntervalSince1970)
                args.append(range.upperBound.timeIntervalSince1970)
            }

            if let range = query.sizeRange {
                wheres.append("m.size BETWEEN ? AND ?")
                args.append(range.lowerBound)
                args.append(range.upperBound)
            }

            if !wheres.isEmpty {
                sql += " WHERE " + wheres.joined(separator: " AND ")
            }
            sql += " ORDER BY m.modified_at DESC, m.id DESC LIMIT ? OFFSET ?"
            args.append(limit)
            args.append(offset)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map(Self.rowToItem)
        }
    }

    private func ftsQueryString(_ text: String) -> String {
        let tokens = text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { "\($0)*" }
        return tokens.joined(separator: " AND ")
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
