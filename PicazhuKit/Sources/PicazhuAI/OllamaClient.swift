import Foundation
import PicazhuCore

public enum OllamaError: Error, Sendable {
    case invalidHost(String)
    case http(status: Int, body: String)
    case decode(String)
    case transport(String)
    case modelNotFound(String)
    case schemaViolation(String)
}

public struct OllamaModelInfo: Sendable, Codable, Hashable {
    public let name: String
    public let size: Int64?
    public let modified: String?
}

public struct OllamaLoadedModel: Sendable, Codable, Hashable {
    public let name: String
    public let model: String
    public let size: Int64?
    public let sizeVRAM: Int64?
}

public struct OllamaGenerateResponse: Sendable, Codable {
    public let model: String
    public let response: String
    public let done: Bool
}

public struct OllamaEmbeddingResponse: Sendable, Codable {
    public let embedding: [Float]
}

public struct OllamaClient: Sendable {
    public let config: OllamaProviderConfig
    private let session: URLSession

    public init(config: OllamaProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    private func applyAuth(_ req: inout URLRequest) {
        if config.hasAPIKey {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    public func listModels() async throws -> [OllamaModelInfo] {
        let url = try endpoint("/api/tags")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        applyAuth(&req)
        let (data, response) = try await session.data(for: req)
        try Self.validate(response: response, data: data)

        struct TagsResponse: Decodable {
            let models: [Model]
            struct Model: Decodable {
                let name: String
                let size: Int64?
                let modified_at: String?
            }
        }
        do {
            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            return decoded.models.map {
                OllamaModelInfo(name: $0.name, size: $0.size, modified: $0.modified_at)
            }
        } catch {
            throw OllamaError.decode("\(error)")
        }
    }

    public func generate(
        model: String,
        prompt: String,
        images: [Data] = [],
        format: [String: Any]? = nil,
        options: [String: Any]? = nil
    ) async throws -> String {
        let url = try endpoint("/api/generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = config.requestTimeoutSeconds

        applyAuth(&req)

        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        if !images.isEmpty {
            body["images"] = images.map { $0.base64EncodedString() }
        }
        if let format {
            body["format"] = format
        }
        if let options {
            body["options"] = options
        } else {
            body["options"] = ["temperature": config.temperature]
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw OllamaError.transport("\(error.localizedDescription)")
        }
        try Self.validate(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            return decoded.response
        } catch {
            throw OllamaError.decode("generate response: \(error)")
        }
    }

    public func chat(
        model: String,
        prompt: String,
        images: [Data] = [],
        format: [String: Any]? = nil,
        options: [String: Any]? = nil
    ) async throws -> String {
        let url = try endpoint("/api/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = config.requestTimeoutSeconds
        applyAuth(&req)

        var userContent: [String: Any] = [
            "role": "user",
            "content": prompt
        ]
        if !images.isEmpty {
            userContent["images"] = images.map { $0.base64EncodedString() }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": [userContent],
            "stream": false
        ]
        if let format {
            body["format"] = format
        }
        if let options {
            body["options"] = options
        } else {
            body["options"] = ["temperature": config.temperature]
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw OllamaError.transport("\(error.localizedDescription)")
        }
        try Self.validate(response: response, data: data)

        struct ChatResponse: Decodable {
            let message: Message
            struct Message: Decodable {
                let content: String
            }
        }
        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            return decoded.message.content
        } catch {
            throw OllamaError.decode("chat response: \(error)")
        }
    }

    public func embed(model: String, input: String) async throws -> [Float] {
        let url = try endpoint("/api/embeddings")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = config.requestTimeoutSeconds
        applyAuth(&req)

        let body: [String: Any] = [
            "model": model,
            "prompt": input
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw OllamaError.transport("\(error.localizedDescription)")
        }
        try Self.validate(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(OllamaEmbeddingResponse.self, from: data)
            return decoded.embedding
        } catch {
            throw OllamaError.decode("embeddings response: \(error)")
        }
    }

    public func ping() async throws {
        _ = try await listModels()
    }

    public func warmup(model: String) async throws {
        let url = try endpoint("/api/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        applyAuth(&req)
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "hi"]],
            "stream": false,
            "options": ["num_predict": 1]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        try Self.validate(response: response, data: data)
    }

    public func unload(model: String) async {
        guard let url = try? endpoint("/api/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 5
        applyAuth(&req)
        let body: [String: Any] = [
            "model": model,
            "messages": [],
            "keep_alive": 0
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: req)
    }

    public func loadedModels() async throws -> [OllamaLoadedModel] {
        let url = try endpoint("/api/ps")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        applyAuth(&req)
        let (data, response) = try await session.data(for: req)
        try Self.validate(response: response, data: data)

        struct PSResponse: Decodable {
            let models: [Model]
            struct Model: Decodable {
                let name: String
                let model: String
                let size: Int64?
                let size_vram: Int64?
            }
        }
        do {
            let decoded = try JSONDecoder().decode(PSResponse.self, from: data)
            return decoded.models.map {
                OllamaLoadedModel(name: $0.name, model: $0.model, size: $0.size, sizeVRAM: $0.size_vram)
            }
        } catch {
            throw OllamaError.decode("\(error)")
        }
    }

    private func endpoint(_ path: String) throws -> URL {
        guard var base = config.baseURL else {
            throw OllamaError.invalidHost(config.host)
        }
        if let appended = URL(string: path, relativeTo: base) {
            base = appended.absoluteURL
        }
        return base
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 404 {
                throw OllamaError.modelNotFound(body)
            }
            throw OllamaError.http(status: http.statusCode, body: body)
        }
    }
}
