import Foundation

public enum PicazhuError: Error, Sendable {
    case databaseUnavailable
    case migrationFailed(String)
    case bookmarkStale
    case bookmarkResolveFailed(underlying: String)
    case securityScopeDenied(URL)
    case enumerationFailed(URL, String)
    case thumbnailGenerationFailed(URL, String)
    case metadataReadFailed(URL, String)
    case invalidPath(String)
}

extension PicazhuError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "Catalog database is unavailable."
        case .migrationFailed(let detail):
            return "Database migration failed: \(detail)"
        case .bookmarkStale:
            return "Folder bookmark is stale. Reconnect the folder."
        case .bookmarkResolveFailed(let u):
            return "Could not resolve folder bookmark: \(u)"
        case .securityScopeDenied(let url):
            return "Access to \(url.path) was denied."
        case .enumerationFailed(let url, let detail):
            return "Failed to enumerate \(url.path): \(detail)"
        case .thumbnailGenerationFailed(let url, let detail):
            return "Thumbnail failed for \(url.lastPathComponent): \(detail)"
        case .metadataReadFailed(let url, let detail):
            return "Metadata read failed for \(url.lastPathComponent): \(detail)"
        case .invalidPath(let p):
            return "Invalid path: \(p)"
        }
    }
}
