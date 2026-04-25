import SwiftUI

struct SplashView: View {
    @State private var trimEnd: CGFloat = 0
    @State private var glowOpacity: Double = 0.6
    @State private var logoScale: CGFloat = 0.85
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var rotation: Double = 0

    let statusText: String

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 32) {
                ZStack {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 36))
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .shadow(color: .white.opacity(0.08), radius: 40)

                    glowBorder
                }
                .frame(width: 180, height: 180)

                VStack(spacing: 10) {
                    Text("PICAZHU")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .pink, .purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(textOpacity)

                    Text(statusText.isEmpty ? "Loading library…" : statusText)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                        .opacity(textOpacity)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                logoOpacity = 1
                logoScale = 1
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                textOpacity = 1
            }
            withAnimation(
                .linear(duration: 1.8)
                .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
            ) {
                glowOpacity = 1.0
            }
        }
    }

    private var glowBorder: some View {
        RoundedRectangle(cornerRadius: 38)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        .orange,
                        .pink,
                        .purple,
                        .blue,
                        .cyan,
                        .blue,
                        .purple,
                        .pink,
                        .orange
                    ]),
                    center: .center,
                    angle: .degrees(rotation)
                ),
                lineWidth: 3
            )
            .frame(width: 174, height: 174)
            .opacity(glowOpacity)
            .blur(radius: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 38)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                .orange.opacity(0.6),
                                .pink.opacity(0.6),
                                .purple.opacity(0.6),
                                .blue.opacity(0.6),
                                .cyan.opacity(0.6),
                                .blue.opacity(0.6),
                                .purple.opacity(0.6),
                                .pink.opacity(0.6),
                                .orange.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 6
                    )
                    .frame(width: 174, height: 174)
                    .blur(radius: 8)
                    .opacity(glowOpacity * 0.7)
            )
    }
}

struct SplashTransition: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isLoading ? 0 : 1)
            .animation(.easeInOut(duration: 0.5), value: isLoading)
    }
}
