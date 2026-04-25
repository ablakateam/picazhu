import SwiftUI
import PicazhuCore
import PicazhuAI
import PicazhuUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var env: AppEnvironment?

    func applicationWillTerminate(_ notification: Notification) {
        guard let env, env.providerKind == "ollama" && env.ollamaConfig.mode == .local,
              let ollama = env.activeProvider as? OllamaVisionProvider else { return }
        PicazhuLog.app.info("Unloading AI model on quit")
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await ollama.unload()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct PicazhuMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var env: AppEnvironment? = {
        do {
            return try AppEnvironment()
        } catch {
            PicazhuLog.app.error("AppEnvironment init failed: \(error.localizedDescription)")
            return nil
        }
    }()
    @State private var model: LibraryViewModel? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if let env {
                    let vm = model ?? LibraryViewModel(env: env)
                    ZStack {
                        RootView(model: vm)
                            .frame(minWidth: 1100, minHeight: 720)
                            .opacity(vm.isBootstrapping ? 0 : 1)

                        if vm.isBootstrapping {
                            SplashView(statusText: vm.bootStatus)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.6), value: vm.isBootstrapping)
                    .onAppear {
                        if model == nil { model = vm }
                        appDelegate.env = env
                    }
                } else {
                    StartupFailureView()
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Folder…") {
                    if let m = model {
                        Task { await m.addWatchedRoot() }
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Analyze Current Folder with AI") {
                    if let m = model { Task { await m.analyzeCurrentFolder() } }
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Find Duplicates…") {
                    if let m = model { Task { await m.scanForDuplicates() } }
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Divider()

                ClearLibraryMenuItem(model: model)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About PICAZHU") {
                    if let m = model { m.showAbout = true }
                }
                Divider()
                DiagnosticsMenuItem(model: model)
            }
            CommandGroup(replacing: .help) {
                Button("PICAZHU Help") {
                    if let m = model { m.showHelp = true }
                }
                .keyboardShortcut("?", modifiers: .command)
            }
            CommandMenu("Go") {
                Button("Quick Look") {
                    if let m = model { Task { await m.quickLookSelection() } }
                }
                .keyboardShortcut(" ", modifiers: [])
                Button("Open") {
                    if let m = model { Task { await m.openSelection() } }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                Button("Reveal in Finder") {
                    if let m = model { Task { await m.revealSelection() } }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Copy Path") {
                    if let m = model { Task { await m.copyPathSelection() } }
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
            }
            CommandGroup(after: .sidebar) {
                Button("Smaller Thumbnails") {
                    if let m = model {
                        m.cellSize = max(DesignTokens.Grid.minCellSize, m.cellSize - 24)
                    }
                }
                .keyboardShortcut("-", modifiers: .command)
                Button("Larger Thumbnails") {
                    if let m = model {
                        m.cellSize = min(DesignTokens.Grid.maxCellSize, m.cellSize + 24)
                    }
                }
                .keyboardShortcut("=", modifiers: .command)
            }
        }

        Window("Diagnostics", id: "diagnostics") {
            if let m = model {
                DiagnosticsView(
                    display: m.diagnosticsDisplay,
                    onRefresh: { Task { await m.refreshDiagnostics() } },
                    onPurgeCache: { Task { await m.purgeThumbnailCache() } },
                    onRebuildCatalog: { Task { await m.rebuildCatalog() } },
                    onClearAllAI: { Task { await m.clearAllAI() } }
                )
                .task { await m.refreshDiagnostics() }
            } else {
                StartupFailureView()
            }
        }
        .windowResizability(.contentSize)
    }
}

struct ClearLibraryMenuItem: View {
    let model: LibraryViewModel?
    @State private var confirming = false

    var body: some View {
        Button("Clear Library…") {
            confirming = true
        }
        .disabled(model == nil || model?.watchedRoots.isEmpty == true)
        .confirmationDialog(
            "Clear the entire PICAZHU library?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Clear Library", role: .destructive) {
                if let m = model { Task { await m.clearLibrary() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All watched folders, the index, and thumbnails will be removed. Files on disk are not touched.")
        }
    }
}

struct DiagnosticsMenuItem: View {
    let model: LibraryViewModel?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Diagnostics…") {
            if let m = model {
                Task { await m.refreshDiagnostics() }
            }
            openWindow(id: "diagnostics")
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
    }
}

struct StartupFailureView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("PICAZHU could not start")
                .font(.title2)
                .fontWeight(.semibold)
            Text("The local catalog could not be opened. See Console.app for details.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
