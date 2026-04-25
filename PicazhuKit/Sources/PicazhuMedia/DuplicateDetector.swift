import Foundation
import AppKit
import CoreGraphics
import PicazhuCore

public struct DuplicateGroup: Sendable, Identifiable {
    public let id: String
    public let itemIDs: [MediaItemID]
    public let similarity: Double

    public init(itemIDs: [MediaItemID], similarity: Double) {
        self.id = itemIDs.map { "\($0.rawValue)" }.joined(separator: "-")
        self.itemIDs = itemIDs
        self.similarity = similarity
    }
}

public enum DuplicateDetector {

    /// Compute a perceptual hash for an image (64-bit)
    public static func pHash(imageData: Data) -> UInt64? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return pHash(cgImage: cgImage)
    }

    public static func pHash(cgImage: CGImage) -> UInt64? {
        // Resize to 32x32 grayscale
        let size = 32
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size)

        // Compute DCT on 8x8 block (top-left low frequencies)
        var dctValues: [Double] = Array(repeating: 0, count: 64)
        for u in 0..<8 {
            for v in 0..<8 {
                var sum: Double = 0
                for x in 0..<size {
                    for y in 0..<size {
                        let pixel = Double(pixels[y * size + x])
                        sum += pixel
                            * cos(Double.pi * Double(2 * x + 1) * Double(u) / Double(2 * size))
                            * cos(Double.pi * Double(2 * y + 1) * Double(v) / Double(2 * size))
                    }
                }
                dctValues[u * 8 + v] = sum
            }
        }

        // Skip DC component (index 0), compute median of remaining
        let acValues = Array(dctValues[1...])
        let sorted = acValues.sorted()
        let median = sorted[sorted.count / 2]

        // Build hash: 1 if above median, 0 if below
        var hash: UInt64 = 0
        for (i, val) in acValues.enumerated() {
            if val > median {
                hash |= (1 << i)
            }
        }
        return hash
    }

    /// Hamming distance between two hashes (number of differing bits)
    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount
    }

    /// Similarity score (0.0 = totally different, 1.0 = identical)
    public static func similarity(_ a: UInt64, _ b: UInt64) -> Double {
        let dist = hammingDistance(a, b)
        return 1.0 - Double(dist) / 63.0
    }

    /// Find duplicate groups from a list of (itemID, hash) pairs
    /// threshold: minimum similarity (0.9 = very similar, 0.95 = near-identical)
    public static func findDuplicates(
        items: [(id: MediaItemID, hash: UInt64)],
        threshold: Double = 0.9
    ) -> [DuplicateGroup] {
        var groups: [[Int]] = []
        var assigned: Set<Int> = []

        for i in 0..<items.count {
            guard !assigned.contains(i) else { continue }
            var group = [i]
            for j in (i + 1)..<items.count {
                guard !assigned.contains(j) else { continue }
                let sim = similarity(items[i].hash, items[j].hash)
                if sim >= threshold {
                    group.append(j)
                    assigned.insert(j)
                }
            }
            if group.count > 1 {
                assigned.insert(i)
                groups.append(group)
            }
        }

        return groups.map { indices in
            let ids = indices.map { items[$0].id }
            let minSim = indices.combinations(ofCount: 2).map { pair in
                similarity(items[pair[0]].hash, items[pair[1]].hash)
            }.min() ?? 1.0
            return DuplicateGroup(itemIDs: ids, similarity: minSim)
        }
    }
}

private extension Array {
    func combinations(ofCount k: Int) -> [[Int]] {
        guard k == 2 else { return [] }
        var result: [[Int]] = []
        for i in 0..<count {
            for j in (i+1)..<count {
                result.append([i, j])
            }
        }
        return result
    }
}
