import Foundation
import SwiftUI

struct OllamaStatus: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case unknown
        case checking
        case unreachable(String)
        case modelMissing(String)
        case ready
        case loaded(vramMB: Int)
    }

    var state: State = .unknown
    var isCloud: Bool = false
    var visionModel: String = ""
    var embeddingModel: String = ""
    var lastCheckedAt: Date?

    var providerLabel: String = ""

    var displayText: String {
        let label = providerLabel.isEmpty ? (isCloud ? "Cloud" : "Local") : providerLabel
        switch state {
        case .unknown, .checking: return label
        case .unreachable: return "Offline"
        case .modelMissing: return "Setup"
        case .ready, .loaded: return label
        }
    }

    var color: Color {
        switch state {
        case .unknown, .checking: return .secondary
        case .unreachable: return .red
        case .modelMissing: return .orange
        case .ready: return .yellow
        case .loaded: return .green
        }
    }

    var iconName: String {
        switch state {
        case .unknown, .checking: return "questionmark.circle"
        case .unreachable: return "exclamationmark.triangle.fill"
        case .modelMissing: return "arrow.down.circle"
        case .ready: return "circle.dotted"
        case .loaded: return "checkmark.circle.fill"
        }
    }
}

struct OllamaStatusPill: View {
    let status: OllamaStatus
    let onRefresh: () -> Void

    var body: some View {
        Button(action: onRefresh) {
            HStack(spacing: 6) {
                Image(systemName: status.iconName)
                    .foregroundStyle(status.color)
                Text(status.displayText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule().strokeBorder(status.color.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Click to refresh Ollama status")
    }
}
