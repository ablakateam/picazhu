import Foundation
import ImageCaptureCore
import AppKit
import PicazhuCore

public struct DeviceFile: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let size: Int64
    public let createdAt: Date?
    public let isVideo: Bool
    public let thumbnailData: Data?
}

public struct ConnectedDevice: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let model: String
    public let iconData: Data?
}

@MainActor
public final class DeviceImporter: NSObject, ObservableObject {
    @Published public var devices: [ConnectedDevice] = []
    @Published public var files: [DeviceFile] = []
    @Published public var isImporting: Bool = false
    @Published public var isLoadingDevice: Bool = false
    @Published public var importProgress: Double = 0
    @Published public var importStatus: String = ""
    @Published public var selectedDeviceID: String?

    private var browser: ICDeviceBrowser?
    private var activeDevice: ICCameraDevice?
    private var cameraFiles: [ICCameraFile] = []
    private var importCompletion: ((Int) -> Void)?
    private var importedCount: Int = 0
    private var totalToImport: Int = 0

    public override init() { super.init() }

    public func startBrowsing() {
        let b = ICDeviceBrowser()
        b.delegate = self
        if let mask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue) {
            b.browsedDeviceTypeMask = mask
        }
        b.start()
        browser = b
        PicazhuLog.media.info("Device browser started")
    }

    public func stopBrowsing() {
        browser?.stop()
        browser = nil
    }

    public func selectDevice(_ device: ConnectedDevice) {
        selectedDeviceID = device.id
        files = []
        cameraFiles = []
        isLoadingDevice = true

        guard let icDevice = browser?.devices?.first(where: {
            $0.name == device.name || "\($0.transportType)" == device.id
        }) else {
            isLoadingDevice = false
            return
        }

        if let cam = icDevice as? ICCameraDevice {
            activeDevice = cam
            cam.delegate = self
            if !cam.hasOpenSession {
                cam.requestOpenSession()
            } else {
                isLoadingDevice = false
            }
        } else {
            isLoadingDevice = false
        }
    }

    public func importFiles(_ fileNames: Set<String>, to destination: URL, completion: @escaping @Sendable (Int) -> Void) {
        guard let device = activeDevice else { completion(0); return }

        let toImport = cameraFiles.filter { fileNames.contains($0.name ?? "") }
        guard !toImport.isEmpty else { completion(0); return }

        isImporting = true
        importProgress = 0
        importedCount = 0
        totalToImport = toImport.count
        importCompletion = completion
        importStatus = "Importing 0/\(totalToImport)…"

        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        // Download files one at a time to avoid overwhelming the device
        Task {
            for file in toImport {
                await downloadFile(file, from: device, to: destination)
            }
            await MainActor.run {
                self.isImporting = false
                self.importStatus = "Done — \(self.importedCount) files imported"
                self.importCompletion?(self.importedCount)
                self.importCompletion = nil
            }
        }
    }

    private func downloadFile(_ file: ICCameraFile, from device: ICCameraDevice, to destination: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let name = file.name ?? "unknown"
            self.pendingDownloadContinuation = cont
            self.importStatus = "Importing \(name)…"

            device.requestDownloadFile(file, options: [
                ICDownloadOption.downloadsDirectoryURL: destination,
                ICDownloadOption.overwrite: true
            ], downloadDelegate: self,
               didDownloadSelector: #selector(DeviceImporter.icDidDownload(_:error:options:contextInfo:)),
               contextInfo: nil)

            // Timeout after 60 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                if let cont = self?.pendingDownloadContinuation {
                    self?.pendingDownloadContinuation = nil
                    PicazhuLog.media.error("Download timeout for \(name)")
                    cont.resume()
                }
            }
        }
    }

    private var pendingDownloadContinuation: CheckedContinuation<Void, Never>?

    @objc(icDidDownload:error:options:contextInfo:)
    private func icDidDownload(_ file: ICCameraFile, error: NSError?, options: [String: Any]?, contextInfo: UnsafeMutableRawPointer?) {
        let cont = pendingDownloadContinuation
        pendingDownloadContinuation = nil

        if let error {
            PicazhuLog.media.error("Download failed for \(file.name ?? ""): \(error.localizedDescription)")
        } else {
            importedCount += 1
            importProgress = Double(importedCount) / Double(max(1, totalToImport))
            importStatus = "Imported \(importedCount)/\(totalToImport)"
            PicazhuLog.media.info("Imported \(file.name ?? "") (\(self.importedCount)/\(self.totalToImport))")
        }

        cont?.resume()
    }

    public func importAll(to destination: URL, completion: @escaping @Sendable (Int) -> Void) {
        importFiles(Set(files.map(\.name)), to: destination, completion: completion)
    }

    private func processNewFiles(_ camFiles: [ICCameraFile]) {
        // Build file entries quickly without heavy image work
        let newFiles = camFiles.map { item -> DeviceFile in
            let name = item.name ?? "Unknown"
            let ext = (name as NSString).pathExtension.lowercased()
            let isVideo = ["mov", "mp4", "m4v", "avi", "hevc"].contains(ext)
            return DeviceFile(
                id: name, name: name,
                size: Int64(item.fileSize),
                createdAt: item.creationDate,
                isVideo: isVideo,
                thumbnailData: nil
            )
        }
        self.cameraFiles.append(contentsOf: camFiles)
        self.files.append(contentsOf: newFiles)

        // Extract thumbnails that are already available
        for file in camFiles {
            guard let thumb = file.thumbnailIfAvailable, let name = file.name else { continue }
            let nsImage = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
            guard let tiff = nsImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { continue }
            if let idx = self.files.firstIndex(where: { $0.name == name }) {
                let old = self.files[idx]
                self.files[idx] = DeviceFile(
                    id: old.id, name: old.name, size: old.size,
                    createdAt: old.createdAt, isVideo: old.isVideo,
                    thumbnailData: jpeg
                )
            }
        }
    }
}

extension DeviceImporter: @preconcurrency ICDeviceBrowserDelegate {
    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        let name = device.name ?? "Unknown Device"
        let id = name
        let model = (device.value(forKey: "productKind") as? String)
            ?? (device.value(forKey: "modelString") as? String) ?? ""
        var iconData: Data?
        if let icon = device.icon {
            let nsImage = NSImage(cgImage: icon, size: NSSize(width: icon.width, height: icon.height))
            iconData = nsImage.tiffRepresentation
        }
        Task { @MainActor in
            if !self.devices.contains(where: { $0.id == id }) {
                self.devices.append(ConnectedDevice(id: id, name: name, model: model, iconData: iconData))
                PicazhuLog.media.info("Device connected: \(name) (\(model))")
            }
        }
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        let name = device.name ?? ""
        Task { @MainActor in
            self.devices.removeAll { $0.name == name }
            if self.selectedDeviceID == name {
                self.selectedDeviceID = nil
                self.files = []
                self.cameraFiles = []
                self.activeDevice = nil
            }
        }
    }
}

extension DeviceImporter: @preconcurrency ICCameraDeviceDownloadDelegate {}

extension DeviceImporter: @preconcurrency ICCameraDeviceDelegate {
    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        let camFiles = items.compactMap { $0 as? ICCameraFile }
        guard !camFiles.isEmpty else { return }
        Task { @MainActor in
            self.processNewFiles(camFiles)
            PicazhuLog.media.info("Device: \(self.files.count) files loaded")
        }
    }

    public func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        let names = Set(items.compactMap(\.name))
        Task { @MainActor in
            self.cameraFiles.removeAll { names.contains($0.name ?? "") }
            self.files.removeAll { names.contains($0.name) }
        }
    }

    public func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {
        guard let thumbnail, let name = item.name else { return }
        let nsImage = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { return }
        Task { @MainActor in
            if let idx = self.files.firstIndex(where: { $0.name == name }) {
                let old = self.files[idx]
                self.files[idx] = DeviceFile(
                    id: old.id, name: old.name, size: old.size,
                    createdAt: old.createdAt, isVideo: old.isVideo,
                    thumbnailData: jpeg
                )
            }
        }
    }

    public func deviceDidBecomeReady(_ device: ICDevice) {
        PicazhuLog.media.info("Device ready: \(device.name ?? "")")
    }

    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task { @MainActor in
            self.isLoadingDevice = false
            PicazhuLog.media.info("Device catalog complete: \(device.name ?? "") — \(self.files.count) files")
        }
    }

    public func didRemove(_ device: ICDevice) {
        let name = device.name ?? ""
        Task { @MainActor in
            self.devices.removeAll { $0.name == name }
            if self.selectedDeviceID == name {
                self.selectedDeviceID = nil
                self.files = []
                self.cameraFiles = []
                self.activeDevice = nil
            }
        }
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        Task { @MainActor in self.isLoadingDevice = false }
    }
    public func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error {
            PicazhuLog.media.error("Session open failed: \(error.localizedDescription)")
            Task { @MainActor in self.isLoadingDevice = false }
        }
    }
    public func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    public func cameraDevice(_ camera: ICCameraDevice, didCompleteDeleteFilesWithError error: (any Error)?) {}
    public func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: (any Error)?) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    public func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    public func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}
