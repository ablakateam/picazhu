import Foundation
import PicazhuCore

public struct OllamaVisionProvider: AIProvider {
    public let info: AIProviderInfo
    public let config: OllamaProviderConfig
    private let client: OllamaClient

    public init(config: OllamaProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.client = OllamaClient(config: config, session: session)
        self.info = AIProviderInfo(
            kind: .ollama,
            displayName: "Ollama (\(config.visionModel))",
            modelVersion: config.visionModel
        )
    }

    public func ping() async throws { try await client.ping() }
    public func loadedModels() async throws -> [OllamaLoadedModel] { try await client.loadedModels() }
    public func listModels() async throws -> [OllamaModelInfo] { try await client.listModels() }
    public func warmup() async throws { try await client.warmup(model: config.visionModel) }
    public func unload() async { await client.unload(model: config.visionModel) }

    public func validate() async throws {
        let models = try await client.listModels()
        let names = models.map(\.name)
        if !Self.hasModel(names, config.visionModel) {
            throw OllamaError.modelNotFound("Vision model \(config.visionModel) not found. Run: ollama pull \(config.visionModel)")
        }
        if !config.embeddingModel.isEmpty && !Self.hasModel(names, config.embeddingModel) {
            throw OllamaError.modelNotFound("Embedding model \(config.embeddingModel) not found. Run: ollama pull \(config.embeddingModel)")
        }
    }

    private static func hasModel(_ installed: [String], _ requested: String) -> Bool {
        if installed.contains(requested) { return true }
        if !requested.contains(":") {
            let withLatest = "\(requested):latest"
            if installed.contains(withLatest) { return true }
        }
        let normalizedRequested = requested.contains(":") ? requested : "\(requested):latest"
        return installed.contains { name in
            name == normalizedRequested || name.split(separator: ":").first.map(String.init) == requested
        }
    }

    public func describeImage(_ input: AIImageInput) async throws -> AIDescription {
        let detailed = try await describeDetailed(imageData: input.thumbnailData)
        return AIDescription(caption: detailed.caption, scene: detailed.scene, confidence: detailed.confidence)
    }

    public func describeVideoFrames(_ input: AIVideoInput) async throws -> AIDescription {
        guard !input.frames.isEmpty else {
            return AIDescription(caption: "", scene: nil, confidence: 0)
        }
        var captions: [String] = []
        var scenes: Set<String> = []
        var confidences: [Double] = []
        for frame in input.frames {
            let detailed = try await describeDetailed(imageData: frame)
            if !detailed.caption.isEmpty { captions.append(detailed.caption) }
            if !detailed.scene.isEmpty { scenes.insert(detailed.scene) }
            confidences.append(detailed.confidence)
        }
        let mergedCaption = captions.joined(separator: " / ")
        let mergedScene = scenes.sorted().joined(separator: ", ")
        let avgConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        return AIDescription(caption: mergedCaption, scene: mergedScene, confidence: avgConfidence)
    }

    public func tag(_ input: AIImageInput) async throws -> AITagSet {
        let detailed = try await describeDetailed(imageData: input.thumbnailData)
        return AITagSet(tags: detailed.tags, objects: detailed.objects)
    }

    public func describeDetailed(imageData: Data) async throws -> AIDetailedDescription {
        let prompt = Self.systemPrompt
        let schema: [String: Any] = [
            "type": "object",
            "required": ["caption", "tags", "objects", "scene", "confidence"],
            "properties": [
                "caption":    ["type": "string"],
                "tags":       ["type": "array", "items": ["type": "string"]],
                "objects":    ["type": "array", "items": ["type": "string"]],
                "scene":      ["type": "string"],
                "confidence": ["type": "number"]
            ]
        ]

        let raw = try await client.chat(
            model: config.visionModel,
            prompt: prompt,
            images: [imageData],
            format: schema
        )

        guard let data = raw.data(using: .utf8) else {
            throw OllamaError.schemaViolation("empty response")
        }

        struct Payload: Decodable {
            let caption: String
            let tags: [String]
            let objects: [String]
            let scene: String
            let confidence: Double
        }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return AIDetailedDescription(
                caption: payload.caption,
                tags: Self.sanitizeList(payload.tags),
                objects: Self.sanitizeList(payload.objects),
                scene: payload.scene,
                confidence: max(0, min(1, payload.confidence))
            )
        } catch {
            throw OllamaError.schemaViolation("\(error)")
        }
    }

    public func embedText(_ text: String) async throws -> AIEmbedding {
        guard !config.embeddingModel.isEmpty else {
            return AIEmbedding(dim: 0, vector: [])
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AIEmbedding(dim: 0, vector: [])
        }
        let vector = try await client.embed(model: config.embeddingModel, input: trimmed)
        return AIEmbedding(dim: vector.count, vector: vector)
    }

    public func embed(_ input: AIImageInput) async throws -> AIEmbedding {
        AIEmbedding(dim: 0, vector: [])
    }

    public func rerank(_ input: AIRerankInput) async throws -> AIRerankResult {
        AIRerankResult(orderedIDs: input.candidateIDs)
    }

    public func mergeOCR(_ input: AIOCRInput) async throws -> AIOCRResult {
        AIOCRResult(mergedText: input.existingText ?? "")
    }

    private static let systemPrompt: String = """
    You are an image indexer. Describe only what is visually present.

    Return JSON matching the required schema.

    Rules:
    - caption: one short sentence in neutral tone, describing the scene.
    - tags: 5-15 lowercase single-word or short-phrase tags.
    - objects: distinct physical objects clearly visible (dog, chair, car, sign).
    - scene: one short descriptor (indoor/outdoor, day/night, weather, location type).
    - confidence: 0.0 to 1.0 self-rated.
    - No speculation. No named people. No brand claims unless a logo is clearly visible.
    - Prefer concrete nouns over abstract ones.
    """

    private static func sanitizeList(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in items {
            let cleaned = raw
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty { continue }
            if seen.insert(cleaned).inserted {
                result.append(cleaned)
            }
        }
        return result
    }
}
