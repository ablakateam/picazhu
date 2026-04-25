import Foundation

public struct WatchedRoot: Sendable, Hashable, Identifiable {
    public let id: WatchedRootID
    public var displayName: String
    public var bookmark: Data
    public var lastScanAt: Date?
    public var accessState: RootAccessState
    public var createdAt: Date

    public init(
        id: WatchedRootID,
        displayName: String,
        bookmark: Data,
        lastScanAt: Date?,
        accessState: RootAccessState,
        createdAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmark = bookmark
        self.lastScanAt = lastScanAt
        self.accessState = accessState
        self.createdAt = createdAt
    }
}

public struct Folder: Sendable, Hashable, Identifiable {
    public let id: FolderID
    public let rootID: WatchedRootID
    public let parentID: FolderID?
    public let relativePath: String
    public let name: String
    public let depth: Int
    public let itemCount: Int
    public let childCount: Int

    public init(
        id: FolderID,
        rootID: WatchedRootID,
        parentID: FolderID?,
        relativePath: String,
        name: String,
        depth: Int,
        itemCount: Int,
        childCount: Int
    ) {
        self.id = id
        self.rootID = rootID
        self.parentID = parentID
        self.relativePath = relativePath
        self.name = name
        self.depth = depth
        self.itemCount = itemCount
        self.childCount = childCount
    }
}

public struct MediaItem: Sendable, Hashable, Identifiable {
    public let id: MediaItemID
    public let folderID: FolderID
    public let rootID: WatchedRootID
    public let filename: String
    public let relativePath: String
    public let fileExtension: String
    public let kind: MediaKind
    public let size: Int64
    public let createdAt: Date?
    public let modifiedAt: Date
    public let width: Int?
    public let height: Int?
    public let duration: Double?
    public let orientation: Int?
    public let contentHash: String?
    public let thumbState: LifecycleState
    public let metaState: LifecycleState
    public let aiState: AIState
    public let indexedAt: Date

    public init(
        id: MediaItemID,
        folderID: FolderID,
        rootID: WatchedRootID,
        filename: String,
        relativePath: String,
        fileExtension: String,
        kind: MediaKind,
        size: Int64,
        createdAt: Date?,
        modifiedAt: Date,
        width: Int?,
        height: Int?,
        duration: Double?,
        orientation: Int?,
        contentHash: String?,
        thumbState: LifecycleState,
        metaState: LifecycleState,
        aiState: AIState,
        indexedAt: Date
    ) {
        self.id = id
        self.folderID = folderID
        self.rootID = rootID
        self.filename = filename
        self.relativePath = relativePath
        self.fileExtension = fileExtension
        self.kind = kind
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.width = width
        self.height = height
        self.duration = duration
        self.orientation = orientation
        self.contentHash = contentHash
        self.thumbState = thumbState
        self.metaState = metaState
        self.aiState = aiState
        self.indexedAt = indexedAt
    }
}

public struct MediaItemDraft: Sendable, Hashable {
    public let rootID: WatchedRootID
    public let folderRelativePath: String
    public let filename: String
    public let relativePath: String
    public let fileExtension: String
    public let kind: MediaKind
    public let size: Int64
    public let createdAt: Date?
    public let modifiedAt: Date

    public init(
        rootID: WatchedRootID,
        folderRelativePath: String,
        filename: String,
        relativePath: String,
        fileExtension: String,
        kind: MediaKind,
        size: Int64,
        createdAt: Date?,
        modifiedAt: Date
    ) {
        self.rootID = rootID
        self.folderRelativePath = folderRelativePath
        self.filename = filename
        self.relativePath = relativePath
        self.fileExtension = fileExtension
        self.kind = kind
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
