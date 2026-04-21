import SwiftUI

public struct AIInspectorInfo: Sendable, Equatable {
    public let caption: String
    public let tags: [String]
    public let objects: [String]
    public let scene: String
    public let ocrText: String
    public let confidence: Double
    public let modelVersion: String

    public init(
        caption: String,
        tags: [String],
        objects: [String],
        scene: String,
        ocrText: String,
        confidence: Double,
        modelVersion: String
    ) {
        self.caption = caption
        self.tags = tags
        self.objects = objects
        self.scene = scene
        self.ocrText = ocrText
        self.confidence = confidence
        self.modelVersion = modelVersion
    }

    public var isEmpty: Bool {
        caption.isEmpty && tags.isEmpty && objects.isEmpty && scene.isEmpty && ocrText.isEmpty
    }
}

public struct AIInspectorSection: View {
    public let info: AIInspectorInfo?
    public let isAnalyzing: Bool
    public let onReanalyze: () -> Void
    public let onClear: () -> Void

    public init(
        info: AIInspectorInfo?,
        isAnalyzing: Bool,
        onReanalyze: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) {
        self.info = info
        self.isAnalyzing = isAnalyzing
        self.onReanalyze = onReanalyze
        self.onClear = onClear
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("AI Analysis")
                    .font(.headline)
                Spacer()
                if isAnalyzing {
                    ProgressView().controlSize(.small)
                }
            }

            if let info, !info.isEmpty {
                if !info.caption.isEmpty {
                    Text(info.caption)
                        .font(.body)
                        .textSelection(.enabled)
                }

                if !info.scene.isEmpty {
                    metadataRow("Scene", info.scene)
                }

                if !info.tags.isEmpty {
                    TagPillList(title: "Tags", items: info.tags)
                }
                if !info.objects.isEmpty {
                    TagPillList(title: "Objects", items: info.objects)
                }

                if !info.ocrText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TEXT IN IMAGE")
                            .font(DesignTokens.Typography.metaLabel)
                            .foregroundStyle(.secondary)
                        Text(info.ocrText)
                            .font(.callout)
                            .textSelection(.enabled)
                            .padding(DesignTokens.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .fill(DesignTokens.Palette.card)
                            )
                    }
                }

                if !info.modelVersion.isEmpty {
                    Text(info.modelVersion)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button("Re-analyze", systemImage: "arrow.clockwise", action: onReanalyze)
                    Button("Clear", systemImage: "trash", role: .destructive, action: onClear)
                }
                .controlSize(.small)
            } else if isAnalyzing {
                Text("Analyzing…")
                    .foregroundStyle(.secondary)
            } else {
                Text("Not analyzed yet")
                    .foregroundStyle(.secondary)
                Button("Analyze Now", systemImage: "sparkles", action: onReanalyze)
                    .controlSize(.small)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.accentColor.opacity(0.06))
        )
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(DesignTokens.Typography.metaLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

struct TagPillList: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(DesignTokens.Typography.metaLabel)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.15))
                        )
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var rowWidth: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                width = max(width, rowWidth - spacing)
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        width = max(width, rowWidth - spacing)
        height += rowHeight
        return CGSize(width: max(0, width), height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
