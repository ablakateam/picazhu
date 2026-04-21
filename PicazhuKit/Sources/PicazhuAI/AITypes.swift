import Foundation
import PicazhuCore

public struct AIProviderInfo: Sendable, Hashable {
    public enum Kind: String, Sendable, Codable { case openai, ollama, stub }
    public let kind: Kind
    public let displayName: String
    public let modelVersion: String
    public init(kind: Kind, displayName: String, modelVersion: String) {
        self.kind = kind
        self.displayName = displayName
        self.modelVersion = modelVersion
    }
}

public struct AIImageInput: Sendable {
    public let itemID: MediaItemID
    public let thumbnailData: Data
    public let originalURL: URL?
    public init(itemID: MediaItemID, thumbnailData: Data, originalURL: URL?) {
        self.itemID = itemID
        self.thumbnailData = thumbnailData
        self.originalURL = originalURL
    }
}

public struct AIVideoInput: Sendable {
    public let itemID: MediaItemID
    public let frames: [Data]
    public init(itemID: MediaItemID, frames: [Data]) {
        self.itemID = itemID
        self.frames = frames
    }
}

public struct AIDescription: Sendable {
    public let caption: String
    public let scene: String?
    public let confidence: Double
    public init(caption: String, scene: String?, confidence: Double) {
        self.caption = caption
        self.scene = scene
        self.confidence = confidence
    }
}

public struct AITagSet: Sendable {
    public let tags: [String]
    public let objects: [String]
    public init(tags: [String], objects: [String]) {
        self.tags = tags
        self.objects = objects
    }
}

public struct AIEmbedding: Sendable {
    public let dim: Int
    public let vector: [Float]
    public init(dim: Int, vector: [Float]) {
        self.dim = dim
        self.vector = vector
    }
}

public struct AIRerankInput: Sendable {
    public let query: String
    public let candidateIDs: [MediaItemID]
    public init(query: String, candidateIDs: [MediaItemID]) {
        self.query = query
        self.candidateIDs = candidateIDs
    }
}

public struct AIRerankResult: Sendable {
    public let orderedIDs: [MediaItemID]
    public init(orderedIDs: [MediaItemID]) {
        self.orderedIDs = orderedIDs
    }
}

public struct AIOCRInput: Sendable {
    public let itemID: MediaItemID
    public let existingText: String?
    public init(itemID: MediaItemID, existingText: String?) {
        self.itemID = itemID
        self.existingText = existingText
    }
}

public struct AIOCRResult: Sendable {
    public let mergedText: String
    public init(mergedText: String) {
        self.mergedText = mergedText
    }
}
