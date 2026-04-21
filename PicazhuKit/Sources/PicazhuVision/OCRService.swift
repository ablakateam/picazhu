import Foundation
import Vision
import CoreGraphics
import ImageIO
import PicazhuCore

public struct OCRLine: Sendable, Hashable {
    public let text: String
    public let confidence: Double
    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

public struct OCRResult: Sendable {
    public let lines: [OCRLine]
    public var joinedText: String {
        lines.map(\.text).joined(separator: "\n")
    }
    public init(lines: [OCRLine]) {
        self.lines = lines
    }
}

public enum OCRError: Error, Sendable {
    case unreadable(URL)
    case visionFailed(String)
}

public struct OCRService: Sendable {
    public var recognitionLanguages: [String]
    public var usesLanguageCorrection: Bool

    public init(
        recognitionLanguages: [String] = ["en-US"],
        usesLanguageCorrection: Bool = true
    ) {
        self.recognitionLanguages = recognitionLanguages
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    public func recognizeText(at url: URL) async throws -> OCRResult {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRError.unreadable(url)
        }
        return try await recognizeText(cgImage: cgImage)
    }

    public func recognizeText(imageData: Data) async throws -> OCRResult {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRError.visionFailed("cannot decode image data")
        }
        return try await recognizeText(cgImage: cgImage)
    }

    public func recognizeText(cgImage: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<OCRResult, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: OCRResult(lines: []))
                    return
                }
                var lines: [OCRLine] = []
                for obs in observations {
                    guard let top = obs.topCandidates(1).first else { continue }
                    lines.append(OCRLine(text: top.string, confidence: Double(top.confidence)))
                }
                cont.resume(returning: OCRResult(lines: lines))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = usesLanguageCorrection
            request.recognitionLanguages = recognitionLanguages
            if #available(macOS 13, *) {
                request.revision = VNRecognizeTextRequestRevision3
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: OCRError.visionFailed(error.localizedDescription))
            }
        }
    }
}
