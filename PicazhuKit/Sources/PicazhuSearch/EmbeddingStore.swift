import Foundation
import PicazhuCore

public struct EmbeddingStore: Sendable {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public static func `default`() throws -> EmbeddingStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base
            .appendingPathComponent("PICAZHU", isDirectory: true)
            .appendingPathComponent("embeddings", isDirectory: true)
        return try EmbeddingStore(root: dir)
    }

    public func write(itemID: MediaItemID, vector: [Float]) throws -> String {
        let shard = String(format: "%02x", abs(itemID.rawValue.hashValue) & 0xff)
        let dir = root.appendingPathComponent(shard, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(itemID.rawValue).vec")
        let data = vector.withUnsafeBufferPointer { buf in
            Data(buffer: buf)
        }
        try data.write(to: file, options: .atomic)
        return file.path
    }

    public func read(path: String) -> [Float]? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return nil }
        return data.withUnsafeBytes { ptr in
            Array(UnsafeBufferPointer(start: ptr.bindMemory(to: Float.self).baseAddress, count: count))
        }
    }

    public func delete(path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    public func purge() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}
