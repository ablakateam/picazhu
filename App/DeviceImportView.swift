import SwiftUI
import AppKit
import PicazhuMedia
import PicazhuUI

struct DeviceImportView: View {
    @ObservedObject var importer: DeviceImporter
    let onImportComplete: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFiles: Set<String> = []
    @State private var selectAll = true
    @State private var importDestination: URL?
    @State private var showFolderPicker = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if importer.files.isEmpty {
                loadingView
            } else {
                fileList
            }

            Divider()
            footer
        }
        .frame(width: 620, height: 520)
        .onAppear {
            selectedFiles = Set(importer.files.map(\.name))
        }
        .onChange(of: importer.files.count) { _, _ in
            if selectAll { selectedFiles = Set(importer.files.map(\.name)) }
        }
    }

    private var currentDevice: ConnectedDevice? {
        importer.devices.first(where: { $0.id == importer.selectedDeviceID })
    }

    private var header: some View {
        HStack {
            if let iconData = currentDevice?.iconData, let icon = NSImage(data: iconData) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(currentDevice?.name ?? "iPhone")
                    .font(.headline)
                if let model = currentDevice?.model, !model.isEmpty {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text("\(importer.files.count) files · \(imageCount) photos · \(videoCount) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if importer.isImporting {
                ProgressView(value: importer.importProgress)
                    .frame(width: 120)
                Text(importer.importStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            if importer.isLoadingDevice {
                Text("Connecting to \(currentDevice?.name ?? "device")…")
                    .foregroundStyle(.secondary)
            } else {
                Text("Reading files from device…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Select All", isOn: $selectAll)
                    .onChange(of: selectAll) { _, newValue in
                        if newValue {
                            selectedFiles = Set(importer.files.map(\.name))
                        } else {
                            selectedFiles.removeAll()
                        }
                    }
                Spacer()
                Text("\(selectedFiles.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(importer.files) { file in
                        DeviceFileCell(
                            file: file,
                            isSelected: selectedFiles.contains(file.name)
                        )
                        .onTapGesture {
                            if selectedFiles.contains(file.name) {
                                selectedFiles.remove(file.name)
                                selectAll = false
                            } else {
                                selectedFiles.insert(file.name)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            if let dest = importDestination {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                    Text(dest.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Choose Folder…") {
                pickFolder()
            }

            Button("Import \(selectedFiles.count) Files") {
                startImport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedFiles.isEmpty || importDestination == nil || importer.isImporting)
        }
        .padding(16)
    }

    private var imageCount: Int {
        importer.files.filter { !$0.isVideo }.count
    }

    private var videoCount: Int {
        importer.files.filter { $0.isVideo }.count
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Import Here"
        panel.message = "Choose a folder to import files into"
        if panel.runModal() == .OK, let url = panel.url {
            importDestination = url
        }
    }

    private func startImport() {
        guard let dest = importDestination else { return }
        importer.importFiles(selectedFiles, to: dest) { count in
            if count > 0 {
                onImportComplete(dest)
            }
        }
    }
}

struct DeviceFileCell: View {
    let file: DeviceFile
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let data = file.thumbnailData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: file.isVideo ? "film" : "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }

                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, .blue)
                                .font(.system(size: 16))
                                .padding(4)
                        }
                        Spacer()
                    }
                }

                if file.isVideo {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "video.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Capsule().fill(.black.opacity(0.6)))
                                .padding(4)
                        }
                    }
                }
            }
            .frame(width: 100, height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.blue : .clear, lineWidth: 2)
            )

            Text(file.name)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 100)
                .foregroundStyle(.secondary)
        }
    }
}
