import Foundation
import UniformTypeIdentifiers

public enum MediaKind: String, Sendable, Codable, CaseIterable {
    case image
    case video

    public static func from(utType: UTType) -> MediaKind? {
        if utType.conforms(to: .image) { return .image }
        if utType.conforms(to: .movie) || utType.conforms(to: .video) { return .video }
        return nil
    }

    public static func from(fileExtension ext: String) -> MediaKind? {
        guard let ut = UTType(filenameExtension: ext.lowercased()) else { return nil }
        return from(utType: ut)
    }
}

public enum LifecycleState: String, Sendable, Codable {
    case pending
    case ready
    case failed
}

public enum AIState: String, Sendable, Codable {
    case none
    case pending
    case ready
    case failed
}

public enum RootAccessState: String, Sendable, Codable {
    case ok
    case stale
    case denied
}
