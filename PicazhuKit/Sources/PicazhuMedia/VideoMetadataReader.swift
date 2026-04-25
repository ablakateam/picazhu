import Foundation
import AVFoundation
import PicazhuCore

public struct VideoMetadata: Sendable {
    public var width: Int?
    public var height: Int?
    public var duration: Double?
    public var codec: String?
}

public enum VideoMetadataReader {
    public static func read(url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        var m = VideoMetadata()

        do {
            let duration = try await asset.load(.duration)
            m.duration = CMTimeGetSeconds(duration)

            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let applied = size.applying(transform)
                m.width = Int(abs(applied.width))
                m.height = Int(abs(applied.height))

                let formatDescriptions = try await track.load(.formatDescriptions)
                if let fd = formatDescriptions.first {
                    let sub = CMFormatDescriptionGetMediaSubType(fd)
                    m.codec = fourCCToString(sub)
                }
            }
        } catch {
            throw PicazhuError.metadataReadFailed(url, "\(error)")
        }
        return m
    }

    private static func fourCCToString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        let s = String(bytes: bytes, encoding: .ascii) ?? ""
        return s.trimmingCharacters(in: .whitespaces)
    }
}
