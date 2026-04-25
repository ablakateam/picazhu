import SwiftUI
import PicazhuUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 30)

            // Logo
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.purple.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.3), radius: 12)
            }

            Text("PICAZHU")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .pink, .purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.top, 4)

            Text("Version 0.1")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text("The intelligent media browser for macOS")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Divider()
                .padding(.vertical, 16)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 10) {
                featureRow("photo.on.rectangle.angled", "Browse photos & videos from real folders")
                featureRow("sparkles", "AI-powered captioning, tagging & OCR")
                featureRow("magnifyingglass", "Search by content, objects, scenes & text")
                featureRow("lock.shield", "Fully local — your files never leave your Mac")
            }
            .padding(.horizontal, 30)

            Divider()
                .padding(.vertical, 16)
                .padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("Built by EBOXLAB LLC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Powered by Ollama + Apple Vision")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: 24)
        }
        .frame(width: 380, height: 480)
        .background(.ultraThinMaterial)
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.purple)
                .frame(width: 24)
            Text(text)
                .font(.callout)
        }
    }
}
