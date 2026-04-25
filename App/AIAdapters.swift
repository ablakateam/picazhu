import Foundation
import AVFoundation
import PicazhuCore
import PicazhuData
import PicazhuAI
import PicazhuMedia
import PicazhuIndexing
import PicazhuSearch
import PicazhuVision

struct ThumbnailSourceAdapter: AIThumbnailSource {
    let cache: ThumbnailCache
    let thumbnails: ThumbnailService
    let rootRepo: WatchedRootRepository
    let bookmarks: BookmarkStore
    let mediaRepo: MediaItemRepository

    func thumbnailBytes(
        rootID: WatchedRootID,
        relativePath: String,
        modifiedAt: Date,
        size: Int64
    ) async -> Data? {
        let key = ThumbnailService.cacheKey(
            rootID: rootID,
            relativePath: relativePath,
            modifiedAt: modifiedAt,
            size: size
        )
        if let cached = await cache.read(key: key) {
            return cached
        }
        guard let root = try? rootRepo.find(id: rootID) else { return nil }
        do {
            let resolved = try await bookmarks.resolve(root)
            let scope = try SecurityScope(url: resolved.url)
            _ = scope
            let fileURL = resolved.url.appendingPathComponent(relativePath)
            let result = try await thumbnails.thumbnail(
                for: fileURL,
                rootID: rootID,
                relativePath: relativePath,
                modifiedAt: modifiedAt,
                size: size
            )
            return result.imageData
        } catch {
            PicazhuLog.ai.error("thumbnailBytes failed for \(relativePath): \(error.localizedDescription)")
            return nil
        }
    }

    func resolveFileURL(for itemID: MediaItemID) async -> URL? {
        guard let item = try? mediaRepo.find(id: itemID),
              let root = try? rootRepo.find(id: item.rootID) else {
            return nil
        }
        do {
            let resolved = try await bookmarks.resolve(root)
            return resolved.url.appendingPathComponent(item.relativePath)
        } catch {
            return nil
        }
    }

    func videoKeyframes(for itemID: MediaItemID, count: Int) async -> [Data] {
        guard let url = await resolveFileURL(for: itemID) else { return [] }
        guard let item = try? mediaRepo.find(id: itemID),
              let root = try? rootRepo.find(id: item.rootID) else { return [] }
        do {
            let resolved = try await bookmarks.resolve(root)
            let scope = try SecurityScope(url: resolved.url)
            _ = scope
            let frames = try await VideoKeyframeExtractor.extractFrames(url: url, count: count)
            return frames.map(\.imageData)
        } catch {
            PicazhuLog.ai.error("Keyframe extraction failed: \(error.localizedDescription)")
            return []
        }
    }
}

struct OCRAdapter: AIOCRPerformer {
    let service: OCRService

    func recognize(imageData: Data) async throws -> String {
        let result = try await service.recognizeText(imageData: imageData)
        return result.joinedText
    }

    func recognize(fileURL: URL) async throws -> String {
        let result = try await service.recognizeText(at: fileURL)
        return result.joinedText
    }
}

struct EmbeddingStoreAdapter: EmbeddingStoreWriter {
    let store: EmbeddingStore

    func write(itemID: MediaItemID, vector: [Float]) throws -> String {
        try store.write(itemID: itemID, vector: vector)
    }
}
