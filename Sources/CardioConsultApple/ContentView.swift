import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: CardioConsultViewModel
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var showingExporter = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    inputSummary
                    if let study = viewModel.study {
                        StudySummaryView(study: study)
                    }
                    if let report = viewModel.report {
                        ResultView(report: report)
                    } else {
                        emptyResult
                    }
                }
                .padding()
                .frame(maxWidth: 980, alignment: .leading)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.importFiles(urls: urls)
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: ReportDocument(text: viewModel.report?.body ?? ""),
            contentType: .plainText,
            defaultFilename: "cardio_consult_apple_report.txt"
        ) { _ in }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CardioConsult")
                .font(.title2.bold())
            Text("Apple Edition")
                .foregroundStyle(.secondary)

            Button {
                showingImporter = true
            } label: {
                Label("Import PNG / DICOM Batch", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)

            Button {
                viewModel.runDiagnosis()
            } label: {
                Label("Start Diagnosis", systemImage: "waveform.path.ecg")
            }
            .disabled(!viewModel.canAnalyze)

            Button {
                showingSettings = true
            } label: {
                Label("Gemma4 Settings", systemImage: "gearshape")
            }

            Button {
                showingExporter = true
            } label: {
                Label("Export Report", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.report == nil)

            Button(role: .destructive) {
                viewModel.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(viewModel.loadedImages.isEmpty)

            Divider()
            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 260)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("心脏超声教学辅助分析")
                .font(.largeTitle.bold())
            Text("导入脱敏 PNG / DICOM / DCOM 文件，在本机完成 B-mode 差分矩阵、Color Doppler 血流向量、体位与收缩舒张相位聚合，并输出明确到病症名称的教学参考判断。")
                .foregroundStyle(.secondary)
            Text("仅供医学教学参考，不作为临床最终诊断、治疗建议或医嘱。")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    private var inputSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Input")
                .font(.headline)
            if viewModel.loadedImages.isEmpty {
                Text("No files selected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.loadedImages.prefix(20)) { image in
                    HStack {
                        Text(image.displayName)
                        Spacer()
                        Text(image.sourceType)
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
                if viewModel.loadedImages.count > 20 {
                    Text("+ \(viewModel.loadedImages.count - 20) more frames")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyResult: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnosis Output")
                .font(.headline)
            Text(viewModel.isBusy ? "Processing..." : "Import files, then start diagnosis.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var allowedTypes: [UTType] {
        [
            .png,
            .jpeg,
            .tiff,
            UTType(filenameExtension: "bmp"),
            UTType(filenameExtension: "dcm"),
            UTType(filenameExtension: "dicom"),
            UTType(filenameExtension: "dcom"),
            .data
        ].compactMap { $0 }
    }
}

struct StudySummaryView: View {
    let study: StudyAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edge Computing Summary")
                .font(.headline)
            Text(study.featureSummary)
                .font(.body)
            HStack {
                MetricBadge(title: "Views", value: "\(study.viewCount)")
                MetricBadge(title: "Files/Frames", value: "\(study.inputCount)")
                MetricBadge(title: "Diastole", value: "\(study.diastoleCount)")
                MetricBadge(title: "Systole", value: "\(study.systoleCount)")
                MetricBadge(title: "Contractility", value: study.contractilityProxy.f3)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MetricBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ResultView: View {
    let report: DiagnosisReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("教学参考病症判断")
                    .font(.headline)
                Text(report.teachingDiagnosis)
                    .font(.title.bold())
                Text("置信度：\(report.confidence)")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(report.body)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Model mode: \(report.modelStatus)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var viewModel: CardioConsultViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("macOS offline Gemma4 4B") {
                    TextField("llama-cli path", text: $viewModel.config.llamaExecutable)
                    TextField("GGUF model path", text: $viewModel.config.modelPath)
                    TextField("mmproj path", text: $viewModel.config.mmprojPath)
                    Stepper("Max tokens: \(viewModel.config.maxTokens)", value: $viewModel.config.maxTokens, in: 128...4096, step: 64)
                    Slider(value: $viewModel.config.temperature, in: 0.0...1.0)
                    Text("Temperature: \(String(format: "%.2f", viewModel.config.temperature))")
                        .foregroundStyle(.secondary)
                }

                Section("iPhone note") {
                    Text("iPhone builds keep the same model-file contract. Direct GGUF inference on device requires adding a llama.cpp/Metal XCFramework or equivalent native backend to the Xcode target. Without it, the app uses the same local edge-rule fallback.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Gemma4 Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveConfig()
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 380)
        }
    }
}

struct ReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.text = text
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

