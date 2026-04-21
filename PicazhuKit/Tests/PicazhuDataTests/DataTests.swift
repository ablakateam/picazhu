import XCTest
@testable import PicazhuData
import PicazhuCore
import GRDB

final class DataTests: XCTestCase {
    func testMigrationAppliesCleanly() async throws {
        let catalog = try Catalog(location: .inMemory)
        try await catalog.reader.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
            XCTAssertTrue(tables.contains("media_items"))
            XCTAssertTrue(tables.contains("folders"))
            XCTAssertTrue(tables.contains("watched_roots"))
            XCTAssertTrue(tables.contains("media_fts"))
            XCTAssertTrue(tables.contains("ai_enrichment"))
        }
    }

    func testWriteAIEnrichmentReWriteSucceeds() async throws {
        // Regression test for the contentless FTS5 DELETE bug.
        // writeAIEnrichment must succeed even when an FTS row already exists for the item.
        let catalog = try Catalog(location: .inMemory)
        let writer = CatalogWriter(catalog: catalog)

        let rootID = try await writer.insertWatchedRoot(displayName: "T", bookmark: Data())
        let folderID = try await writer.upsertFolder(rootID: rootID, parentID: nil, relativePath: "", name: "root", depth: 0)
        let draft = MediaItemDraft(
            rootID: rootID, folderRelativePath: "",
            filename: "park.jpg", relativePath: "park.jpg",
            fileExtension: "jpg", kind: .image, size: 1,
            createdAt: nil, modifiedAt: Date()
        )
        try await writer.insertMediaDrafts([draft], folderID: folderID)
        let items = try MediaItemRepository(catalog: catalog).items(in: folderID)
        let itemID = items[0].id

        // First write — no existing row, should succeed.
        try await writer.insertFTSRow(itemID: itemID, filename: "park.jpg", folderPath: "")
        try await writer.writeAIEnrichment(
            itemID: itemID, providerID: nil, modelVersion: "test",
            caption: "a dog in the park",
            tagsJSON: "[\"dog\",\"park\"]",
            objectsJSON: "[\"dog\",\"bench\"]",
            scene: "outdoor day",
            ocrText: nil, confidence: 0.9
        )

        // Second write — row already exists, this previously crashed
        // because contentless FTS5 cannot DELETE without contentless_delete=1.
        try await writer.writeAIEnrichment(
            itemID: itemID, providerID: nil, modelVersion: "test",
            caption: "a dog playing fetch",
            tagsJSON: "[\"dog\",\"fetch\"]",
            objectsJSON: "[\"dog\",\"ball\"]",
            scene: "outdoor day",
            ocrText: nil, confidence: 0.95
        )

        let hits: Int = try await catalog.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM media_fts WHERE media_fts MATCH ?", arguments: ["fetch*"]) ?? 0
        }
        XCTAssertEqual(hits, 1, "Re-writing AI enrichment must update the FTS row, not crash")
    }

    func testInsertAndFTSRoundTrip() async throws {
        let catalog = try Catalog(location: .inMemory)
        let writer = CatalogWriter(catalog: catalog)
        let bookmark = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let rootID = try await writer.insertWatchedRoot(displayName: "Test", bookmark: bookmark)
        let folderID = try await writer.upsertFolder(
            rootID: rootID,
            parentID: nil,
            relativePath: "",
            name: "root",
            depth: 0
        )
        let draft = MediaItemDraft(
            rootID: rootID,
            folderRelativePath: "",
            filename: "beach.jpg",
            relativePath: "beach.jpg",
            fileExtension: "jpg",
            kind: .image,
            size: 1234,
            createdAt: nil,
            modifiedAt: Date()
        )
        try await writer.insertMediaDrafts([draft], folderID: folderID)

        let repo = MediaItemRepository(catalog: catalog)
        let items = try repo.items(in: folderID)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.filename, "beach.jpg")

        try await writer.insertFTSRow(
            itemID: items[0].id,
            filename: "beach.jpg",
            folderPath: ""
        )

        let hits: Int = try await catalog.reader.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM media_fts WHERE media_fts MATCH ?",
                arguments: ["beach*"]
            ) ?? 0
        }
        XCTAssertEqual(hits, 1)
    }
}
