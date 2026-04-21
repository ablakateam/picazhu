import Foundation
import PicazhuCore

public struct SecurityScope: ~Copyable {
    public let url: URL
    private let didStart: Bool

    public init(url: URL) throws {
        self.url = url
        self.didStart = url.startAccessingSecurityScopedResource()
        if !self.didStart {
            PicazhuLog.indexing.warning("startAccessingSecurityScopedResource failed for \(url.path)")
        }
    }

    deinit {
        if didStart {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

public func withSecurityScope<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
    let scope = try SecurityScope(url: url)
    _ = scope
    return try body(url)
}

public func withSecurityScope<T>(_ url: URL, _ body: (URL) async throws -> T) async throws -> T {
    let scope = try SecurityScope(url: url)
    _ = scope
    return try await body(url)
}
