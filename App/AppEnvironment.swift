import Foundation
import SwiftUI
import GRDB
import PicazhuCore
import PicazhuData
import PicazhuIndexing
import PicazhuMedia
import PicazhuSearch
import PicazhuDiagnostics
import PicazhuAI
import PicazhuVision

@MainActor
@Observable
final class AppEnvironment {
    let catalog: Catalog
    let writer: CatalogWriter
    let bookmarks: BookmarkStore
    let thumbnailCache: ThumbnailCache
    let thumbnails: ThumbnailService
    let coordinator: IndexingCoordinator
    let folderWatchManager: FolderWatchManager
    let searchEngine: SearchEngine
    let savedSearches: SavedSearchStore
    let healthChecks: HealthChecks
    let rootRepo: WatchedRootRepository
    let folderRepo: FolderRepository
    let mediaRepo: MediaItemRepository
    let ocr: OCRService
    let embeddings: EmbeddingStore
    var aiConfig: OllamaProviderConfig
    var aiProviderID: Int64?
    var aiProvider: OllamaVisionProvider

    init() throws {
        let catalog = try Catalog(location: .applicationSupport)
        let writer = CatalogWriter(catalog: catalog)
        let cache = try ThumbnailCache.default()
        let thumbs = ThumbnailService(cache: cache)
        let bookmarks = BookmarkStore(catalog: catalog, writer: writer)
        let coordinator = IndexingCoordinator(
            catalog: catalog,
            writer: writer,
            bookmarks: bookmarks,
            thumbnails: thumbs
        )

        self.catalog = catalog
        self.writer = writer
        self.bookmarks = bookmarks
        self.thumbnailCache = cache
        self.thumbnails = thumbs
        self.coordinator = coordinator
        self.folderWatchManager = FolderWatchManager(
            catalog: catalog,
            bookmarks: bookmarks,
            coordinator: coordinator
        )
        self.searchEngine = SearchEngine(catalog: catalog)
        self.savedSearches = SavedSearchStore(catalog: catalog)
        self.healthChecks = HealthChecks(catalog: catalog, cache: cache)
        self.rootRepo = WatchedRootRepository(catalog: catalog)
        self.folderRepo = FolderRepository(catalog: catalog)
        self.mediaRepo = MediaItemRepository(catalog: catalog)

        self.ocr = OCRService()
        self.embeddings = try EmbeddingStore.default()

        let savedConfig = Self.loadSavedConfig(from: catalog)
        let config = savedConfig?.config ?? OllamaProviderConfig.default
        self.aiConfig = config
        self.aiProvider = OllamaVisionProvider(config: config)
        self.aiProviderID = savedConfig?.providerID

        PicazhuLog.app.info("AI config loaded: mode=\(config.mode.rawValue, privacy: .public) host=\(config.host, privacy: .public) vision=\(config.visionModel, privacy: .public) hasKey=\(config.hasAPIKey)")
    }

    private struct SavedProviderInfo {
        let providerID: Int64
        let config: OllamaProviderConfig
    }

    private static func loadSavedConfig(from catalog: Catalog) -> SavedProviderInfo? {
        do {
            return try catalog.reader.read { db -> SavedProviderInfo? in
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT id, config_json FROM ai_providers
                    WHERE enabled = 1
                    ORDER BY id DESC
                    LIMIT 1
                """) else { return nil }

                let id: Int64 = row["id"]
                let json: String = row["config_json"]
                guard let data = json.data(using: .utf8),
                      let config = try? JSONDecoder().decode(OllamaProviderConfig.self, from: data) else {
                    return nil
                }
                return SavedProviderInfo(providerID: id, config: config)
            }
        } catch {
            PicazhuLog.app.error("loadSavedConfig failed: \(error.localizedDescription)")
            return nil
        }
    }

    func makeEnrichmentCoordinator() -> AIEnrichmentCoordinator {
        let thumbSource = ThumbnailSourceAdapter(
            cache: thumbnailCache,
            thumbnails: thumbnails,
            rootRepo: rootRepo,
            bookmarks: bookmarks,
            mediaRepo: mediaRepo
        )
        let ocrAdapter = OCRAdapter(service: ocr)
        let embeddingAdapter = EmbeddingStoreAdapter(store: embeddings)
        return AIEnrichmentCoordinator(
            catalog: catalog,
            writer: writer,
            provider: aiProvider,
            providerID: aiProviderID,
            ocr: ocrAdapter,
            thumbnailSource: thumbSource,
            embeddings: embeddingAdapter
        )
    }

    func updateAIConfig(_ newConfig: OllamaProviderConfig) async throws {
        self.aiConfig = newConfig
        self.aiProvider = OllamaVisionProvider(config: newConfig)
        let json = try JSONEncoder().encode(newConfig)
        let jsonString = String(data: json, encoding: .utf8) ?? "{}"
        self.aiProviderID = try await writer.upsertAIProvider(
            kind: "ollama",
            name: "active",
            configJSON: jsonString,
            enabled: true
        )
        PicazhuLog.app.info("AI config saved: mode=\(newConfig.mode.rawValue, privacy: .public) host=\(newConfig.host, privacy: .public) vision=\(newConfig.visionModel, privacy: .public) hasKey=\(newConfig.hasAPIKey)")
    }
}
