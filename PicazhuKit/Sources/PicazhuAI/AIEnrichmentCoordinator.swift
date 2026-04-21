import Foundation
import PicazhuCore
import PicazhuData

public struct ProgressTick: Sendable {
    public enum Stage: String, Sendable {
        case ocr
        case vlm
        case embed
        case idle
    }
    public let total: Int
    public let completed: Int
    public let failed: Int
    public let stage: Stage
    public let currentItemName: String?
    public let elapsed: TimeInterval
    public init(total: Int, completed: Int, failed: Int, stage: Stage, currentItemName: String?, elapsed: TimeInterval) {
        self.total = total
        self.completed = completed
        self.failed = failed
        self.stage = stage
        self.currentItemName = currentItemName
        self.elapsed = elapsed
    }
}

public protocol AIThumbnailSource: Sendable {
    func thumbnailBytes(rootID: WatchedRootID, relativePath: String, modifiedAt: Date, size: Int64) async -> Data?
    func resolveFileURL(for itemID: MediaItemID) async -> URL?
}

public protocol AIOCRPerformer: Sendable {
    func recognize(imageData: Data) async throws -> String
    func recognize(fileURL: URL) async throws -> String
}

public actor AIEnrichmentCoordinator {
    public enum State: Sendable { case idle, running, paused }

    private let catalog: Catalog
    private let writer: CatalogWriter
    private let mediaRepo: MediaItemRepository
    private let provider: AIProvider
    private let providerID: Int64?
    private let ocr: AIOCRPerformer
    private let thumbnailSource: AIThumbnailSource
    private let embeddings: EmbeddingStoreWriter

    private var state: State = .idle
    public private(set) var lastError: String?
    private var totalEnqueued: Int = 0
    private var totalCompleted: Int = 0
    private var totalFailed: Int = 0
    private var startedAt: Date = Date()
    private var continuation: AsyncStream<ProgressTick>.Continuation?

    public let progressStream: AsyncStream<ProgressTick>

    public init(
        catalog: Catalog,
        writer: CatalogWriter,
        provider: AIProvider,
        providerID: Int64?,
        ocr: AIOCRPerformer,
        thumbnailSource: AIThumbnailSource,
        embeddings: EmbeddingStoreWriter
    ) {
        self.catalog = catalog
        self.writer = writer
        self.mediaRepo = MediaItemRepository(catalog: catalog)
        self.provider = provider
        self.providerID = providerID
        self.ocr = ocr
        self.thumbnailSource = thumbnailSource
        self.embeddings = embeddings

        var cont: AsyncStream<ProgressTick>.Continuation?
        self.progressStream = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    public func currentState() -> State { state }
    public func pause() { if state == .running { state = .paused } }
    public func resume() { if state == .paused { state = .running } }
    public func stop() {
        state = .idle
        emit(stage: .idle, itemName: nil)
    }

    public func run() async {
        guard state != .running else {
            PicazhuLog.ai.info("AIEnrichmentCoordinator.run: already running, skipping")
            return
        }
        state = .running
        startedAt = Date()
        if totalEnqueued == 0 {
            totalEnqueued = (try? mediaRepo.pendingAIJobs(limit: 1_000_000).count) ?? 0
            totalCompleted = 0
            totalFailed = 0
        }
        PicazhuLog.ai.info("AI run starting: \(self.totalEnqueued) jobs enqueued, provider=\(self.provider.info.displayName)")

        emit(stage: .idle, itemName: "Warming up model…")

        while state == .running {
            if state == .paused {
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
            if let next = try? await writer.nextAIJob() {
                PicazhuLog.ai.info("Picked job \(next.jobID) for item \(next.itemID.rawValue)")
                await process(jobID: next.jobID, itemID: next.itemID)
            } else {
                PicazhuLog.ai.info("No more queued AI jobs, exiting run loop")
                break
            }
        }

        if state == .running { state = .idle }
        emit(stage: .idle, itemName: nil)
        PicazhuLog.ai.info("AI run finished: completed=\(self.totalCompleted) failed=\(self.totalFailed)")
    }

    private func process(jobID: Int64, itemID: MediaItemID) async {
        guard let item = try? mediaRepo.find(id: itemID) else {
            PicazhuLog.ai.error("Job \(jobID): item \(itemID.rawValue) not found")
            try? await writer.completeAIJob(jobID, success: false, error: "item not found")
            totalFailed += 1
            return
        }

        if ProcessInfo.processInfo.thermalState == .critical {
            PicazhuLog.ai.warning("Thermal state critical, sleeping 2s")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        PicazhuLog.ai.info("Processing \(item.filename) (kind=\(item.kind.rawValue))")
        var ocrText = ""
        if item.kind == .image {
            emit(stage: .ocr, itemName: item.filename)
            if let fileURL = await thumbnailSource.resolveFileURL(for: itemID) {
                ocrText = (try? await ocr.recognize(fileURL: fileURL)) ?? ""
            }
        }

        emit(stage: .vlm, itemName: item.filename)
        var detailed: AIDetailedDescription?
        do {
            PicazhuLog.ai.info("Fetching thumbnail bytes for \(item.filename)")
            guard let thumbData = await thumbnailSource.thumbnailBytes(
                rootID: item.rootID,
                relativePath: item.relativePath,
                modifiedAt: item.modifiedAt,
                size: item.size
            ) else {
                PicazhuLog.ai.error("No thumbnail for \(item.filename)")
                throw OllamaError.transport("no thumbnail")
            }
            PicazhuLog.ai.info("Calling VLM for \(item.filename, privacy: .public) (\(thumbData.count) bytes)")

            let input = AIImageInput(itemID: itemID, thumbnailData: thumbData, originalURL: nil)
            if let ollama = provider as? OllamaVisionProvider {
                detailed = try await ollama.describeDetailed(imageData: thumbData)
            } else {
                let desc = try await provider.describeImage(input)
                let tags = try await provider.tag(input)
                detailed = AIDetailedDescription(
                    caption: desc.caption,
                    tags: tags.tags,
                    objects: tags.objects,
                    scene: desc.scene ?? "",
                    confidence: desc.confidence
                )
            }
            PicazhuLog.ai.info("VLM returned caption for \(item.filename, privacy: .public)")
        } catch {
            let errMsg = String(describing: error)
            try? await writer.completeAIJob(jobID, success: false, error: errMsg)
            try? await writer.setItemAIState(itemID, .failed)
            totalFailed += 1
            lastError = errMsg
            PicazhuLog.ai.error("VLM failed for \(item.filename, privacy: .public): \(errMsg, privacy: .public)")
            emit(stage: .idle, itemName: "Error: \(errMsg.prefix(80))")
            return
        }

        guard let detailed else {
            try? await writer.completeAIJob(jobID, success: false, error: "no description")
            totalFailed += 1
            return
        }

        emit(stage: .embed, itemName: item.filename)
        var embedding: AIEmbedding?
        if !detailed.caption.isEmpty {
            embedding = try? await provider.embedText(detailed.caption)
        }

        do {
            let tagsJSON = try? JSONEncoder().encode(detailed.tags)
            let objectsJSON = try? JSONEncoder().encode(detailed.objects)
            try await writer.writeAIEnrichment(
                itemID: itemID,
                providerID: providerID,
                modelVersion: provider.info.modelVersion,
                caption: detailed.caption,
                tagsJSON: tagsJSON.flatMap { String(data: $0, encoding: .utf8) },
                objectsJSON: objectsJSON.flatMap { String(data: $0, encoding: .utf8) },
                scene: detailed.scene,
                ocrText: ocrText.isEmpty ? nil : ocrText,
                confidence: detailed.confidence
            )

            if let embedding, embedding.dim > 0 {
                if let path = try? embeddings.write(itemID: itemID, vector: embedding.vector) {
                    try await writer.writeAIEmbedding(
                        itemID: itemID,
                        providerID: providerID,
                        modelVersion: provider.info.modelVersion,
                        dim: embedding.dim,
                        vectorPath: path
                    )
                }
            }

            try await writer.completeAIJob(jobID, success: true, error: nil)
            totalCompleted += 1
            PicazhuLog.ai.info("Job \(jobID) done for \(item.filename) (\(self.totalCompleted)/\(self.totalEnqueued))")
            emit(stage: .idle, itemName: item.filename)
        } catch {
            try? await writer.completeAIJob(jobID, success: false, error: "\(error)")
            try? await writer.setItemAIState(itemID, .failed)
            totalFailed += 1
            PicazhuLog.ai.error("Persist failed for \(item.filename, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func emit(stage: ProgressTick.Stage, itemName: String?) {
        let tick = ProgressTick(
            total: totalEnqueued,
            completed: totalCompleted,
            failed: totalFailed,
            stage: stage,
            currentItemName: itemName,
            elapsed: Date().timeIntervalSince(startedAt)
        )
        continuation?.yield(tick)
    }

    public func setTotal(_ total: Int) {
        totalEnqueued = total
    }
}

public protocol EmbeddingStoreWriter: Sendable {
    func write(itemID: MediaItemID, vector: [Float]) throws -> String
}
