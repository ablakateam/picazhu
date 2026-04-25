import Foundation
import CoreServices
import PicazhuCore

public final class FolderWatcher: @unchecked Sendable {
    public typealias EventHandler = @Sendable ([URL]) -> Void

    private var stream: FSEventStreamRef?
    private let url: URL
    private let handler: EventHandler
    private let queue = DispatchQueue(label: "com.picazhu.fswatcher")

    public init(url: URL, handler: @escaping EventHandler) {
        self.url = url
        self.handler = handler
    }

    public func start() {
        stop()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [url.path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes
        )
        let latency: CFTimeInterval = 1.0

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
            let urls = paths.prefix(numEvents).map { URL(fileURLWithPath: $0) }
            watcher.handler(Array(urls))
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            PicazhuLog.indexing.error("FSEventStreamCreate failed")
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        stop()
    }
}
