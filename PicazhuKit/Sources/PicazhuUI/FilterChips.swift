import SwiftUI
import PicazhuCore

public struct FilterState: Equatable, Sendable {
    public var kinds: Set<MediaKind> = []
    public var datePreset: DatePreset = .any
    public var sizePreset: SizePreset = .any
    public var aiOnly: Bool = false

    public var isActive: Bool {
        !kinds.isEmpty || datePreset != .any || sizePreset != .any || aiOnly
    }

    public func reset() -> FilterState {
        FilterState()
    }

    public init() {}

    public enum DatePreset: String, CaseIterable, Sendable {
        case any = "Any time"
        case today = "Today"
        case week = "This week"
        case month = "This month"
        case year = "This year"

        public var dateRange: ClosedRange<Date>? {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .any: return nil
            case .today: return cal.startOfDay(for: now)...now
            case .week: return cal.date(byAdding: .day, value: -7, to: now)!...now
            case .month: return cal.date(byAdding: .month, value: -1, to: now)!...now
            case .year: return cal.date(byAdding: .year, value: -1, to: now)!...now
            }
        }
    }

    public enum SizePreset: String, CaseIterable, Sendable {
        case any = "Any size"
        case small = "< 1 MB"
        case medium = "1–10 MB"
        case large = "> 10 MB"

        public var sizeRange: ClosedRange<Int64>? {
            switch self {
            case .any: return nil
            case .small: return 0...1_000_000
            case .medium: return 1_000_000...10_000_000
            case .large: return 10_000_000...Int64.max
            }
        }
    }
}

public struct FilterChipsBar: View {
    @Binding public var filter: FilterState
    public let onApply: () -> Void

    public init(filter: Binding<FilterState>, onApply: @escaping () -> Void) {
        self._filter = filter
        self.onApply = onApply
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Kind chips
                kindChip("Images", systemImage: "photo", kind: .image)
                kindChip("Videos", systemImage: "film", kind: .video)

                divider

                // Date chips
                Menu {
                    ForEach(FilterState.DatePreset.allCases, id: \.self) { preset in
                        Button {
                            filter.datePreset = preset
                            onApply()
                        } label: {
                            HStack {
                                Text(preset.rawValue)
                                if filter.datePreset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    chipLabel(
                        filter.datePreset == .any ? "Date" : filter.datePreset.rawValue,
                        systemImage: "calendar",
                        active: filter.datePreset != .any
                    )
                }
                .buttonStyle(.plain)

                // Size chips
                Menu {
                    ForEach(FilterState.SizePreset.allCases, id: \.self) { preset in
                        Button {
                            filter.sizePreset = preset
                            onApply()
                        } label: {
                            HStack {
                                Text(preset.rawValue)
                                if filter.sizePreset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    chipLabel(
                        filter.sizePreset == .any ? "Size" : filter.sizePreset.rawValue,
                        systemImage: "internaldrive",
                        active: filter.sizePreset != .any
                    )
                }
                .buttonStyle(.plain)

                divider

                // AI filter
                toggleChip("AI Analyzed", systemImage: "sparkles", active: filter.aiOnly) {
                    filter.aiOnly.toggle()
                    onApply()
                }

                if filter.isActive {
                    divider
                    Button {
                        filter = filter.reset()
                        onApply()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Clear")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
        }
        .frame(height: 32)
    }

    private func kindChip(_ label: String, systemImage: String, kind: MediaKind) -> some View {
        let active = filter.kinds.contains(kind)
        return toggleChip(label, systemImage: systemImage, active: active) {
            if active {
                filter.kinds.remove(kind)
            } else {
                filter.kinds.insert(kind)
            }
            onApply()
        }
    }

    private func toggleChip(_ label: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(label, systemImage: systemImage, active: active)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ label: String, systemImage: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
            Text(label)
                .font(.caption.weight(active ? .semibold : .regular))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(active ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule()
                .strokeBorder(active ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .foregroundStyle(active ? Color.accentColor : .secondary)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 18)
    }
}
