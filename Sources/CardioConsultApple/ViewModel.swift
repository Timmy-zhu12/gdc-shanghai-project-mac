import Foundation
import SwiftUI

@MainActor
final class CardioConsultViewModel: ObservableObject {
    @Published var loadedImages: [LoadedStudyImage] = []
    @Published var study: StudyAnalysis?
    @Published var report: DiagnosisReport?
    @Published var config: ModelConfig = ConfigStore.load()
    @Published var isBusy = false
    @Published var statusMessage = "Ready"
    @Published var errorMessage: String?

    var canAnalyze: Bool {
        !loadedImages.isEmpty && !isBusy
    }

    func importFiles(urls: [URL]) {
        isBusy = true
        errorMessage = nil
        statusMessage = "Loading \(urls.count) file(s)"
        Task {
            do {
                let images = try StudyInputLoader.load(urls: urls)
                let analysis = try StudyAnalyzer.analyze(images: images)
                loadedImages = images
                study = analysis
                report = nil
                statusMessage = "Loaded \(images.count) files/frames"
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Import failed"
            }
            isBusy = false
        }
    }

    func runDiagnosis() {
        guard let study else { return }
        isBusy = true
        errorMessage = nil
        statusMessage = "Running edge features and Gemma4 4B interface"
        ConfigStore.save(config)
        Task {
            let diagnosis = await DiagnosisEngine.runDiagnosis(study: study, config: config)
            report = diagnosis
            statusMessage = "Diagnosis complete"
            isBusy = false
        }
    }

    func clear() {
        loadedImages = []
        study = nil
        report = nil
        errorMessage = nil
        statusMessage = "Ready"
    }

    func saveConfig() {
        ConfigStore.save(config)
        statusMessage = "Settings saved"
    }
}

enum ConfigStore {
    private static let key = "CardioConsult.ModelConfig"

    static func load() -> ModelConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ModelConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ config: ModelConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

