import Foundation
import AppKit
import Quartz
import SwiftUI
import PicazhuCore

@MainActor
public final class QuickLookController: NSObject, @MainActor QLPreviewPanelDataSource, @MainActor QLPreviewPanelDelegate {
    public static let shared = QuickLookController()

    private var urls: [URL] = []
    private var currentIndex: Int = 0

    public func show(urls: [URL], startingAt index: Int = 0) {
        self.urls = urls
        self.currentIndex = max(0, min(index, urls.count - 1))
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = currentIndex
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    public nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}

public enum FileActions {
    public static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func open(_ url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.path]
        try? task.run()
    }

    public static func copyPath(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
    }
}
