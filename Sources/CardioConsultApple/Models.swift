import Foundation

struct RGBImage: Hashable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    var isValid: Bool {
        width > 0 && height > 0 && pixels.count == width * height * 3
    }
}

struct LoadedStudyImage: Identifiable, Hashable {
    let id = UUID()
    let fileName: String
    let frameIndex: Int
    let image: RGBImage
    let sourceType: String
    let metadata: [String: String]

    var displayName: String {
        frameIndex > 0 ? "\(fileName)#\(frameIndex)" : fileName
    }
}

struct FrameAnalysis: Identifiable, Hashable {
    let id = UUID()
    let loaded: LoadedStudyImage
    let view: String
    var phase: String
    let chamberAreaProxy: Double
    let hasColorDoppler: Bool
    let bModeFeatures: [Double]
    let flowFeatures: [Double]
}

struct StudyAnalysis: Hashable {
    let frames: [FrameAnalysis]
    let viewCount: Int
    let inputCount: Int
    let systoleCount: Int
    let diastoleCount: Int
    let meanBMode: [Double]
    let meanFlow: [Double]
    let contractilityProxy: Double
    let coverageWarning: String
    let featureSummary: String

    func compactFeatureText() -> String {
        let b = meanBMode.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let f = meanFlow.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        return """
        views=\(viewCount), files_or_frames=\(inputCount), systole=\(systoleCount), diastole=\(diastoleCount), contractility_proxy=\(String(format: "%.4f", contractilityProxy))
        B-mode mean features=[\(b)]
        Doppler mean features=[\(f)]
        """
    }
}

struct TeachingJudgment: Hashable {
    let label: String
    let confidence: String
    let rationale: String
}

struct DiagnosisReport: Identifiable, Hashable {
    let id = UUID()
    let teachingDiagnosis: String
    let confidence: String
    let body: String
    let modelStatus: String
    let featureSummary: String
    let createdAt: Date
}

struct ModelConfig: Codable, Hashable {
    var llamaExecutable: String
    var modelPath: String
    var mmprojPath: String
    var maxTokens: Int
    var temperature: Double

    static let `default` = ModelConfig(
        llamaExecutable: "",
        modelPath: "Models/gemma-4-4b-it-Q4_K_M.gguf",
        mmprojPath: "Models/gemma-4-4b-mmproj-Q4_0.gguf",
        maxTokens: 640,
        temperature: 0.15
    )
}

enum CardioError: LocalizedError {
    case noInput
    case unsupportedFile(String)
    case imageDecodeFailed(String)
    case dicomDecodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInput:
            return "No input files were loaded."
        case .unsupportedFile(let name):
            return "\(name): unsupported file type."
        case .imageDecodeFailed(let name):
            return "\(name): image decode failed."
        case .dicomDecodeFailed(let message):
            return "DICOM decode failed: \(message)"
        }
    }
}

