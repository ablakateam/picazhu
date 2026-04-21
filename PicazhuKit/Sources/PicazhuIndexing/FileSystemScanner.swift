import Foundation
import UniformTypeIdentifiers
import PicazhuCore

public struct ScanResult: Sendable {
    public var folderRelativePaths: Set<String>
    public var drafts: [MediaItemDraft]
    public var errors: [String]
}

public struct ScanBatch: Sendable {
    public let folderRelativePaths: [String]
    public let drafts: [MediaItemDraft]
}

public enum FileSystemScanner {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .creationDateKey,
        .typeIdentifierKey,
        .nameKey
    ]

    public static func scan(
        rootURL: URL,
        rootID: WatchedRootID,
        progress: @Sendable (Int) -> Void = { _ in }
    ) throws -> ScanResult {
        var result = ScanResult(folderRelativePaths: [""], drafts: [], errors: [])
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                PicazhuLog.indexing.error("enumerator error at \(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            throw PicazhuError.enumerationFailed(rootURL, "no enumerator")
        }
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        var scanned = 0
        for case let fileURL as URL in enumerator {
            if let entry = try? classify(fileURL: fileURL, rootComponents: rootComponents, rootID: rootID) {
                switch entry {
                case .folder(let relPath):
                    result.folderRelativePaths.insert(relPath)
                case .media(let draft):
                    result.drafts.append(draft)
                    scanned += 1
                    if scanned % 200 == 0 { progress(scanned) }
                }
            }
        }
        progress(scanned)
        return result
    }

    public static func scanStreaming(
        rootURL: URL,
        rootID: WatchedRootID,
        batchSize: Int = 500,
        onBatch: (ScanBatch) async throws -> Void,
        onProgress: @Sendable (Int) -> Void = { _ in }
    ) async throws -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                PicazhuLog.indexing.error("enumerator error at \(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            throw PicazhuError.enumerationFailed(rootURL, "no enumerator")
        }

        let rootComponents = rootURL.standardizedFileURL.pathComponents
        var folderBatch: [String] = [""]
        var draftBatch: [MediaItemDraft] = []
        var total = 0

        while let next = enumerator.nextObject() {
            try Task.checkCancellation()
            guard let fileURL = next as? URL else { continue }
            guard let entry = try? classify(
                fileURL: fileURL,
                rootComponents: rootComponents,
                rootID: rootID
            ) else { continue }

            switch entry {
            case .folder(let relPath):
                folderBatch.append(relPath)
            case .media(let draft):
                draftBatch.append(draft)
            }

            if draftBatch.count >= batchSize {
                try await onBatch(ScanBatch(folderRelativePaths: folderBatch, drafts: draftBatch))
                total += draftBatch.count
                onProgress(total)
                folderBatch.removeAll(keepingCapacity: true)
                draftBatch.removeAll(keepingCapacity: true)
            }
        }

        if !folderBatch.isEmpty || !draftBatch.isEmpty {
            try await onBatch(ScanBatch(folderRelativePaths: folderBatch, drafts: draftBatch))
            total += draftBatch.count
            onProgress(total)
        }
        return total
    }

    private enum ScannedEntry {
        case folder(String)
        case media(MediaItemDraft)
    }

    private static func classify(
        fileURL: URL,
        rootComponents: [String],
        rootID: WatchedRootID
    ) throws -> ScannedEntry? {
        let values = try fileURL.resourceValues(forKeys: keys)
        let standardized = fileURL.standardizedFileURL
        let relativeComponents = Array(standardized.pathComponents.dropFirst(rootComponents.count))
        let relativePath = relativeComponents.joined(separator: "/")

        if values.isDirectory == true {
            return .folder(relativePath)
        }

        guard let typeID = values.typeIdentifier,
              let ut = UTType(typeID),
              let kind = MediaKind.from(utType: ut) else {
            return nil
        }

        let folderRelative = relativeComponents.dropLast().joined(separator: "/")
        let filename = relativeComponents.last ?? standardized.lastPathComponent
        let ext = (filename as NSString).pathExtension.lowercased()

        return .media(MediaItemDraft(
            rootID: rootID,
            folderRelativePath: folderRelative,
            filename: filename,
            relativePath: relativePath,
            fileExtension: ext,
            kind: kind,
            size: Int64(values.fileSize ?? 0),
            createdAt: values.creationDate,
            modifiedAt: values.contentModificationDate ?? Date()
        ))
    }
}
