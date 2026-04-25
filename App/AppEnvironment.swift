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
    let deviceImporter: DeviceImporter
    let ocr: OCRService
    let embeddings: EmbeddingStore
    var providerKind: String = "ollama"
    var ollamaConfig: OllamaProviderConfig
    var openaiConfig: OpenAIProviderConfig
    var aiProviderID: Int64?
    var activeProvider: any AIProvider

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

        self.deviceImporter = DeviceImporter()
        self.ocr = OCRService()
        self.embeddings = try EmbeddingStore.default()

        let saved = Self.loadSavedConfig(from: catalog)
        let kind = saved?.kind ?? "ollama"
        self.providerKind = kind

        if kind == "openai", let openaiJSON = saved?.configJSON,
           let data = openaiJSON.data(using: .utf8),
           let cfg = try? JSONDecoder().decode(OpenAIProviderConfig.self, from: data) {
            self.openaiConfig = cfg
            self.ollamaConfig = OllamaProviderConfig.default
            self.activeProvider = OpenAIVisionProvider(config: cfg)
        } else if let ollamaJSON = saved?.configJSON,
                  let data = ollamaJSON.data(using: .utf8),
                  let cfg = try? JSONDecoder().decode(OllamaProviderConfig.self, from: data) {
            self.ollamaConfig = cfg
            self.openaiConfig = OpenAIProviderConfig.default
            self.activeProvider = OllamaVisionProvider(config: cfg)
        } else {
            self.ollamaConfig = OllamaProviderConfig.default
            self.openaiConfig = OpenAIProviderConfig.default
            self.activeProvider = OllamaVisionProvider(config: OllamaProviderConfig.default)
        }
        self.aiProviderID = saved?.providerID

        PicazhuLog.app.info("AI provider loaded: kind=\(kind, privacy: .public)")
    }

    private struct SavedProviderInfo {
        let providerID: Int64
        let kind: String
        let configJSON: String
    }

    private static func loadSavedConfig(from catalog: Catalog) -> SavedProviderInfo? {
        do {
            return try catalog.reader.read { db -> SavedProviderInfo? in
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT id, kind, config_json FROM ai_providers
                    WHERE enabled = 1
                    ORDER BY id DESC
                    LIMIT 1
                """) else { return nil }
                return SavedProviderInfo(
                    providerID: row["id"],
                    kind: row["kind"],
                    configJSON: row["config_json"]
                )
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
            provider: activeProvider,
            providerID: aiProviderID,
            ocr: ocrAdapter,
            thumbnailSource: thumbSource,
            embeddings: embeddingAdapter
        )
    }

    func updateOllamaConfig(_ newConfig: OllamaProviderConfig) async throws {
        self.ollamaConfig = newConfig
        self.providerKind = "ollama"
        self.activeProvider = OllamaVisionProvider(config: newConfig)
        let json = try JSONEncoder().encode(newConfig)
        let jsonString = String(data: json, encoding: .utf8) ?? "{}"
        self.aiProviderID = try await writer.upsertAIProvider(
            kind: "ollama",
            name: "active",
            configJSON: jsonString,
            enabled: true
        )
        PicazhuLog.app.info("Ollama config saved: \(newConfig.mode.rawValue, privacy: .public) \(newConfig.visionModel, privacy: .public)")
    }

    func updateOpenAIConfig(_ newConfig: OpenAIProviderConfig) async throws {
        self.openaiConfig = newConfig
        self.providerKind = "openai"
        self.activeProvider = OpenAIVisionProvider(config: newConfig)
        let json = try JSONEncoder().encode(newConfig)
        let jsonString = String(data: json, encoding: .utf8) ?? "{}"
        self.aiProviderID = try await writer.upsertAIProvider(
            kind: "openai",
            name: "active",
            configJSON: jsonString,
            enabled: true
        )
        PicazhuLog.app.info("OpenAI config saved: \(newConfig.visionModel, privacy: .public)")
    }

    var isCloud: Bool {
        providerKind == "openai" || (providerKind == "ollama" && ollamaConfig.mode == .cloud)
    }
}
