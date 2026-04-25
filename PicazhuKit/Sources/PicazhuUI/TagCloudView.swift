import SwiftUI

public struct TagItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let tag: String
    public let count: Int
    public init(tag: String, count: Int) {
        self.id = tag
        self.tag = tag
        self.count = count
    }
}

public struct TagCloudView: View {
    public let tags: [TagItem]
    public let onTap: (String) -> Void
    @State private var appeared = false

    public init(tags: [TagItem], onTap: @escaping (String) -> Void) {
        self.tags = tags
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.purple)
                Text("Tags")
                    .font(.headline)
                Spacer()
                Text("\(tags.count) tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if tags.isEmpty {
                Text("Analyze media with AI to generate tags.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DesignTokens.Spacing.md)
            } else {
                ScrollView {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(tags.enumerated()), id: \.element.id) { index, item in
                            TagPill(item: item, rank: rank(for: item), index: index, appeared: appeared) {
                                onTap(item.tag)
                            }
                        }
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    private func rank(for item: TagItem) -> Double {
        guard let max = tags.first?.count, max > 0 else { return 0.5 }
        return Double(item.count) / Double(max)
    }
}

struct TagPill: View {
    let item: TagItem
    let rank: Double
    let index: Int
    let appeared: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(item.tag)
                    .font(.system(size: fontSize, weight: fontWeight))
                Text("\(item.count)")
                    .font(.system(size: max(9, fontSize - 2), design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(pillColor)
            )
            .overlay(
                Capsule().strokeBorder(hovering ? Color.purple.opacity(0.5) : .clear, lineWidth: 1)
            )
            .foregroundStyle(textColor)
            .scaleEffect(hovering ? 1.08 : 1.0)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.015), value: appeared)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(item.count) items tagged \"\(item.tag)\"")
    }

    private var fontSize: CGFloat {
        let base: CGFloat = 11
        let scale: CGFloat = 5
        return base + CGFloat(rank) * scale
    }

    private var fontWeight: Font.Weight {
        rank > 0.6 ? .semibold : .regular
    }

    private var pillColor: Color {
        if rank > 0.7 {
            return Color.purple.opacity(hovering ? 0.3 : 0.2)
        } else if rank > 0.4 {
            return Color.accentColor.opacity(hovering ? 0.2 : 0.12)
        } else {
            return Color(nsColor: .controlBackgroundColor).opacity(hovering ? 0.9 : 0.7)
        }
    }

    private var textColor: Color {
        rank > 0.5 ? .primary : .secondary
    }
}
