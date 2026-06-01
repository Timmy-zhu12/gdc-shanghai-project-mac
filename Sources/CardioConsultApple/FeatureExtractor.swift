import Foundation

enum StudyAnalyzer {
    private static let analysisSize = 256

    private static let standardViews: [(String, [String])] = [
        ("PLAX", ["plax", "parasternal_long", "long_axis", "左室长轴", "胸骨旁长轴"]),
        ("PSAX-AV", ["psax_av", "aortic_valve", "short_axis_av", "主动脉瓣短轴"]),
        ("PSAX-MV", ["psax_mv", "mitral", "二尖瓣短轴"]),
        ("PSAX-PM", ["psax_pm", "papillary", "乳头肌短轴"]),
        ("PSAX-APEX", ["psax_apex", "apex_short", "心尖短轴"]),
        ("A4C", ["a4c", "apical_4", "four_chamber", "4ch", "4_chamber", "心尖四腔"]),
        ("A5C", ["a5c", "apical_5", "five_chamber", "心尖五腔"]),
        ("A2C", ["a2c", "apical_2", "two_chamber", "2ch", "2_chamber", "心尖二腔"]),
        ("A3C", ["a3c", "apical_3", "three_chamber", "心尖三腔"]),
        ("SUBCOSTAL-4C", ["subcostal", "subxiphoid", "剑突下", "肋下"]),
        ("IVC", ["ivc", "下腔静脉"]),
        ("SUPRASTERNAL", ["suprasternal", "arch", "胸骨上窝", "主动脉弓"])
    ]

    static func analyze(images: [LoadedStudyImage]) throws -> StudyAnalysis {
        guard !images.isEmpty else { throw CardioError.noInput }

        var provisional: [FrameAnalysis] = images.map { image in
            let resized = image.image.resized(to: analysisSize)
            let gray = resized.grayMatrix()
            let bMode = bModeFeatures(gray)
            let flow = flowFeatures(resized)
            return FrameAnalysis(
                loaded: image,
                view: detectView(image.fileName),
                phase: phaseFromName(image.fileName),
                chamberAreaProxy: chamberAreaProxy(gray),
                hasColorDoppler: flow[safe: 4, fallback: 0] > 0.015,
                bModeFeatures: bMode,
                flowFeatures: flow
            )
        }

        assignPhases(&provisional)
        let views = Set(provisional.map(\.view))
        let systole = provisional.filter { $0.phase == "systole" }.count
        let diastole = provisional.filter { $0.phase == "diastole" }.count
        let meanB = meanFeatures(provisional.map(\.bModeFeatures), count: 14)
        let meanF = meanFeatures(provisional.map(\.flowFeatures), count: 10)
        let contractility = computeContractilityProxy(provisional)
        let contractilityFraction = computeContractilityFractionProxy(provisional)
        let warning: String
        if views.count > 12 {
            warning = "输入超过 12 个体位标签，已按全部文件聚合；建议按标准 12 体位整理。"
        } else if views.count < 2 {
            warning = "体位覆盖较少，输出只能作为极低置信度的疑似描述。"
        } else {
            warning = ""
        }
        let summary = buildFeatureSummary(frames: provisional, meanB: meanB, meanF: meanF, contractility: contractility, contractilityFraction: contractilityFraction, warning: warning)

        return StudyAnalysis(
            frames: provisional,
            viewCount: views.count,
            inputCount: images.count,
            systoleCount: systole,
            diastoleCount: diastole,
            meanBMode: meanB,
            meanFlow: meanF,
            contractilityProxy: contractility,
            contractilityFractionProxy: contractilityFraction,
            coverageWarning: warning,
            featureSummary: summary
        )
    }

    private static func bModeFeatures(_ gray: [Double]) -> [Double] {
        let normalized = robustNormalize(gray)
        let dog = differenceOfGaussians(normalized, sigmaSmall: 1.0, sigmaLarge: 2.0)
        let mean = normalized.average
        var variance = 0.0
        var dxMean = 0.0
        var dyMean = 0.0
        var gradMean = 0.0
        var edgePixels = 0
        var count = 0
        var histogram = [Int](repeating: 0, count: 32)

        for y in 0..<(analysisSize - 1) {
            for x in 0..<(analysisSize - 1) {
                let index = y * analysisSize + x
                let value = normalized[index]
                let dx = normalized[index + 1] - value
                let dy = normalized[index + analysisSize] - value
                let grad = sqrt(dx * dx + dy * dy)
                variance += (value - mean) * (value - mean)
                dxMean += abs(dx)
                dyMean += abs(dy)
                gradMean += grad
                if grad > 0.12 {
                    edgePixels += 1
                }
                let bin = min(max(Int((value * 31).rounded()), 0), 31)
                histogram[bin] += 1
                count += 1
            }
        }

        let denom = max(Double(count), 1)
        let varianceFeature = (variance / denom).clamped01
        let dxFeature = (dxMean / denom).clamped01
        let dyFeature = (dyMean / denom).clamped01
        let gradFeature = (gradMean / denom).clamped01
        let edgeFeature = (Double(edgePixels) / denom).clamped01
        let dogMean = dog.average.clamped01
        var speckleResidual = 0.0
        var dogVariance = 0.0
        var leftSum = 0.0
        var rightSum = 0.0
        var leftCount = 0
        var rightCount = 0
        for y in 0..<analysisSize {
            for x in 0..<analysisSize {
                let index = y * analysisSize + x
                let value = normalized[index]
                speckleResidual += abs(value - dog[index])
                let dogDiff = dog[index] - dogMean
                dogVariance += dogDiff * dogDiff
                if x < analysisSize / 2 {
                    leftSum += value
                    leftCount += 1
                } else {
                    rightSum += value
                    rightCount += 1
                }
            }
        }
        let pixelDenom = max(Double(normalized.count), 1.0)
        speckleResidual = (speckleResidual / pixelDenom).clamped01
        dogVariance /= pixelDenom
        let contrastGain = min(max(dogVariance / max(varianceFeature, 0.000001), 0.0), 3.0)
        let directionalAnisotropy = min(max(abs(dxFeature - dyFeature) / max(dxFeature + dyFeature, 0.001), 0.0), 1.0)
        let leftMean = leftSum / max(Double(leftCount), 1.0)
        let rightMean = rightSum / max(Double(rightCount), 1.0)
        let symmetryProxy = (1.0 - abs(leftMean - rightMean)).clamped01
        return [
            mean.clamped01,
            varianceFeature,
            dxFeature,
            dyFeature,
            gradFeature,
            edgeFeature,
            normalizedEntropy(histogram),
            dogMean,
            (Double(dog.filter { $0 > 0.65 }.count) / Double(max(dog.count, 1))).clamped01,
            chamberAreaProxy(normalized),
            speckleResidual,
            contrastGain,
            directionalAnisotropy,
            symmetryProxy
        ]
    }

    private static func flowFeatures(_ image: RGBImage) -> [Double] {
        var towards = 0.0
        var away = 0.0
        var speedSum = 0.0
        var signedSum = 0.0
        var active = 0
        let count = image.width * image.height
        var vx = [Double](repeating: 0, count: count)
        var vy = [Double](repeating: 0, count: count)
        var speed = [Double](repeating: 0, count: count)

        for index in 0..<count {
            let offset = index * 3
            let hsv = rgbToHSV(
                r: Double(image.pixels[offset]) / 255.0,
                g: Double(image.pixels[offset + 1]) / 255.0,
                b: Double(image.pixels[offset + 2]) / 255.0
            )
            let currentSpeed = hsv.saturation * hsv.value
            if currentSpeed > 0.12 {
                let theta = hueToTheta(hsv.hue)
                let x = currentSpeed * cos(theta)
                let y = currentSpeed * sin(theta)
                vx[index] = x
                vy[index] = y
                speed[index] = currentSpeed
                speedSum += currentSpeed
                signedSum += x
                active += 1
                if x >= 0 {
                    towards += 1
                } else {
                    away += 1
                }
            }
        }

        let activeDenom = max(Double(active), 1)
        let meanSpeed = speedSum / activeDenom
        let meanSigned = signedSum / activeDenom
        let activeRatio = Double(active) / Double(max(count, 1))
        var turbulence = 0.0
        if active > 0 {
            for value in speed where value > 0 {
                turbulence += (value - meanSpeed) * (value - meanSpeed)
            }
            turbulence /= activeDenom
        }

        var gradientEnergy = 0.0
        var divergence = 0.0
        var vorticity = 0.0
        var gradientCount = 0
        for y in 1..<(image.height - 1) {
            for x in 1..<(image.width - 1) {
                let index = y * image.width + x
                let dvxDx = (vx[index + 1] - vx[index - 1]) * 0.5
                let dvyDy = (vy[index + image.width] - vy[index - image.width]) * 0.5
                let dvyDx = (vy[index + 1] - vy[index - 1]) * 0.5
                let dvxDy = (vx[index + image.width] - vx[index - image.width]) * 0.5
                gradientEnergy += sqrt(dvxDx * dvxDx + dvyDy * dvyDy + dvyDx * dvyDx + dvxDy * dvxDy)
                divergence += abs(dvxDx + dvyDy)
                vorticity += abs(dvyDx - dvxDy)
                gradientCount += 1
            }
        }
        let gradientDenom = max(Double(gradientCount), 1)

        return [
            (towards / activeDenom).clamped01,
            (away / activeDenom).clamped01,
            meanSpeed.clamped01,
            ((meanSigned + 1.0) * 0.5).clamped01,
            activeRatio.clamped01,
            turbulence.clamped01,
            (gradientEnergy / gradientDenom).clamped01,
            (divergence / gradientDenom).clamped01,
            (vorticity / gradientDenom).clamped01,
            meanSpeed.clamped01
        ]
    }

    private static func robustNormalize(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return values }
        let sorted = values.sorted()
        let p2 = sorted[min(max(Int(Double(sorted.count - 1) * 0.02), 0), sorted.count - 1)]
        let p98 = sorted[min(max(Int(Double(sorted.count - 1) * 0.98), 0), sorted.count - 1)]
        let denom = max(p98 - p2, 0.001)
        return values.map { (($0 - p2) / denom).clamped01 }
    }

    private static func differenceOfGaussians(_ values: [Double], sigmaSmall: Double, sigmaLarge: Double) -> [Double] {
        let small = gaussianBlur(values, width: analysisSize, height: analysisSize, sigma: sigmaSmall)
        let large = gaussianBlur(values, width: analysisSize, height: analysisSize, sigma: sigmaLarge)
        return robustNormalize(zip(small, large).map { $0 - $1 })
    }

    private static func gaussianBlur(_ input: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
        let radius = max(Int((sigma * 3.0).rounded()), 1)
        var kernel = [Double](repeating: 0, count: radius * 2 + 1)
        var sum = 0.0
        for i in -radius...radius {
            let value = exp(-Double(i * i) / (2.0 * sigma * sigma))
            kernel[i + radius] = value
            sum += value
        }
        kernel = kernel.map { $0 / max(sum, 0.001) }

        var temp = [Double](repeating: 0, count: input.count)
        var output = [Double](repeating: 0, count: input.count)
        for y in 0..<height {
            for x in 0..<width {
                var acc = 0.0
                for k in -radius...radius {
                    let xx = min(max(x + k, 0), width - 1)
                    acc += input[y * width + xx] * kernel[k + radius]
                }
                temp[y * width + x] = acc
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var acc = 0.0
                for k in -radius...radius {
                    let yy = min(max(y + k, 0), height - 1)
                    acc += temp[yy * width + x] * kernel[k + radius]
                }
                output[y * width + x] = acc
            }
        }
        return output
    }

    private static func chamberAreaProxy(_ gray: [Double]) -> Double {
        let x0 = Int(Double(analysisSize) * 0.12)
        let x1 = Int(Double(analysisSize) * 0.88)
        let y0 = Int(Double(analysisSize) * 0.18)
        let y1 = Int(Double(analysisSize) * 0.86)
        let cropWidth = max(x1 - x0, 1)
        let cropHeight = max(y1 - y0, 1)
        var crop: [Double] = []
        crop.reserveCapacity(cropWidth * cropHeight)
        for y in y0..<y1 {
            for x in x0..<x1 {
                crop.append(gray[y * analysisSize + x])
            }
        }

        let threshold = otsuThreshold(crop)
        let cx = Double(cropWidth - 1) / 2.0
        let cy = Double(cropHeight - 1) / 2.0
        var darkWeighted = 0.0
        var weightSum = 0.0
        for y in 0..<cropHeight {
            for x in 0..<cropWidth {
                let radius = sqrt(
                    pow((Double(y) - cy) / Double(max(cropHeight, 1)), 2) +
                    pow((Double(x) - cx) / Double(max(cropWidth, 1)), 2)
                )
                let weight = max(0.15, min(1.0, 1.0 - radius * 2.2))
                if crop[y * cropWidth + x] < threshold {
                    darkWeighted += weight
                }
                weightSum += weight
            }
        }
        return (darkWeighted / max(weightSum, 0.001)).clamped01
    }

    private static func otsuThreshold(_ values: [Double]) -> Double {
        let bins = 96
        var histogram = [Int](repeating: 0, count: bins)
        for value in values {
            let index = min(max(Int((value.clamped01 * Double(bins - 1)).rounded()), 0), bins - 1)
            histogram[index] += 1
        }
        let total = max(histogram.reduce(0, +), 1)
        var sumTotal = 0.0
        for i in 0..<bins {
            sumTotal += Double(histogram[i]) * (Double(i) / Double(bins - 1))
        }

        var weightBg = 0.0
        var sumBg = 0.0
        var bestVariance = -1.0
        var best = 0.25
        for i in 0..<bins {
            let count = Double(histogram[i])
            weightBg += count
            if weightBg <= 0 { continue }
            let weightFg = Double(total) - weightBg
            if weightFg <= 0 { break }
            let center = Double(i) / Double(bins - 1)
            sumBg += count * center
            let meanBg = sumBg / weightBg
            let meanFg = (sumTotal - sumBg) / weightFg
            let between = weightBg * weightFg * pow(meanBg - meanFg, 2)
            if between > bestVariance {
                bestVariance = between
                best = center
            }
        }
        return min(max(best, 0.08), 0.55)
    }

    private static func normalizedEntropy(_ histogram: [Int]) -> Double {
        let total = max(Double(histogram.reduce(0, +)), 1.0)
        var entropy = 0.0
        for bin in histogram where bin > 0 {
            let p = Double(bin) / total
            entropy -= p * log2(p)
        }
        return (entropy / 5.0).clamped01
    }

    private static func rgbToHSV(r: Double, g: Double, b: Double) -> (hue: Double, saturation: Double, value: Double) {
        let maxc = max(r, max(g, b))
        let minc = min(r, min(g, b))
        let delta = maxc - minc
        var hue = 0.0
        if delta > 0.000001 {
            if maxc == r {
                hue = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6.0))
            } else if maxc == g {
                hue = 60.0 * (((b - r) / delta) + 2.0)
            } else {
                hue = 60.0 * (((r - g) / delta) + 4.0)
            }
            if hue < 0 { hue += 360.0 }
        }
        let saturation = maxc <= 0.000001 ? 0.0 : delta / maxc
        return (hue, saturation, maxc)
    }

    private static func hueToTheta(_ hue: Double) -> Double {
        if hue <= 240.0 {
            return (hue / 240.0) * Double.pi
        }
        if hue >= 330.0 {
            return 0.0
        }
        return Double.pi + ((hue - 240.0) / 90.0) * Double.pi
    }

    private static func detectView(_ fileName: String) -> String {
        let lower = fileName.lowercased()
        for (view, keys) in standardViews {
            if keys.contains(where: { lower.contains($0.lowercased()) }) {
                return view
            }
        }
        return "UNKNOWN"
    }

    private static func phaseFromName(_ fileName: String) -> String {
        let lower = fileName.lowercased()
        let systoleKeys = ["systole", "systolic", "_es", "-es", "endsystole", "end_systole", "收缩"]
        let diastoleKeys = ["diastole", "diastolic", "_ed", "-ed", "enddiastole", "end_diastole", "舒张"]
        if systoleKeys.contains(where: { lower.contains($0) }) {
            return "systole"
        }
        if diastoleKeys.contains(where: { lower.contains($0) }) {
            return "diastole"
        }
        return "unknown"
    }

    private static func assignPhases(_ frames: inout [FrameAnalysis]) {
        let groups = Dictionary(grouping: frames.indices, by: { frames[$0].view })
        for indices in groups.values {
            let unknown = indices.filter { frames[$0].phase == "unknown" }
            if indices.count >= 2 && !unknown.isEmpty {
                let ordered = indices.sorted { frames[$0].chamberAreaProxy < frames[$1].chamberAreaProxy }
                frames[ordered.first!].phase = "systole"
                frames[ordered.last!].phase = "diastole"
                for index in ordered.dropFirst().dropLast() where frames[index].phase == "unknown" {
                    frames[index].phase = "intermediate"
                }
            } else if indices.count == 1, let index = indices.first, frames[index].phase == "unknown" {
                frames[index].phase = "unknown_single_frame"
            }
        }
    }

    private static func computeContractilityProxy(_ frames: [FrameAnalysis]) -> Double {
        let groups = Dictionary(grouping: frames, by: \.view)
        let deltas: [Double] = groups.values.compactMap { group in
            let systolic = group.filter { $0.phase == "systole" }.map(\.chamberAreaProxy)
            let diastolic = group.filter { $0.phase == "diastole" }.map(\.chamberAreaProxy)
            guard let maxD = diastolic.max(), let minS = systolic.min() else {
                return nil
            }
            return max(maxD - minS, 0)
        }
        return deltas.isEmpty ? 0 : deltas.average.clamped01
    }

    private static func computeContractilityFractionProxy(_ frames: [FrameAnalysis]) -> Double {
        let groups = Dictionary(grouping: frames, by: \.view)
        let fractions: [Double] = groups.values.compactMap { group in
            let systolic = group.filter { $0.phase == "systole" }.map(\.chamberAreaProxy)
            let diastolic = group.filter { $0.phase == "diastole" }.map(\.chamberAreaProxy)
            guard let maxD = diastolic.max(), let minS = systolic.min(), maxD > 0.001 else {
                return nil
            }
            return (max(maxD - minS, 0) / maxD).clamped01
        }
        return fractions.isEmpty ? 0 : fractions.average.clamped01
    }

    private static func meanFeatures(_ features: [[Double]], count: Int) -> [Double] {
        guard !features.isEmpty else { return [Double](repeating: 0, count: count) }
        var mean = [Double](repeating: 0, count: count)
        for feature in features {
            for i in 0..<count {
                mean[i] += feature[safe: i, fallback: 0]
            }
        }
        return mean.map { $0 / Double(features.count) }
    }

    private static func buildFeatureSummary(frames: [FrameAnalysis], meanB: [Double], meanF: [Double], contractility: Double, contractilityFraction: Double, warning: String) -> String {
        let views = Set(frames.map(\.view)).sorted().joined(separator: ", ")
        let phaseText = frames.prefix(24).map { "\($0.loaded.displayName):\($0.phase)/\($0.view)" }.joined(separator: ", ")
        return """
        输入 \(frames.count) 个文件/帧，覆盖体位: \(views). 相位识别: \(phaseText). 收缩-舒张腔室面积代理差值: \(contractility.f3); contractility_fraction_proxy=\(contractilityFraction.f3). B-mode 边缘密度=\(meanB[safe: 5, fallback: 0].f3), 纹理熵=\(meanB[safe: 6, fallback: 0].f3); Doppler 活跃区比例=\(meanF[safe: 4, fallback: 0].f3), 湍流代理=\(meanF[safe: 5, fallback: 0].f3), 涡量代理=\(meanF[safe: 8, fallback: 0].f3). \(warning)
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension RGBImage {
    func resized(to size: Int) -> RGBImage {
        guard width != size || height != size else { return self }
        var out = [UInt8](repeating: 0, count: size * size * 3)
        for y in 0..<size {
            let srcY = min(height - 1, max(0, Int(Double(y) * Double(height) / Double(size))))
            for x in 0..<size {
                let srcX = min(width - 1, max(0, Int(Double(x) * Double(width) / Double(size))))
                let src = (srcY * width + srcX) * 3
                let dst = (y * size + x) * 3
                out[dst] = pixels[src]
                out[dst + 1] = pixels[src + 1]
                out[dst + 2] = pixels[src + 2]
            }
        }
        return RGBImage(width: size, height: size, pixels: out)
    }

    func grayMatrix() -> [Double] {
        let count = width * height
        var gray = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let offset = index * 3
            gray[index] =
                0.299 * Double(pixels[offset]) / 255.0 +
                0.587 * Double(pixels[offset + 1]) / 255.0 +
                0.114 * Double(pixels[offset + 2]) / 255.0
        }
        return gray
    }
}

extension Array where Element == Double {
    var average: Double {
        isEmpty ? 0.0 : reduce(0, +) / Double(count)
    }

    subscript(safe index: Int, fallback fallback: Double) -> Double {
        indices.contains(index) ? self[index] : fallback
    }
}

extension Double {
    var clamped01: Double {
        min(max(self, 0.0), 1.0)
    }

    var f3: String {
        String(format: "%.3f", self)
    }
}
