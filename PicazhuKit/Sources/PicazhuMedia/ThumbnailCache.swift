import Foundation
import PicazhuCore

public actor ThumbnailCache {
    public let root: URL
    public var maxBytes: Int64

    public init(root: URL, maxBytes: Int64 = 2 * 1024 * 1024 * 1024) throws {
        self.root = root
        self.maxBytes = maxBytes
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public static func `default`() throws -> ThumbnailCache {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = caches.appendingPathComponent("PICAZHU/thumbs", isDirectory: true)
        return try ThumbnailCache(root: dir)
    }

    public func fileURL(key: String) -> URL {
        let shard = String(key.prefix(2))
        let dir = root.appendingPathComponent(shard, isDirectory: true)
        return dir.appendingPathComponent("\(key).jpg", isDirectory: false)
    }

    public func read(key: String) -> Data? {
        let url = fileURL(key: key)
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    public func write(key: String, data: Data) {
        let url = fileURL(key: key)
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            PicazhuLog.media.error("Thumbnail cache write failed: \(error.localizedDescription)")
        }
    }

    public func purge() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func sizeBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
