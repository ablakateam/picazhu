import XCTest
@testable import PicazhuMedia

final class ThumbnailCacheTests: XCTestCase {
    func testCacheReadWriteRoundtrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("picazhu-cache-\(UUID().uuidString)", isDirectory: true)
        let cache = try ThumbnailCache(root: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let data = Data([1, 2, 3, 4, 5])
        await cache.write(key: "deadbeef", data: data)
        let read = await cache.read(key: "deadbeef")
        XCTAssertEqual(read, data)
    }
}
