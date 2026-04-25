import Foundation
import PicazhuCore

public protocol AIProvider: Sendable {
    var info: AIProviderInfo { get }
    func validate() async throws
    func describeImage(_ input: AIImageInput) async throws -> AIDescription
    func describeVideoFrames(_ input: AIVideoInput) async throws -> AIDescription
    func tag(_ input: AIImageInput) async throws -> AITagSet
    func embedText(_ text: String) async throws -> AIEmbedding
    func embed(_ input: AIImageInput) async throws -> AIEmbedding
    func rerank(_ input: AIRerankInput) async throws -> AIRerankResult
    func mergeOCR(_ input: AIOCRInput) async throws -> AIOCRResult
}

public struct StubProvider: AIProvider {
    public let info = AIProviderInfo(kind: .stub, displayName: "Disabled", modelVersion: "n/a")
    public init() {}
    public func validate() async throws {}
    public func describeImage(_ input: AIImageInput) async throws -> AIDescription {
        AIDescription(caption: "", scene: nil, confidence: 0)
    }
    public func describeVideoFrames(_ input: AIVideoInput) async throws -> AIDescription {
        AIDescription(caption: "", scene: nil, confidence: 0)
    }
    public func tag(_ input: AIImageInput) async throws -> AITagSet {
        AITagSet(tags: [], objects: [])
    }
    public func embedText(_ text: String) async throws -> AIEmbedding {
        AIEmbedding(dim: 0, vector: [])
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
}

public struct AIDetailedDescription: Sendable {
    public let caption: String
    public let tags: [String]
    public let objects: [String]
    public let scene: String
    public let confidence: Double
    public init(caption: String, tags: [String], objects: [String], scene: String, confidence: Double) {
        self.caption = caption
        self.tags = tags
        self.objects = objects
        self.scene = scene
        self.confidence = confidence
    }
}
