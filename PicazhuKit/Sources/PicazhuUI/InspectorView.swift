import SwiftUI
import PicazhuCore

public struct InspectorItemInfo: Sendable {
    public let filename: String
    public let relativePath: String
    public let sizeText: String
    public let kindLabel: String
    public let dimensionsText: String?
    public let durationText: String?
    public let modifiedText: String
    public let cameraText: String?
    public init(
        filename: String,
        relativePath: String,
        sizeText: String,
        kindLabel: String,
        dimensionsText: String?,
        durationText: String?,
        modifiedText: String,
        cameraText: String?
    ) {
        self.filename = filename
        self.relativePath = relativePath
        self.sizeText = sizeText
        self.kindLabel = kindLabel
        self.dimensionsText = dimensionsText
        self.durationText = durationText
        self.modifiedText = modifiedText
        self.cameraText = cameraText
    }
}

public struct InspectorView: View {
    public let info: InspectorItemInfo?
    public let onReveal: () -> Void
    public let onOpen: () -> Void
    public let onCopyPath: () -> Void
    public let onQuickLook: () -> Void

    public init(
        info: InspectorItemInfo?,
        onReveal: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onCopyPath: @escaping () -> Void,
        onQuickLook: @escaping () -> Void
    ) {
        self.info = info
        self.onReveal = onReveal
        self.onOpen = onOpen
        self.onCopyPath = onCopyPath
        self.onQuickLook = onQuickLook
    }

    public var body: some View {
        Group {
            if let info {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        Text(info.filename)
                            .font(.headline)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Button("Quick Look", systemImage: "eye", action: onQuickLook)
                            Button("Open", systemImage: "arrow.up.right.square", action: onOpen)
                        }
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Button("Reveal", systemImage: "folder", action: onReveal)
                            Button("Copy Path", systemImage: "doc.on.clipboard", action: onCopyPath)
                        }

                        Divider()

                        metadataRow("Kind", info.kindLabel)
                        metadataRow("Size", info.sizeText)
                        if let dims = info.dimensionsText { metadataRow("Dimensions", dims) }
                        if let dur = info.durationText { metadataRow("Duration", dur) }
                        metadataRow("Modified", info.modifiedText)
                        if let cam = info.cameraText { metadataRow("Camera", cam) }
                        metadataRow("Path", info.relativePath)
                    }
                    .padding(DesignTokens.Spacing.lg)
                }
            } else {
                EmptyStateView(
                    symbol: "sidebar.right",
                    title: "No selection",
                    message: "Select a photo or video to see its details."
                )
            }
        }
        .frame(minWidth: 260)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(DesignTokens.Typography.metaLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
