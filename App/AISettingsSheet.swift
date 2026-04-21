import SwiftUI
import PicazhuAI
import PicazhuCore

struct AISettingsSheet: View {
    @Bindable var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: OllamaMode
    @State private var host: String
    @State private var apiKey: String
    @State private var visionModel: String
    @State private var embeddingModel: String
    @State private var temperature: Double
    @State private var availableModels: [String] = []
    @State private var testStatus: TestStatus = .idle
    @State private var testMessage: String = ""
    @State private var isFetchingModels: Bool = false

    enum TestStatus { case idle, testing, success, failed }

    init(model: LibraryViewModel) {
        self.model = model
        let cfg = model.env.aiConfig
        _mode = State(initialValue: cfg.mode)
        _host = State(initialValue: cfg.host)
        _apiKey = State(initialValue: cfg.apiKey)
        _visionModel = State(initialValue: cfg.visionModel)
        _embeddingModel = State(initialValue: cfg.embeddingModel)
        _temperature = State(initialValue: cfg.temperature)
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
        .frame(width: 520, height: 560)
        .onAppear { fetchModels() }
    }

    // MARK: - Sections

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
                ForEach(OllamaMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, newValue in
                switch newValue {
                case .local:
                    host = "http://localhost:11434"
                    visionModel = "qwen3-vl:8b"
                    embeddingModel = "nomic-embed-text"
                case .cloud:
                    host = "https://ollama.com"
                    visionModel = "qwen3-vl:235b-instruct"
                    embeddingModel = ""
                }
                fetchModels()
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECTION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LabeledContent("Host URL") {
                TextField("http://localhost:11434", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }
            if mode == .cloud {
                LabeledContent("API Key") {
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
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
                if isFetchingModels {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh") { fetchModels() }
                    .controlSize(.small)
            }

            LabeledContent("Vision model") {
                if availableModels.isEmpty {
                    TextField("qwen2.5vl:7b", text: $visionModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                } else {
                    Picker("", selection: $visionModel) {
                        ForEach(availableModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        if !availableModels.contains(visionModel) {
                            Text(visionModel).tag(visionModel)
                        }
                    }
                    .frame(maxWidth: 320)
                }
            }

            LabeledContent("Embedding model") {
                if availableModels.isEmpty {
                    TextField("nomic-embed-text", text: $embeddingModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                } else {
                    Picker("", selection: $embeddingModel) {
                        ForEach(availableModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        if !availableModels.contains(embeddingModel) {
                            Text(embeddingModel).tag(embeddingModel)
                        }
                    }
                    .frame(maxWidth: 320)
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
                    Slider(value: $temperature, in: 0...1, step: 0.05)
                        .frame(maxWidth: 200)
                    Text(String(format: "%.2f", temperature))
                        .font(.callout.monospacedDigit())
                        .frame(width: 40)
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button("Test Connection") { testConnection() }
                    .buttonStyle(.borderedProminent)
                    .disabled(testStatus == .testing)
                if testStatus == .testing {
                    ProgressView().controlSize(.small)
                }
                switch testStatus {
                case .success:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Label(testMessage, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .font(.callout)
                default:
                    EmptyView()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Save & Apply") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func fetchModels() {
        isFetchingModels = true
        let cfg = buildConfig()
        let client = OllamaClient(config: cfg)
        Task {
            defer { isFetchingModels = false }
            do {
                let models = try await client.listModels()
                availableModels = models.map(\.name).sorted()
            } catch {
                availableModels = []
            }
        }
    }

    private func testConnection() {
        testStatus = .testing
        testMessage = ""
        let cfg = buildConfig()
        let provider = OllamaVisionProvider(config: cfg)
        Task {
            do {
                try await provider.validate()
                testStatus = .success
                testMessage = "All good"
            } catch {
                testStatus = .failed
                testMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        let cfg = buildConfig()
        let keyLen = cfg.apiKey.count
        PicazhuLog.ai.info("Saving AI config: mode=\(cfg.mode.rawValue, privacy: .public) host=\(cfg.host, privacy: .public) vision=\(cfg.visionModel, privacy: .public) keyLen=\(keyLen) embed=\(cfg.embeddingModel, privacy: .public)")
        model.applyAIConfig(cfg)
        dismiss()
    }

    private func buildConfig() -> OllamaProviderConfig {
        OllamaProviderConfig(
            mode: mode,
            host: host,
            apiKey: apiKey,
            visionModel: visionModel,
            embeddingModel: embeddingModel,
            temperature: temperature,
            maxFramesPerVideo: 5,
            requestTimeoutSeconds: 120
        )
    }
}
