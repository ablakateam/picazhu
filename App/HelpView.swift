import SwiftUI
import PicazhuUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text("Quick Start Guide")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Getting Started", [
                        step("1", "folder.badge.plus", "Add a Folder", "Click the **Add Folder** button or drag a folder from Finder onto the window. PICAZHU indexes your photos and videos without moving or copying them."),
                        step("2", "eye", "Browse & Preview", "Click any thumbnail to see details. **Double-click** or press **Enter** to open. Press **Space** for Quick Look."),
                        step("3", "sparkles", "Analyze with AI", "Click the **✨ Analyze** button or right-click a folder → **Analyze with AI**. PICAZHU uses Qwen3-VL to caption every photo and video."),
                        step("4", "magnifyingglass", "Search Anything", "Type in the search bar to find photos by content: *\"dog on beach\"*, *\"red car\"*, *\"WALMART sign\"*. Toggle 🌐 for global search across all folders."),
                    ])

                    section("Keyboard Shortcuts", [
                        shortcut("⌘N", "Add folder"),
                        shortcut("⌘⇧I", "Analyze current folder with AI"),
                        shortcut("Space", "Quick Look preview"),
                        shortcut("Enter", "Open in default app"),
                        shortcut("⌘⇧R", "Reveal in Finder"),
                        shortcut("⌘⌥C", "Copy file path"),
                        shortcut("← → ↑ ↓", "Navigate grid"),
                        shortcut("⌘- / ⌘=", "Thumbnail size"),
                        shortcut("⌘⇧D", "Diagnostics"),
                    ])

                    section("AI Setup", [
                        tip("local", "**Local mode** — Install [Ollama](https://ollama.com), then run `ollama pull qwen3-vl:8b` and `ollama pull nomic-embed-text`. Free, private, runs on your Mac."),
                        tip("cloud", "**Cloud mode** — Click ⚙ Settings → Ollama Cloud → enter your API key from [ollama.com/settings/keys](https://ollama.com/settings/keys). Faster, uses the 235B model."),
                        tip("ocr", "**Text in images** — PICAZHU uses Apple Vision to read text in photos (signs, labels, screens). This runs automatically and locally — no setup needed."),
                    ])

                    section("Tips", [
                        tip("filter", "Use **filter chips** below the search bar to narrow by type (Images/Videos), date, size, or AI-analyzed status."),
                        tip("badge", "Look for the **✨ AI** badge on thumbnails — it means that photo has been analyzed and is searchable by content."),
                        tip("debug", "Click the **⌨ terminal** icon in the toolbar to see the debug console — useful for troubleshooting AI issues."),
                        tip("diag", "Open **Diagnostics** (⌘⇧D) to see library stats, queue status, and manage cache."),
                    ])
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 600)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<items.count, id: \.self) { i in
                    items[i]
                }
            }
        }
    }

    private func step(_ num: String, _ icon: String, _ title: String, _ desc: String) -> AnyView {
        AnyView(
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(.init(desc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }

    private func shortcut(_ keys: String, _ desc: String) -> AnyView {
        AnyView(
            HStack(spacing: 12) {
                Text(keys)
                    .font(.system(size: 11, design: .monospaced).weight(.semibold))
                    .frame(width: 80, alignment: .trailing)
                    .foregroundStyle(.purple)
                Text(desc)
                    .font(.callout)
                Spacer()
            }
        )
    }

    private func tip(_ id: String, _ text: String) -> AnyView {
        AnyView(
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .padding(.top, 2)
                Text(.init(text))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }
}
