import SwiftUI
import PicazhuAI
import PicazhuCore

enum AIProviderMode: String, CaseIterable {
    case localOllama = "Local Ollama"
    case cloudOllama = "Ollama Cloud"
    case openai = "OpenAI"
}

struct AISettingsSheet: View {
    @Bindable var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AIProviderMode
    @State private var ollamaHost: String
    @State private var ollamaKey: String
    @State private var ollamaVision: String
    @State private var ollamaEmbed: String
    @State private var openaiKey: String
    @State private var openaiBase: String
    @State private var openaiVision: String
    @State private var openaiEmbed: String
    @State private var temperature: Double
    @State private var availableModels: [String] = []
    @State private var testStatus: TestStatus = .idle
    @State private var testMessage: String = ""
    @State private var isFetchingModels: Bool = false

    enum TestStatus { case idle, testing, success, failed }

    init(model: LibraryViewModel) {
        self.model = model
        let env = model.env
        let ollamaCfg = env.ollamaConfig
        let openaiCfg = env.openaiConfig

        if env.providerKind == "openai" {
            _mode = State(initialValue: .openai)
        } else if ollamaCfg.mode == .cloud {
            _mode = State(initialValue: .cloudOllama)
        } else {
            _mode = State(initialValue: .localOllama)
        }

        _ollamaHost = State(initialValue: ollamaCfg.host)
        _ollamaKey = State(initialValue: ollamaCfg.apiKey)
        _ollamaVision = State(initialValue: ollamaCfg.visionModel)
        _ollamaEmbed = State(initialValue: ollamaCfg.embeddingModel)
        _openaiKey = State(initialValue: openaiCfg.apiKey)
        _openaiBase = State(initialValue: openaiCfg.baseURL)
        _openaiVision = State(initialValue: openaiCfg.visionModel)
        _openaiEmbed = State(initialValue: openaiCfg.embeddingModel)
        _temperature = State(initialValue: env.providerKind == "openai" ? openaiCfg.temperature : ollamaCfg.temperature)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    providerSection
                    connectionSection
                    modelSection
                    temperatureSection
                    statusSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 580)
        .onAppear { fetchModels() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("AI Settings")
                .font(.title2.weight(.semibold))
            Spacer()
            OllamaStatusPill(status: model.ollamaStatus, onRefresh: {
                Task { await model.refreshOllamaStatus() }
            })
        }
        .padding(16)
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROVIDER")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("", selection: $mode) {
                ForEach(AIProviderMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, newValue in
                switch newValue {
                case .localOllama:
                    ollamaHost = "http://localhost:11434"
                    ollamaVision = "qwen3-vl:8b"
                    ollamaEmbed = "nomic-embed-text"
                case .cloudOllama:
                    ollamaHost = "https://ollama.com"
                    ollamaVision = "qwen3-vl:235b-instruct"
                    ollamaEmbed = ""
                case .openai:
                    openaiBase = "https://api.openai.com"
                    openaiVision = "gpt-4o"
                    openaiEmbed = "text-embedding-3-small"
                }
                fetchModels()
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECTION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            switch mode {
            case .localOllama:
                LabeledContent("Host") {
                    TextField("http://localhost:11434", text: $ollamaHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                }
            case .cloudOllama:
                LabeledContent("Host") {
                    TextField("https://ollama.com", text: $ollamaHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                }
                LabeledContent("API Key") {
                    SecureField("Ollama Cloud key", text: $ollamaKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                }
            case .openai:
                LabeledContent("Base URL") {
                    TextField("https://api.openai.com", text: $openaiBase)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                }
                LabeledContent("API Key") {
                    SecureField("sk-...", text: $openaiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                }
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MODELS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isFetchingModels { ProgressView().controlSize(.small) }
                Button("Refresh") { fetchModels() }.controlSize(.small)
            }

            let visionBinding = mode == .openai ? $openaiVision : $ollamaVision
            let embedBinding = mode == .openai ? $openaiEmbed : $ollamaEmbed

            LabeledContent("Vision model") {
                if availableModels.isEmpty {
                    TextField(mode == .openai ? "gpt-4o" : "qwen3-vl:8b", text: visionBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                } else {
                    Picker("", selection: visionBinding) {
                        ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                        if !availableModels.contains(visionBinding.wrappedValue) {
                            Text(visionBinding.wrappedValue).tag(visionBinding.wrappedValue)
                        }
                    }
                    .frame(maxWidth: 340)
                }
            }

            LabeledContent("Embedding model") {
                if availableModels.isEmpty {
                    TextField(mode == .openai ? "text-embedding-3-small" : "nomic-embed-text", text: embedBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                } else {
                    Picker("", selection: embedBinding) {
                        Text("(none)").tag("")
                        ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                        if !embedBinding.wrappedValue.isEmpty && !availableModels.contains(embedBinding.wrappedValue) {
                            Text(embedBinding.wrappedValue).tag(embedBinding.wrappedValue)
                        }
                    }
                    .frame(maxWidth: 340)
                }
            }
        }
    }

    private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GENERATION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LabeledContent("Temperature") {
                HStack {
                    Slider(value: $temperature, in: 0...1, step: 0.05).frame(maxWidth: 200)
                    Text(String(format: "%.2f", temperature)).font(.callout.monospacedDigit()).frame(width: 40)
                }
            }
        }
    }

    private var statusSection: some View {
        HStack(spacing: 12) {
            Button("Test Connection") { testConnection() }
                .buttonStyle(.borderedProminent)
                .disabled(testStatus == .testing)
            if testStatus == .testing { ProgressView().controlSize(.small) }
            switch testStatus {
            case .success:
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Label(testMessage, systemImage: "xmark.circle.fill").foregroundStyle(.red).lineLimit(2).font(.callout)
            default: EmptyView()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button("Save & Apply") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private func fetchModels() {
        isFetchingModels = true
        Task {
            defer { isFetchingModels = false }
            do {
                switch mode {
                case .localOllama, .cloudOllama:
                    let cfg = buildOllamaConfig()
                    let client = OllamaClient(config: cfg)
                    let models = try await client.listModels()
                    availableModels = models.map(\.name).sorted()
                case .openai:
                    let cfg = buildOpenAIConfig()
                    let client = OpenAIClient(config: cfg)
                    availableModels = try await client.listModels()
                }
            } catch {
                availableModels = []
            }
        }
    }

    private func testConnection() {
        testStatus = .testing
        testMessage = ""
        Task {
            do {
                switch mode {
                case .localOllama, .cloudOllama:
                    let provider = OllamaVisionProvider(config: buildOllamaConfig())
                    try await provider.validate()
                case .openai:
                    let provider = OpenAIVisionProvider(config: buildOpenAIConfig())
                    try await provider.validate()
                }
                testStatus = .success
            } catch {
                testStatus = .failed
                testMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        PicazhuLog.ai.info("Saving AI config: mode=\(mode.rawValue, privacy: .public)")
        model.invalidateAICoordinator()
        Task {
            do {
                switch mode {
                case .localOllama, .cloudOllama:
                    try await model.env.updateOllamaConfig(buildOllamaConfig())
                case .openai:
                    try await model.env.updateOpenAIConfig(buildOpenAIConfig())
                }
                await model.refreshOllamaStatus()
                model.debugLog.info("AI config saved: \(mode.rawValue)")
            } catch {
                model.debugLog.error("Save failed: \(error)")
            }
        }
        dismiss()
    }

    private func buildOllamaConfig() -> OllamaProviderConfig {
        OllamaProviderConfig(
            mode: mode == .cloudOllama ? .cloud : .local,
            host: ollamaHost,
            apiKey: ollamaKey,
            visionModel: ollamaVision,
            embeddingModel: ollamaEmbed,
            temperature: temperature,
            maxFramesPerVideo: 5,
            requestTimeoutSeconds: 120
        )
    }

    private func buildOpenAIConfig() -> OpenAIProviderConfig {
        OpenAIProviderConfig(
            apiKey: openaiKey,
            baseURL: openaiBase,
            visionModel: openaiVision,
            embeddingModel: openaiEmbed,
            temperature: temperature,
            maxFramesPerVideo: 5,
            requestTimeoutSeconds: 120
        )
    }
}
