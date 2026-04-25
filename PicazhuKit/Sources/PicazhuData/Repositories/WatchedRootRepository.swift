import Foundation
import GRDB
import PicazhuCore

public struct WatchedRootRepository: Sendable {
    private let reader: DatabaseReader

    public init(catalog: Catalog) {
        self.reader = catalog.reader
    }

    public func all() throws -> [WatchedRoot] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, display_name, bookmark, last_scan_at, access_state, created_at
                FROM watched_roots
                ORDER BY created_at ASC
            """)
            return rows.map(Self.rowToRoot)
        }
    }

    public func find(id: WatchedRootID) throws -> WatchedRoot? {
        try reader.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, display_name, bookmark, last_scan_at, access_state, created_at
                    FROM watched_roots WHERE id = ?
                """,
                arguments: [id.rawValue]
            ) else { return nil }
            return Self.rowToRoot(row)
        }
    }

    public func observeAll() -> ValueObservation<ValueReducers.Fetch<[WatchedRoot]>> {
        ValueObservation.tracking { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, display_name, bookmark, last_scan_at, access_state, created_at
                FROM watched_roots
                ORDER BY created_at ASC
            """)
            return rows.map(Self.rowToRoot)
        }
    }

    private static func rowToRoot(_ row: Row) -> WatchedRoot {
        WatchedRoot(
            id: WatchedRootID(rawValue: row["id"]),
            displayName: row["display_name"],
            bookmark: row["bookmark"],
            lastScanAt: (row["last_scan_at"] as Double?).map { Date(timeIntervalSince1970: $0) },
            accessState: RootAccessState(rawValue: row["access_state"]) ?? .ok,
            createdAt: Date(timeIntervalSince1970: row["created_at"])
        )
    }
}
