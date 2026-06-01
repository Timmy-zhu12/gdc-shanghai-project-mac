import Foundation

struct LowEFCalibrationEstimate: Hashable {
    let probability: Double
    let threshold: Double
    let positive: Bool

    var compactText: String {
        "CAMUS low-EF B-mode calibration p=\(probability.f3), threshold=\(threshold.f3)"
    }
}

enum LowEFCalibration {
    private static let means = [
        0.3439935179, 0.1202890558, 0.0257984379, 0.0245626505,
        0.0402119582, 0.0737082141, 0.7069971181, 0.4954215066,
        0.1480851636, 0.0763964283, 0.0746771633, 1.3412349234,
        0.0336320823, 0.7312120198
    ]
    private static let scales = [
        0.0320823992, 0.0130243928, 0.0025158036, 0.0021835693,
        0.0035243618, 0.0154935366, 0.0205262283, 0.0097401574,
        0.0088450145, 0.0618941601, 0.0176097238, 0.1334816438,
        0.0174574480, 0.0417555305
    ]
    private static let coeffs = [
        0.6227405327, -0.0138485092, 0.2119849661, -0.2368895083,
        0.1975460847, 0.0613060324, 0.7014784635, 1.4841314955,
        0.2065621561, 0.2448794316, 0.7444971896, 0.4895215522,
        -0.5426316802, 1.0054161135
    ]
    private static let intercept = 0.3068175790
    private static let threshold = 0.270

    static func estimate(study: StudyAnalysis) -> LowEFCalibrationEstimate {
        var score = intercept
        for index in coeffs.indices {
            let value = study.meanBMode[safe: index, fallback: means[index]]
            score += ((value - means[index]) / max(scales[index], 0.000001)) * coeffs[index]
        }
        let probability = sigmoid(score).clamped01
        return LowEFCalibrationEstimate(
            probability: probability,
            threshold: threshold,
            positive: probability >= threshold
        )
    }

    private static func sigmoid(_ score: Double) -> Double {
        if score >= 0 {
            return 1.0 / (1.0 + exp(-score))
        }
        let z = exp(score)
        return z / (1.0 + z)
    }
}
