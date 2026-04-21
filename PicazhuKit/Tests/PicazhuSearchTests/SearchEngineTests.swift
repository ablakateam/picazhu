import XCTest
@testable import PicazhuSearch
import PicazhuCore
import PicazhuData

final class SearchEngineTests: XCTestCase {
    func testSearchByFilename() async throws {
        let catalog = try Catalog(location: .inMemory)
        let writer = CatalogWriter(catalog: catalog)
        let rootID = try await writer.insertWatchedRoot(displayName: "Test", bookmark: Data())
        let folderID = try await writer.upsertFolder(
            rootID: rootID,
            parentID: nil,
            relativePath: "",
            name: "root",
            depth: 0
        )

        let drafts = [
            MediaItemDraft(
                rootID: rootID,
                folderRelativePath: "",
                filename: "sunset.jpg",
                relativePath: "sunset.jpg",
                fileExtension: "jpg",
                kind: .image,
                size: 100,
                createdAt: nil,
                modifiedAt: Date()
            ),
            MediaItemDraft(
                rootID: rootID,
                folderRelativePath: "",
                filename: "beach.jpg",
                relativePath: "beach.jpg",
                fileExtension: "jpg",
                kind: .image,
                size: 100,
                createdAt: nil,
                modifiedAt: Date()
            )
        ]
        try await writer.insertMediaDrafts(drafts, folderID: folderID)

        let repo = MediaItemRepository(catalog: catalog)
        for item in try repo.items(in: folderID) {
            try await writer.insertFTSRow(
                itemID: item.id,
                filename: item.filename,
                folderPath: ""
            )
        }

        let engine = SearchEngine(catalog: catalog)
        let results = try engine.execute(SearchQuery(text: "beach"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.filename, "beach.jpg")
    }
}
