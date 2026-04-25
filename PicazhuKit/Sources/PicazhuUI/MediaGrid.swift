import SwiftUI
import AppKit
import PicazhuCore

// MARK: - AI Visual Effects

struct AIScanningOverlay: View {
    @State private var hScan: CGFloat = -0.15
    @State private var vScan: CGFloat = -0.15
    @State private var gridOpacity: Double = 0
    @State private var nodePhase: Double = 0
    @State private var borderRotation: Double = 0
    @State private var dimmed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(dimmed ? 0.4 : 0)

                glowGrid(in: geo.size)

                horizontalRadar(in: geo.size)
                verticalRadar(in: geo.size)
                crosshairGlow(in: geo.size)

                pulsingBorder
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) {
                dimmed = true
                gridOpacity = 0.5
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                hScan = 1.15
            }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true).delay(0.6)) {
                vScan = 1.15
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                gridOpacity = 0.85
            }
            withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
                nodePhase = 1
            }
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                borderRotation = 360
            }
        }
    }

    private func horizontalRadar(in size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.cyan.opacity(0.08), Color.cyan.opacity(0.25), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: size.height * 0.5)
                .offset(y: (hScan - 0.5) * size.height)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.cyan.opacity(0.4), Color.white.opacity(0.9), Color.cyan.opacity(0.4), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 3)
                .shadow(color: .cyan, radius: 8)
                .shadow(color: .cyan.opacity(0.5), radius: 20)
                .offset(y: (hScan - 0.5) * size.height)
        }
    }

    private func verticalRadar(in size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.purple.opacity(0.06), Color.purple.opacity(0.2), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size.width * 0.5)
                .offset(x: (vScan - 0.5) * size.width)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.purple.opacity(0.4), Color.white.opacity(0.7), Color.purple.opacity(0.4), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 2)
                .shadow(color: .purple, radius: 6)
                .shadow(color: .purple.opacity(0.4), radius: 16)
                .offset(x: (vScan - 0.5) * size.width)
        }
    }

    private func crosshairGlow(in size: CGSize) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.5), Color.cyan.opacity(0.15), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 20
                )
            )
            .frame(width: 40, height: 40)
            .offset(
                x: (vScan - 0.5) * size.width,
                y: (hScan - 0.5) * size.height
            )
            .blur(radius: 2)
    }

    private func glowGrid(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let cols = 12
            let rows = 12
            let cellW = canvasSize.width / CGFloat(cols)
            let cellH = canvasSize.height / CGFloat(rows)

            for row in 0...rows {
                let y = CGFloat(row) * cellH
                let wave = sin(Double(row) * 0.4 + nodePhase * .pi * 2) * 0.3 + 0.4
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(path, with: .color(.cyan.opacity(gridOpacity * 0.15 * wave)), lineWidth: 0.5)
            }
            for col in 0...cols {
                let x = CGFloat(col) * cellW
                let wave = sin(Double(col) * 0.5 + nodePhase * .pi * 2 + 0.8) * 0.3 + 0.4
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                context.stroke(path, with: .color(.cyan.opacity(gridOpacity * 0.15 * wave)), lineWidth: 0.5)
            }

            for row in 0...rows {
                for col in 0...cols {
                    let x = CGFloat(col) * cellW
                    let y = CGFloat(row) * cellH
                    let w1 = sin(Double(row * 3 + col * 2) * 0.5 + nodePhase * .pi * 2) * 0.5 + 0.5
                    let w2 = cos(Double(row + col * 3) * 0.35 + nodePhase * .pi * 2 * 1.4) * 0.5 + 0.5
                    let c = w1 * 0.5 + w2 * 0.5
                    let s = 1.5 + c * 3.5
                    let rect = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
                    context.fill(Path(ellipseIn: rect), with: .color(.cyan.opacity(gridOpacity * c * 0.6)))

                    if c > 0.55, col < cols {
                        let nx = CGFloat(col + 1) * cellW
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: y))
                        line.addLine(to: CGPoint(x: nx, y: y))
                        context.stroke(line, with: .color(.cyan.opacity(gridOpacity * c * 0.12)), lineWidth: 0.5)
                    }
                    if c > 0.55, row < rows {
                        let ny = CGFloat(row + 1) * cellH
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: y))
                        line.addLine(to: CGPoint(x: x, y: ny))
                        context.stroke(line, with: .color(.cyan.opacity(gridOpacity * c * 0.12)), lineWidth: 0.5)
                    }
                    if c > 0.7, col < cols, row < rows {
                        let nx = CGFloat(col + 1) * cellW
                        let ny = CGFloat(row + 1) * cellH
                        var diag = Path()
                        diag.move(to: CGPoint(x: x, y: y))
                        diag.addLine(to: CGPoint(x: nx, y: ny))
                        context.stroke(diag, with: .color(.purple.opacity(gridOpacity * c * 0.08)), lineWidth: 0.5)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var pulsingBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            .strokeBorder(
                AngularGradient(
                    colors: [
                        .cyan.opacity(0.7), .blue.opacity(0.5), .purple.opacity(0.7),
                        .pink.opacity(0.5), .cyan.opacity(0.7)
                    ],
                    center: .center,
                    angle: .degrees(borderRotation)
                ),
                lineWidth: 2
            )
            .shadow(color: .cyan.opacity(0.3), radius: 8)
            .shadow(color: .purple.opacity(0.2), radius: 16)
    }
}

struct AIBadge: View {
    @State private var shimmer: Double = 0

    var body: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                    Text("AI")
                        .font(.system(size: 8, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .purple.opacity(0.5), radius: 4)
                )
                Spacer()
            }
            .padding(6)
        }
    }
}

public struct MediaGridView: View {
    public let items: [MediaItem]
    @Binding public var selection: Set<MediaItemID>
    public let cellSize: CGFloat
    public let currentlyAnalyzingName: String
    public let thumbnailForItem: (MediaItem) -> NSImage?
    public let onOpen: (MediaItem) -> Void

    public init(
        items: [MediaItem],
        selection: Binding<Set<MediaItemID>>,
        cellSize: CGFloat = DesignTokens.Grid.defaultCellSize,
        currentlyAnalyzingName: String = "",
        thumbnailForItem: @escaping (MediaItem) -> NSImage?,
        onOpen: @escaping (MediaItem) -> Void
    ) {
        self.items = items
        self._selection = selection
        self.cellSize = cellSize
        self.currentlyAnalyzingName = currentlyAnalyzingName
        self.thumbnailForItem = thumbnailForItem
        self.onOpen = onOpen
    }

    @FocusState private var gridFocused: Bool

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cellSize), spacing: DesignTokens.Grid.gutter)],
                    spacing: DesignTokens.Grid.gutter
                ) {
                    ForEach(items, id: \.id) { item in
                        MediaCell(
                            item: item,
                            isSelected: selection.contains(item.id),
                            isAnalyzing: !currentlyAnalyzingName.isEmpty && currentlyAnalyzingName.hasPrefix(item.filename),
                            cellSize: cellSize,
                            thumbnail: thumbnailForItem(item)
                        )
                        .id(item.id)
                        .onTapGesture(count: 2) { onOpen(item) }
                        .onTapGesture {
                            gridFocused = true
                            if NSEvent.modifierFlags.contains(.command) {
                                if selection.contains(item.id) {
                                    selection.remove(item.id)
                                } else {
                                    selection.insert(item.id)
                                }
                            } else {
                                selection = [item.id]
                            }
                        }
                    }
                }
                .padding(DesignTokens.Spacing.lg)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .focusable()
            .focused($gridFocused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { moveSelection(by: -1, proxy: proxy); return .handled }
            .onKeyPress(.rightArrow) { moveSelection(by: 1, proxy: proxy); return .handled }
            .onKeyPress(.upArrow) { moveSelection(by: -columnsCount, proxy: proxy); return .handled }
            .onKeyPress(.downArrow) { moveSelection(by: columnsCount, proxy: proxy); return .handled }
            .onKeyPress(.return) {
                if let id = selection.first, let item = items.first(where: { $0.id == id }) {
                    onOpen(item)
                }
                return .handled
            }
        }
    }

    private var columnsCount: Int {
        max(1, Int((NSScreen.main?.frame.width ?? 1200) / (cellSize + DesignTokens.Grid.gutter)))
    }

    private func moveSelection(by offset: Int, proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let currentIndex: Int
        if let sel = selection.first, let idx = items.firstIndex(where: { $0.id == sel }) {
            currentIndex = idx
        } else {
            currentIndex = -1
        }
        let newIndex = max(0, min(items.count - 1, currentIndex + offset))
        let newID = items[newIndex].id
        selection = [newID]
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(newID, anchor: .center)
        }
    }
}

struct AIPendingPulse: View {
    @State private var pulse: Double = 0.3

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.cyan.opacity(pulse * 0.5), lineWidth: 1)
            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.cyan)
                        Text("Queued")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.cyan.opacity(0.8))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    Spacer()
                }
                .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = 0.8
            }
        }
    }
}

struct MediaCell: View {
    let item: MediaItem
    let isSelected: Bool
    let isAnalyzing: Bool
    let cellSize: CGFloat
    let thumbnail: NSImage?

    private var isPending: Bool {
        item.aiState == .pending && !isAnalyzing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(DesignTokens.Palette.card)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cellSize, height: cellSize)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                        .saturation(isPending ? 0.5 : 1.0)
                        .brightness(isAnalyzing ? -0.1 : 0)
                } else {
                    Image(systemName: item.kind == .video ? "film" : "photo")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                }
                if isAnalyzing {
                    AIScanningOverlay()
                        .transition(.opacity.animation(.easeInOut(duration: 0.6)))
                } else if isPending {
                    AIPendingPulse()
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
                if item.aiState == .ready {
                    AIBadge()
                        .transition(.scale.combined(with: .opacity).animation(.spring(duration: 0.4, bounce: 0.3)))
                }
                if item.kind == .video, let duration = item.duration {
                    durationBadge(duration)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(
                        isSelected ? DesignTokens.Palette.selectionBorder
                        : item.aiState == .ready ? Color.purple.opacity(0.3)
                        : Color.clear,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(isSelected ? DesignTokens.Palette.selection : Color.clear)
            )

            Text(item.filename)
                .font(DesignTokens.Typography.itemCaption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
                .frame(width: cellSize, alignment: .leading)
        }
    }

    private func durationBadge(_ seconds: Double) -> some View {
        let text: String = {
            let total = Int(seconds)
            let m = total / 60
            let s = total % 60
            return String(format: "%d:%02d", m, s)
        }()
        return VStack {
            Spacer()
            HStack {
                Spacer()
                Text(text)
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.65))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(6)
            }
        }
    }
}
