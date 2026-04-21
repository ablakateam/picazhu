import Foundation
import GRDB
import PicazhuCore

public struct FolderRepository: Sendable {
    private let reader: DatabaseReader

    public init(catalog: Catalog) {
        self.reader = catalog.reader
    }

    public func children(of parentID: FolderID?, rootID: WatchedRootID) throws -> [Folder] {
        try reader.read { db in
            let rows: [Row]
            if let parent = parentID {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, root_id, parent_id, relative_path, name, depth, item_count, child_count
                        FROM folders
                        WHERE parent_id = ? AND root_id = ?
                        ORDER BY name COLLATE NOCASE ASC
                    """,
                    arguments: [parent.rawValue, rootID.rawValue]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, root_id, parent_id, relative_path, name, depth, item_count, child_count
                        FROM folders
                        WHERE parent_id IS NULL AND root_id = ?
                        ORDER BY name COLLATE NOCASE ASC
                    """,
                    arguments: [rootID.rawValue]
                )
            }
            return rows.map(Self.rowToFolder)
        }
    }

    public func firstNonEmpty(rootID: WatchedRootID) throws -> Folder? {
        try reader.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, root_id, parent_id, relative_path, name, depth, item_count, child_count
                    FROM folders
                    WHERE root_id = ? AND item_count > 0
                    ORDER BY depth ASC, name COLLATE NOCASE ASC
                    LIMIT 1
                """,
                arguments: [rootID.rawValue]
            ) else { return nil }
            return Self.rowToFolder(row)
        }
    }

    public func find(id: FolderID) throws -> Folder? {
        try reader.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, root_id, parent_id, relative_path, name, depth, item_count, child_count
                    FROM folders WHERE id = ?
                """,
                arguments: [id.rawValue]
            ) else { return nil }
            return Self.rowToFolder(row)
        }
    }

    public func pinned() throws -> [Folder] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT f.id, f.root_id, f.parent_id, f.relative_path, f.name, f.depth, f.item_count, f.child_count
                FROM pinned_folders p
                JOIN folders f ON f.id = p.folder_id
                ORDER BY p.pinned_at DESC
            """)
            return rows.map(Self.rowToFolder)
        }
    }

    public func recent(limit: Int = 10) throws -> [Folder] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT f.id, f.root_id, f.parent_id, f.relative_path, f.name, f.depth, f.item_count, f.child_count
                FROM recent_folders r
                JOIN folders f ON f.id = r.folder_id
                ORDER BY r.visited_at DESC
                LIMIT \(limit)
            """)
            return rows.map(Self.rowToFolder)
        }
    }

    private static func rowToFolder(_ row: Row) -> Folder {
        Folder(
            id: FolderID(rawValue: row["id"]),
            rootID: WatchedRootID(rawValue: row["root_id"]),
            parentID: (row["parent_id"] as Int64?).map { FolderID(rawValue: $0) },
            relativePath: row["relative_path"],
            name: row["name"],
            depth: row["depth"],
            itemCount: row["item_count"],
            childCount: row["child_count"]
        )
    }
}
