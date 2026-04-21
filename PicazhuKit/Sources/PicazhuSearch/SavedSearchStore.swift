import Foundation
import GRDB
import PicazhuCore
import PicazhuData

public struct SavedSearch: Sendable, Identifiable {
    public let id: SavedSearchID
    public let name: String
    public let query: SearchQuery
    public let pinned: Bool
    public let createdAt: Date
}

public struct SavedSearchStore: Sendable {
    private let catalog: Catalog

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    public func all() throws -> [SavedSearch] {
        try catalog.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, name, query_json, pinned, created_at FROM saved_searches
                ORDER BY pinned DESC, created_at DESC
            """)
            return rows.map { row in
                let data = (row["query_json"] as String).data(using: .utf8) ?? Data()
                let query = (try? JSONDecoder().decode(SearchQuery.self, from: data)) ?? SearchQuery()
                return SavedSearch(
                    id: SavedSearchID(rawValue: row["id"]),
                    name: row["name"],
                    query: query,
                    pinned: (row["pinned"] as Int) != 0,
                    createdAt: Date(timeIntervalSince1970: row["created_at"])
                )
            }
        }
    }

    public func save(name: String, query: SearchQuery, pinned: Bool = false) throws -> SavedSearchID {
        try catalog.writer.write { db in
            let json = try JSONEncoder().encode(query)
            let jsonString = String(data: json, encoding: .utf8) ?? "{}"
            try db.execute(
                sql: """
                    INSERT INTO saved_searches (name, query_json, pinned, created_at)
                    VALUES (?, ?, ?, ?)
                """,
                arguments: [name, jsonString, pinned ? 1 : 0, Date().timeIntervalSince1970]
            )
            return SavedSearchID(rawValue: db.lastInsertedRowID)
        }
    }

    public func delete(_ id: SavedSearchID) throws {
        try catalog.writer.write { db in
            try db.execute(sql: "DELETE FROM saved_searches WHERE id = ?", arguments: [id.rawValue])
        }
    }
}
