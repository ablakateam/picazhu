import Foundation
import AppKit
import QuickLookThumbnailing
import AVFoundation
import CryptoKit
import PicazhuCore

public struct ThumbnailResult: Sendable {
    public let imageData: Data
    public let pixelSize: Int
    public let cacheKey: String
}

public actor ThumbnailService {
    public struct Config: Sendable {
        public var pixelSize: Int = 512
        public var scale: CGFloat = 2.0
        public init() {}
    }

    public let config: Config
    private let cache: ThumbnailCache

    public init(cache: ThumbnailCache, config: Config = Config()) {
        self.cache = cache
        self.config = config
    }

    public func thumbnail(
        for fileURL: URL,
        rootID: WatchedRootID,
        relativePath: String,
        modifiedAt: Date,
        size: Int64
    ) async throws -> ThumbnailResult {
        let key = Self.cacheKey(
            rootID: rootID,
            relativePath: relativePath,
            modifiedAt: modifiedAt,
            size: size
        )

        if let cached = await cache.read(key: key) {
            return ThumbnailResult(imageData: cached, pixelSize: config.pixelSize, cacheKey: key)
        }

        let data = try await generate(for: fileURL)
        await cache.write(key: key, data: data)
        return ThumbnailResult(imageData: data, pixelSize: config.pixelSize, cacheKey: key)
    }

    private func generate(for url: URL) async throws -> Data {
        let pixel = CGFloat(config.pixelSize)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pixel, height: pixel),
            scale: config.scale,
            representationTypes: .thumbnail
        )

        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            guard let data = Self.heicData(from: rep.nsImage) else {
                throw PicazhuError.thumbnailGenerationFailed(url, "HEIC encoding failed")
            }
            return data
        } catch {
            if let fallback = try? await Self.videoPosterFrame(url: url, pixel: pixel) {
                return fallback
            }
            throw PicazhuError.thumbnailGenerationFailed(url, "\(error)")
        }
    }

    private static func heicData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.85]
        )
    }

    private static func videoPosterFrame(url: URL, pixel: CGFloat) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixel, height: pixel)

        let cgImage = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGImage, Error>) in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0.1, preferredTimescale: 600))]) { _, image, _, _, error in
                if let image {
                    cont.resume(returning: image)
                } else {
                    cont.resume(throwing: error ?? PicazhuError.thumbnailGenerationFailed(url, "no frame"))
                }
            }
        }
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        guard let data = heicData(from: nsImage) else {
            throw PicazhuError.thumbnailGenerationFailed(url, "HEIC encoding failed")
        }
        return data
    }

    public static func cacheKey(
        rootID: WatchedRootID,
        relativePath: String,
        modifiedAt: Date,
        size: Int64
    ) -> String {
        let raw = "\(rootID.rawValue)|\(relativePath)|\(Int64(modifiedAt.timeIntervalSince1970))|\(size)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
