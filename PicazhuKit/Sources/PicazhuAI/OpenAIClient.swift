import Foundation
import PicazhuCore

public struct OpenAIProviderConfig: Codable, Sendable, Equatable {
    public var apiKey: String
    public var baseURL: String
    public var visionModel: String
    public var embeddingModel: String
    public var temperature: Double
    public var maxFramesPerVideo: Int
    public var requestTimeoutSeconds: Double

    public static let `default` = OpenAIProviderConfig(
        apiKey: "",
        baseURL: "https://api.openai.com",
        visionModel: "gpt-4o",
        embeddingModel: "text-embedding-3-small",
        temperature: 0.2,
        maxFramesPerVideo: 5,
        requestTimeoutSeconds: 120
    )

    public init(
        apiKey: String,
        baseURL: String = "https://api.openai.com",
        visionModel: String = "gpt-4o",
        embeddingModel: String = "text-embedding-3-small",
        temperature: Double = 0.2,
        maxFramesPerVideo: Int = 5,
        requestTimeoutSeconds: Double = 120
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.visionModel = visionModel
        self.embeddingModel = embeddingModel
        self.temperature = temperature
        self.maxFramesPerVideo = maxFramesPerVideo
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }

    public var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct OpenAIClient: Sendable {
    public let config: OpenAIProviderConfig
    private let session: URLSession

    public init(config: OpenAIProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func chatWithVision(
        model: String,
        prompt: String,
        imageBase64: String,
        jsonSchema: [String: Any]? = nil
    ) async throws -> String {
        let url = try endpoint("/v1/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = config.requestTimeoutSeconds

        let imageContent: [String: Any] = [
            "type": "image_url",
            "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]
        ]
        let textContent: [String: Any] = [
            "type": "text",
            "text": prompt
        ]
        let message: [String: Any] = [
            "role": "user",
            "content": [textContent, imageContent]
        ]

        var body: [String: Any] = [
            "model": model,
            "messages": [message],
            "temperature": config.temperature,
            "max_tokens": 1024
        ]

        if let schema = jsonSchema {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": "image_analysis",
                    "strict": true,
                    "schema": schema
                ]
            ]
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)

        struct ChatResponse: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let message: Message
            }
            struct Message: Decodable {
                let content: String?
            }
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIError.emptyResponse
        }
        return content
    }

    public func embed(model: String, input: String) async throws -> [Float] {
        let url = try endpoint("/v1/embeddings")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "input": input
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)

        struct EmbedResponse: Decodable {
            let data: [EmbedData]
            struct EmbedData: Decodable {
                let embedding: [Float]
            }
        }
        let decoded = try JSONDecoder().decode(EmbedResponse.self, from: data)
        guard let embedding = decoded.data.first?.embedding else {
            throw OpenAIError.emptyResponse
        }
        return embedding
    }

    public func listModels() async throws -> [String] {
        let url = try endpoint("/v1/models")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)

        struct ModelsResponse: Decodable {
            let data: [Model]
            struct Model: Decodable {
                let id: String
            }
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let base = URL(string: config.baseURL),
              let url = URL(string: path, relativeTo: base) else {
            throw OpenAIError.invalidURL(config.baseURL)
        }
        return url.absoluteURL
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.http(status: http.statusCode, body: body)
        }
    }
}

public enum OpenAIError: Error, Sendable {
    case invalidURL(String)
    case http(status: Int, body: String)
    case emptyResponse
    case decode(String)
}

extension OpenAIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .http(let status, let body): return "HTTP \(status): \(body.prefix(200))"
        case .emptyResponse: return "Empty response from OpenAI"
        case .decode(let msg): return "Decode error: \(msg)"
        }
    }
}
