import Foundation
import PicazhuCore

public struct OpenAIVisionProvider: AIProvider {
    public let info: AIProviderInfo
    public let config: OpenAIProviderConfig
    private let client: OpenAIClient

    public init(config: OpenAIProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.client = OpenAIClient(config: config, session: session)
        self.info = AIProviderInfo(
            kind: .openai,
            displayName: "OpenAI (\(config.visionModel))",
            modelVersion: config.visionModel
        )
    }

    public func validate() async throws {
        guard config.hasAPIKey else {
            throw OpenAIError.http(status: 401, body: "No API key configured")
        }
        _ = try await client.listModels()
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
            let d = try await describeDetailed(imageData: frame)
            if !d.caption.isEmpty { captions.append(d.caption) }
            if !d.scene.isEmpty { scenes.insert(d.scene) }
            confidences.append(d.confidence)
        }
        return AIDescription(
            caption: captions.joined(separator: " / "),
            scene: scenes.sorted().joined(separator: ", "),
            confidence: confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        )
    }

    public func tag(_ input: AIImageInput) async throws -> AITagSet {
        let d = try await describeDetailed(imageData: input.thumbnailData)
        return AITagSet(tags: d.tags, objects: d.objects)
    }

    public func describeDetailed(imageData: Data) async throws -> AIDetailedDescription {
        let b64 = imageData.base64EncodedString()

        let schema: [String: Any] = [
            "type": "object",
            "required": ["caption", "tags", "objects", "scene", "confidence"],
            "properties": [
                "caption": ["type": "string"],
                "tags": ["type": "array", "items": ["type": "string"]],
                "objects": ["type": "array", "items": ["type": "string"]],
                "scene": ["type": "string"],
                "confidence": ["type": "number"]
            ],
            "additionalProperties": false
        ]

        let raw = try await client.chatWithVision(
            model: config.visionModel,
            prompt: Self.systemPrompt,
            imageBase64: b64,
            jsonSchema: schema
        )

        guard let data = raw.data(using: .utf8) else {
            throw OpenAIError.decode("empty response")
        }

        struct Payload: Decodable {
            let caption: String
            let tags: [String]
            let objects: [String]
            let scene: String
            let confidence: Double
        }
        do {
            let p = try JSONDecoder().decode(Payload.self, from: data)
            return AIDetailedDescription(
                caption: p.caption,
                tags: Self.sanitize(p.tags),
                objects: Self.sanitize(p.objects),
                scene: p.scene,
                confidence: max(0, min(1, p.confidence))
            )
        } catch {
            throw OpenAIError.decode("\(error)")
        }
    }

    public func embedText(_ text: String) async throws -> AIEmbedding {
        guard !config.embeddingModel.isEmpty else {
            return AIEmbedding(dim: 0, vector: [])
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AIEmbedding(dim: 0, vector: []) }
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

    private static let systemPrompt = """
    You are an image indexer. Describe only what is visually present.

    Return JSON with:
    - caption: one short sentence in neutral tone describing the scene
    - tags: 5-15 lowercase single-word or short-phrase tags
    - objects: distinct physical objects clearly visible
    - scene: one short descriptor (indoor/outdoor, day/night, weather, location type)
    - confidence: 0.0 to 1.0 self-rated

    Rules: No speculation. No named people. No brand claims unless a logo is clearly visible.
    """

    private static func sanitize(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { raw in
            let cleaned = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { return nil }
            return cleaned
        }
    }
}
