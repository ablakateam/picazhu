import Foundation

public enum OllamaMode: String, Codable, Sendable, CaseIterable {
    case local = "Local Ollama"
    case cloud = "Ollama Cloud"
}

public struct OllamaProviderConfig: Codable, Sendable, Equatable {
    public var mode: OllamaMode
    public var host: String
    public var apiKey: String
    public var visionModel: String
    public var embeddingModel: String
    public var temperature: Double
    public var maxFramesPerVideo: Int
    public var requestTimeoutSeconds: Double

    public static let `default` = OllamaProviderConfig(
        mode: .local,
        host: "http://localhost:11434",
        apiKey: "",
        visionModel: "qwen3-vl:8b",
        embeddingModel: "nomic-embed-text",
        temperature: 0.2,
        maxFramesPerVideo: 5,
        requestTimeoutSeconds: 120
    )

    public static let cloud = OllamaProviderConfig(
        mode: .cloud,
        host: "https://ollama.com",
        apiKey: "",
        visionModel: "qwen3-vl:235b-instruct",
        embeddingModel: "",
        temperature: 0.2,
        maxFramesPerVideo: 5,
        requestTimeoutSeconds: 120
    )

    public init(
        mode: OllamaMode = .local,
        host: String,
        apiKey: String = "",
        visionModel: String,
        embeddingModel: String,
        temperature: Double,
        maxFramesPerVideo: Int,
        requestTimeoutSeconds: Double
    ) {
        self.mode = mode
        self.host = host
        self.apiKey = apiKey
        self.visionModel = visionModel
        self.embeddingModel = embeddingModel
        self.temperature = temperature
        self.maxFramesPerVideo = maxFramesPerVideo
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }

    public var baseURL: URL? {
        URL(string: host)
    }

    public var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
