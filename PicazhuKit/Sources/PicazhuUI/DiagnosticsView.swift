import SwiftUI
import PicazhuCore

public struct DiagnosticsRootRow: Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let access: String
    public init(id: Int, name: String, access: String) {
        self.id = id
        self.name = name
        self.access = access
    }
}

public struct DiagnosticsDisplay: Sendable {
    public let roots: [DiagnosticsRootRow]
    public let imageCount: Int
    public let videoCount: Int
    public let pendingThumbs: Int
    public let pendingMetadata: Int
    public let cacheSizeText: String
    public let dbSizeText: String
    public let integrity: String
    public let activeAIProvider: String
    public let aiEnriched: Int
    public let aiPending: Int
    public let aiFailed: Int
    public let aiEmbeddings: Int

    public init(
        roots: [DiagnosticsRootRow],
        imageCount: Int,
        videoCount: Int,
        pendingThumbs: Int,
        pendingMetadata: Int,
        cacheSizeText: String,
        dbSizeText: String,
        integrity: String,
        activeAIProvider: String,
        aiEnriched: Int = 0,
        aiPending: Int = 0,
        aiFailed: Int = 0,
        aiEmbeddings: Int = 0
    ) {
        self.roots = roots
        self.imageCount = imageCount
        self.videoCount = videoCount
        self.pendingThumbs = pendingThumbs
        self.pendingMetadata = pendingMetadata
        self.cacheSizeText = cacheSizeText
        self.dbSizeText = dbSizeText
        self.integrity = integrity
        self.activeAIProvider = activeAIProvider
        self.aiEnriched = aiEnriched
        self.aiPending = aiPending
        self.aiFailed = aiFailed
        self.aiEmbeddings = aiEmbeddings
    }
}

struct RootRowList: View {
    let rows: [DiagnosticsRootRow]

    var body: some View {
        if rows.isEmpty {
            AnyView(Text("None").foregroundStyle(.secondary))
        } else {
            AnyView(
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    ForEach(rows) { (row: DiagnosticsRootRow) in
                        HStack {
                            Text(verbatim: row.name)
                            Spacer()
                            Text(verbatim: row.access)
                                .foregroundStyle(row.access == "ok" ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Color.orange))
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
            )
        }
    }
}

public struct DiagnosticsView: View {
    public let display: DiagnosticsDisplay?
    public let onRefresh: () -> Void
    public let onPurgeCache: () -> Void
    public let onRebuildCatalog: () -> Void
    public let onClearAllAI: () -> Void

    public init(
        display: DiagnosticsDisplay?,
        onRefresh: @escaping () -> Void,
        onPurgeCache: @escaping () -> Void,
        onRebuildCatalog: @escaping () -> Void,
        onClearAllAI: @escaping () -> Void = {}
    ) {
        self.display = display
        self.onRefresh = onRefresh
        self.onPurgeCache = onPurgeCache
        self.onRebuildCatalog = onRebuildCatalog
        self.onClearAllAI = onClearAllAI
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                HStack {
                    Text("Diagnostics")
                        .font(.largeTitle.weight(.semibold))
                    Spacer()
                    Button("Refresh", action: onRefresh)
                }

                if let d = display {
                    rootsSection(rows: d.roots)

                    section("Library") {
                        row("Images", "\(d.imageCount)")
                        row("Videos", "\(d.videoCount)")
                    }

                    section("Queues") {
                        row("Pending thumbnails", "\(d.pendingThumbs)")
                        row("Pending metadata", "\(d.pendingMetadata)")
                    }

                    section("Storage") {
                        row("Thumbnail cache", d.cacheSizeText)
                        row("Database", d.dbSizeText)
                        row("Integrity", d.integrity)
                    }

                    section("AI") {
                        row("Active provider", d.activeAIProvider)
                        row("Enriched items", "\(d.aiEnriched)")
                        row("Pending jobs", "\(d.aiPending)")
                        row("Failed jobs", "\(d.aiFailed)")
                        row("Embeddings stored", "\(d.aiEmbeddings)")
                    }

                    HStack(spacing: DesignTokens.Spacing.md) {
                        Button("Purge thumbnail cache", action: onPurgeCache)
                        Button("Rebuild catalog", role: .destructive, action: onRebuildCatalog)
                        Button("Clear all AI data", role: .destructive, action: onClearAllAI)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private func rootsSection(rows: [DiagnosticsRootRow]) -> some View {
        section("Watched roots") {
            RootRowList(rows: rows)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title.uppercased())
                .font(DesignTokens.Typography.metaLabel)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                content()
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(DesignTokens.Palette.card)
            )
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.callout.monospacedDigit())
        }
    }
}
