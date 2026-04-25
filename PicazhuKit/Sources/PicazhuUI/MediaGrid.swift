import SwiftUI
import AppKit
import PicazhuCore

// MARK: - AI Visual Effects

struct AIScanningOverlay: View {
    @State private var hScan: CGFloat = -0.2
    @State private var vScan: CGFloat = -0.2
    @State private var dotPhase: Double = 0
    @State private var pulsePhase: Double = 0
    @State private var borderRotation: Double = 0
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(appeared ? 0.45 : 0)

                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        drawGrid(context: context, size: size, time: t)
                    }
                }
                .allowsHitTesting(false)

                hBeam(in: geo.size)
                vBeam(in: geo.size)
                crosshair(in: geo.size)

                pulsingBorder
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { hScan = 1.2 }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(0.4)) { vScan = 1.2 }
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) { borderRotation = 360 }
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, time: Double) {
        let cols = 14
        let rows = 14
        let cw = size.width / CGFloat(cols)
        let ch = size.height / CGFloat(rows)

        for row in 0...rows {
            for col in 0...cols {
                let x = CGFloat(col) * cw
                let y = CGFloat(row) * ch

                let wave1 = sin(Double(row) * 0.7 + Double(col) * 0.5 + time * 2.5) * 0.5 + 0.5
                let wave2 = cos(Double(row) * 0.4 - Double(col) * 0.8 + time * 1.8) * 0.5 + 0.5
                let intensity = wave1 * 0.6 + wave2 * 0.4

                let dotSize = 1.5 + intensity * 5.0
                let dotAlpha = intensity * intensity * 0.9

                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(.cyan.opacity(dotAlpha)))

                if intensity > 0.5, col < cols {
                    let nx = CGFloat(col + 1) * cw
                    let ny = y
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: y))
                    line.addLine(to: CGPoint(x: nx, y: ny))
                    context.stroke(line, with: .color(.cyan.opacity(intensity * 0.2)), lineWidth: 0.5)
                }
                if intensity > 0.5, row < rows {
                    let ny = CGFloat(row + 1) * ch
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: y))
                    line.addLine(to: CGPoint(x: x, y: ny))
                    context.stroke(line, with: .color(.cyan.opacity(intensity * 0.2)), lineWidth: 0.5)
                }
                if intensity > 0.65, col < cols, row < rows {
                    let nx = CGFloat(col + 1) * cw
                    let ny = CGFloat(row + 1) * ch
                    var diag = Path()
                    diag.move(to: CGPoint(x: x, y: y))
                    diag.addLine(to: CGPoint(x: nx, y: ny))
                    context.stroke(diag, with: .color(.purple.opacity(intensity * 0.12)), lineWidth: 0.5)
                }
            }
        }
    }

    private func hBeam(in size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .cyan.opacity(0.12), .cyan.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                .frame(height: size.height * 0.4)
                .offset(y: (hScan - 0.5) * size.height)

            Rectangle()
                .fill(LinearGradient(colors: [.clear, .cyan.opacity(0.5), .white.opacity(0.95), .cyan.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                .frame(height: 3)
                .shadow(color: .cyan, radius: 12)
                .shadow(color: .cyan.opacity(0.6), radius: 25)
                .offset(y: (hScan - 0.5) * size.height)
        }
    }

    private func vBeam(in size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .purple.opacity(0.08), .purple.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: size.width * 0.4)
                .offset(x: (vScan - 0.5) * size.width)

            Rectangle()
                .fill(LinearGradient(colors: [.clear, .purple.opacity(0.5), .white.opacity(0.8), .purple.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 2.5)
                .shadow(color: .purple, radius: 10)
                .shadow(color: .purple.opacity(0.5), radius: 20)
                .offset(x: (vScan - 0.5) * size.width)
        }
    }

    private func crosshair(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.7), .cyan.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: 25))
                .frame(width: 50, height: 50)
            Circle()
                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                .frame(width: 20, height: 20)
        }
        .offset(x: (vScan - 0.5) * size.width, y: (hScan - 0.5) * size.height)
        .blur(radius: 1)
    }

    private var pulsingBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            .strokeBorder(
                AngularGradient(
                    colors: [.cyan, .blue, .purple, .pink, .orange, .cyan],
                    center: .center,
                    angle: .degrees(borderRotation)
                ),
                lineWidth: 2.5
            )
            .shadow(color: .cyan.opacity(0.4), radius: 10)
            .shadow(color: .purple.opacity(0.3), radius: 20)
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
    public let favorites: Set<MediaItemID>
    public let thumbnailForItem: (MediaItem) -> NSImage?
    public let onOpen: (MediaItem) -> Void
    public let onToggleFavorite: (MediaItemID) -> Void

    public init(
        items: [MediaItem],
        selection: Binding<Set<MediaItemID>>,
        cellSize: CGFloat = DesignTokens.Grid.defaultCellSize,
        currentlyAnalyzingName: String = "",
        favorites: Set<MediaItemID> = [],
        thumbnailForItem: @escaping (MediaItem) -> NSImage?,
        onOpen: @escaping (MediaItem) -> Void,
        onToggleFavorite: @escaping (MediaItemID) -> Void = { _ in }
    ) {
        self.items = items
        self._selection = selection
        self.cellSize = cellSize
        self.currentlyAnalyzingName = currentlyAnalyzingName
        self.favorites = favorites
        self.thumbnailForItem = thumbnailForItem
        self.onOpen = onOpen
        self.onToggleFavorite = onToggleFavorite
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
                            isFavorite: favorites.contains(item.id),
                            cellSize: cellSize,
                            thumbnail: thumbnailForItem(item),
                            onToggleFavorite: { onToggleFavorite(item.id) }
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
    let isFavorite: Bool
    let cellSize: CGFloat
    let thumbnail: NSImage?
    var onToggleFavorite: () -> Void = {}

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
                if isFavorite {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.yellow)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                                .padding(6)
                        }
                        Spacer()
                    }
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
