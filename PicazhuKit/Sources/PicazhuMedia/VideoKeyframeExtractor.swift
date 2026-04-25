import Foundation
import AVFoundation
import AppKit
import PicazhuCore

public struct KeyframeResult: Sendable {
    public let frameIndex: Int
    public let timestamp: Double
    public let imageData: Data
}

public enum VideoKeyframeExtractor {
    public static func extractFrames(
        url: URL,
        count: Int = 5
    ) async throws -> [KeyframeResult] {
        let asset = AVURLAsset(url: url)
        let duration: Double
        do {
            let cmDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmDuration)
        } catch {
            throw PicazhuError.metadataReadFailed(url, "duration: \(error)")
        }

        guard duration > 0 else {
            throw PicazhuError.metadataReadFailed(url, "zero duration")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let positions: [Double]
        if count == 1 || duration < 2 {
            positions = [0.5]
        } else {
            positions = (0..<count).map { i in
                let fraction = (Double(i) + 0.5) / Double(count)
                return fraction * duration
            }
        }

        var results: [KeyframeResult] = []
        for (index, timestamp) in positions.enumerated() {
            let time = CMTime(seconds: timestamp, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let nsImage = NSImage(cgImage: cgImage, size: .zero)
                guard let tiff = nsImage.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                    continue
                }
                results.append(KeyframeResult(
                    frameIndex: index,
                    timestamp: timestamp,
                    imageData: jpeg
                ))
            } catch {
                PicazhuLog.media.warning("Keyframe \(index) at \(String(format: "%.1f", timestamp))s failed: \(error.localizedDescription)")
                continue
            }
        }
        return results
    }
}
