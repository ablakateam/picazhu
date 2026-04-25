import Foundation
import GRDB
import PicazhuCore

public enum DatabaseLocation: Sendable {
    case applicationSupport
    case inMemory
    case file(URL)

    public func resolveURL(fileManager: FileManager = .default) throws -> URL? {
        switch self {
        case .inMemory:
            return nil
        case .file(let url):
            return url
        case .applicationSupport:
            let base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = base.appendingPathComponent("PICAZHU", isDirectory: true)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("catalog.sqlite", isDirectory: false)
        }
    }
}

public struct Catalog: Sendable {
    public let dbPool: DatabaseWriter

    public init(location: DatabaseLocation = .applicationSupport) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL;")
            try db.execute(sql: "PRAGMA synchronous = NORMAL;")
            try db.execute(sql: "PRAGMA temp_store = MEMORY;")
        }

        if let url = try location.resolveURL() {
            self.dbPool = try DatabasePool(path: url.path, configuration: config)
        } else {
            self.dbPool = try DatabaseQueue(configuration: config)
        }

        try Migrations.migrator().migrate(self.dbPool)
        PicazhuLog.data.info("Catalog opened at \(String(describing: try? location.resolveURL()?.path))")
    }

    public var reader: DatabaseReader { dbPool }
    public var writer: DatabaseWriter { dbPool }
}
