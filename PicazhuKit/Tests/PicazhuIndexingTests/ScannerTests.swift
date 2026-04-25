import XCTest
@testable import PicazhuIndexing
import PicazhuCore

final class ScannerTests: XCTestCase {
    func testScanEnumeratesMediaFiles() throws {
        let tmp = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("album", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let jpeg = sub.appendingPathComponent("a.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]).write(to: jpeg)

        let text = tmp.appendingPathComponent("readme.txt")
        try "ignore me".write(to: text, atomically: true, encoding: .utf8)

        let result = try FileSystemScanner.scan(rootURL: tmp, rootID: WatchedRootID(rawValue: 1))
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts.first?.filename, "a.jpg")
        XCTAssertEqual(result.drafts.first?.kind, .image)
    }
}
