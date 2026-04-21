import Foundation
import PicazhuCore

public enum FolderScope: Sendable, Codable, Equatable {
    case all
    case folder(FolderID)
    case pinned
}

public struct SearchQuery: Sendable, Codable, Equatable {
    public var text: String
    public var kinds: Set<MediaKind>
    public var extensions: Set<String>
    public var dateRange: ClosedRange<Date>?
    public var sizeRange: ClosedRange<Int64>?
    public var folderScope: FolderScope

    public init(
        text: String = "",
        kinds: Set<MediaKind> = [],
        extensions: Set<String> = [],
        dateRange: ClosedRange<Date>? = nil,
        sizeRange: ClosedRange<Int64>? = nil,
        folderScope: FolderScope = .all
    ) {
        self.text = text
        self.kinds = kinds
        self.extensions = extensions
        self.dateRange = dateRange
        self.sizeRange = sizeRange
        self.folderScope = folderScope
    }

    public var isEmpty: Bool {
        text.isEmpty && kinds.isEmpty && extensions.isEmpty && dateRange == nil && sizeRange == nil && folderScope == .all
    }
}
