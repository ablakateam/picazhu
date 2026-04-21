import SwiftUI

public struct AIProgressSnapshot: Sendable, Equatable {
    public enum Stage: String, Sendable {
        case ocr
        case vlm
        case embed
        case idle
    }

    public var total: Int
    public var completed: Int
    public var failed: Int
    public var stage: Stage
    public var currentItemName: String
    public var ratePerSecond: Double
    public var isPaused: Bool
    public var isActive: Bool
    public var itemElapsed: TimeInterval

    public init(
        total: Int = 0,
        completed: Int = 0,
        failed: Int = 0,
        stage: Stage = .idle,
        currentItemName: String = "",
        ratePerSecond: Double = 0,
        isPaused: Bool = false,
        isActive: Bool = false,
        itemElapsed: TimeInterval = 0
    ) {
        self.total = total
        self.completed = completed
        self.failed = failed
        self.stage = stage
        self.currentItemName = currentItemName
        self.ratePerSecond = ratePerSecond
        self.isPaused = isPaused
        self.isActive = isActive
        self.itemElapsed = itemElapsed
    }

    public var progressValue: Double {
        guard total > 0 else { return 0 }
        let stageWeight: Double = switch stage {
        case .ocr:   0.1
        case .vlm:   0.5
        case .embed: 0.9
        case .idle:  0.0
        }
        let itemProgress = (Double(completed) + stageWeight) / Double(total)
        return min(1.0, max(0.0, itemProgress))
    }

    public var remaining: Int { max(0, total - completed - failed) }

    public var etaText: String {
        guard ratePerSecond > 0, remaining > 0 else { return "—" }
        let seconds = Double(remaining) / ratePerSecond
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        if seconds < 3600 {
            return String(format: "%dm %ds", Int(seconds) / 60, Int(seconds) % 60)
        }
        return String(format: "%dh %dm", Int(seconds) / 3600, (Int(seconds) % 3600) / 60)
    }

    public var percentText: String {
        guard total > 0 else { return "—" }
        return String(format: "%d%%", Int(progressValue * 100))
    }
}

public struct AIProgressBar: View {
    public let snapshot: AIProgressSnapshot
    public let onPauseToggle: () -> Void
    public let onCancel: () -> Void

    public init(
        snapshot: AIProgressSnapshot,
        onPauseToggle: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.onPauseToggle = onPauseToggle
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            stageBadge
                .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(titleText)
                        .font(.callout.weight(.semibold))
                    if !snapshot.currentItemName.isEmpty && !snapshot.currentItemName.hasPrefix("Error:") {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(snapshot.currentItemName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if snapshot.itemElapsed > 0 && snapshot.stage != .idle {
                        Text(elapsedText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Text(countsText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("ETA \(snapshot.etaText)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if snapshot.currentItemName.hasPrefix("Error:") {
                    Text(snapshot.currentItemName)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                ProgressView(value: snapshot.progressValue)
                    .progressViewStyle(.linear)
                    .tint(snapshot.isPaused ? Color.orange : Color.accentColor)
                    .animation(.easeInOut(duration: 0.5), value: snapshot.progressValue)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    onPauseToggle()
                } label: {
                    Image(systemName: snapshot.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderless)
                .help(snapshot.isPaused ? "Resume" : "Pause")

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var titleText: String {
        switch snapshot.stage {
        case .ocr: return "Step 1/3 · Reading text"
        case .vlm: return "Step 2/3 · Analyzing image"
        case .embed: return "Step 3/3 · Building index"
        case .idle: return snapshot.isPaused ? "Paused" : (snapshot.completed > 0 ? "Processing…" : "Starting…")
        }
    }

    private var elapsedText: String {
        let s = Int(snapshot.itemElapsed)
        return s < 60 ? "\(s)s" : "\(s/60)m \(s%60)s"
    }

    private var countsText: String {
        "\(snapshot.completed)/\(snapshot.total)"
            + (snapshot.failed > 0 ? " (\(snapshot.failed) failed)" : "")
    }

    private var stageBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: stageIcon)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
            Text(snapshot.percentText)
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    private var stageIcon: String {
        switch snapshot.stage {
        case .ocr: return "textformat.abc"
        case .vlm: return "sparkles"
        case .embed: return "point.3.connected.trianglepath.dotted"
        case .idle: return "checkmark.circle.fill"
        }
    }
}

public struct AIProgressChip: View {
    public let snapshot: AIProgressSnapshot
    public init(snapshot: AIProgressSnapshot) { self.snapshot = snapshot }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
            Text(snapshot.percentText)
                .font(.caption.monospacedDigit().weight(.semibold))
            if snapshot.total > 0 {
                Text("\(snapshot.completed)/\(snapshot.total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.15))
        )
    }
}
