import SwiftUI
import PicazhuCore

@MainActor
@Observable
final class DebugLog {
    static let shared = DebugLog()

    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        let level: String
        let message: String
    }

    private(set) var entries: [Entry] = []
    var isVisible: Bool = false
    private let maxEntries = 200

    func log(_ message: String, level: String = "INFO") {
        let entry = Entry(time: Date(), level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func info(_ msg: String) { log(msg, level: "INFO") }
    func error(_ msg: String) { log(msg, level: "ERROR") }
    func warn(_ msg: String) { log(msg, level: "WARN") }
    func clear() { entries.removeAll() }
}

struct DebugConsoleView: View {
    let debugLog: DebugLog

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundStyle(.green)
                Text("Debug Console")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                Text("\(debugLog.entries.count) entries")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Clear") { debugLog.clear() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button {
                    debugLog.isVisible = false
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(debugLog.entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.timeFmt.string(from: entry.time))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text(entry.level)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(levelColor(entry.level))
                                    .frame(width: 40, alignment: .leading)
                                Text(entry.message)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: debugLog.entries.count) { _, _ in
                    if let last = debugLog.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Color(white: 0.08))
        }
        .frame(height: 180)
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "ERROR": return .red
        case "WARN": return .orange
        default: return .green
        }
    }
}
