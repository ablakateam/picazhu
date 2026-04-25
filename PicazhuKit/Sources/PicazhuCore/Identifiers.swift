import Foundation

public struct WatchedRootID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }
}

public struct FolderID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }
}

public struct MediaItemID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }
}

public struct SavedSearchID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }
}
