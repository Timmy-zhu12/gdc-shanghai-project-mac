import Foundation

enum DiagnosisEngine {
    static func runDiagnosis(study: StudyAnalysis, config: ModelConfig) async -> DiagnosisReport {
        let judgment = classifyTeachingCondition(study)
        let prompt = buildGemma4Prompt(study: study, judgment: judgment)
        let runner = Gemma4Runner()
        let modelStatus = runner.status(config: config)

        let generated = await runner.generate(prompt: prompt, config: config)
        let body: String
        if let generated, !generated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = generated
        } else {
            body = heuristicDiagnosis(study: study, judgment: judgment)
        }

        return DiagnosisReport(
            teachingDiagnosis: judgment.label,
            confidence: judgment.confidence,
            body: body,
            modelStatus: modelStatus,
            featureSummary: study.featureSummary,
            createdAt: Date()
        )
    }

    static func classifyTeachingCondition(_ study: StudyAnalysis) -> TeachingJudgment {
        let b = study.meanBMode
        let f = study.meanFlow
        let edgeDensity = b[safe: 5, fallback: 0]
        let entropy = b[safe: 6, fallback: 0]
        let chamberProxy = b[safe: 9, fallback: 0]
        let dopplerActive = f[safe: 4, fallback: 0]
        let turbulence = f[safe: 5, fallback: 0]
        let vorticity = f[safe: 8, fallback: 0]
        let contractility = study.contractilityProxy
        let views = Set(study.frames.map(\.view))
        let hasA4C = views.contains("A4C")
        let hasA5C = views.contains("A5C")
        let hasA2C = views.contains("A2C")
        let hasA3C = views.contains("A3C")
        let hasPLAX = views.contains("PLAX")
        let hasPSAXAV = views.contains("PSAX-AV")
        let towards = f[safe: 0, fallback: 0]
        let away = f[safe: 1, fallback: 0]
        let signed = f[safe: 3, fallback: 0.5]
        let enoughPhase = study.systoleCount >= 1 && study.diastoleCount >= 1
        let broadCoverage = study.viewCount >= 6

        let label: String
        let rationale: String
        if dopplerActive > 0.14 && (turbulence > 0.055 || vorticity > 0.045) && (hasPLAX || hasA3C) {
            label = "中度二尖瓣反流"
            rationale = "PLAX/A3C 相关输入中 Doppler 活跃区和湍流/涡量代理明显升高，教学规则将其归入二尖瓣反流谱系。"
        } else if dopplerActive > 0.13 && hasA4C && (turbulence > 0.045 || vorticity > 0.04) {
            label = "中度三尖瓣反流"
            rationale = "A4C 相关输入中 Doppler 活跃区较高并伴湍流/涡量代理升高，教学规则归入中度三尖瓣反流。"
        } else if dopplerActive > 0.07 && (hasPLAX || hasA3C || hasA2C) && signed < 0.54 {
            label = "轻度二尖瓣反流"
            rationale = "二尖瓣相关切面中出现一定 Doppler 活跃区，方向代理偏向反流侧，但湍流代理未达到中度阈值。"
        } else if dopplerActive > 0.07 && hasA4C && signed >= 0.54 {
            label = "轻度三尖瓣反流"
            rationale = "A4C 输入中右心房室区常见反流教学模式与当前 Doppler 方向代理相符，活跃区未达到中重度阈值。"
        } else if dopplerActive > 0.09 && (hasA5C || hasPSAXAV) && (turbulence > 0.035 || vorticity > 0.035) {
            label = "主动脉瓣轻度狭窄倾向"
            rationale = "A5C/主动脉瓣短轴相关输入中出现高速紊流代理，符合主动脉瓣口狭窄教学样例的早期阈值。"
        } else if dopplerActive > 0.08 && hasA5C && away > towards {
            label = "轻度主动脉瓣反流"
            rationale = "A5C 相关输入中 Doppler 方向代理偏离正常射流方向，教学规则将其归入主动脉瓣反流。"
        } else if dopplerActive > 0.11 && hasPSAXAV && (turbulence > 0.035 || vorticity > 0.035) {
            label = "肺动脉瓣轻度反流"
            rationale = "主动脉瓣短轴层面附近的流场活跃和涡量代理升高，在当前简化规则中对应肺动脉瓣反流教学标签。"
        } else if enoughPhase && contractility < 0.035 && chamberProxy > 0.55 {
            label = "左心室收缩功能减低"
            rationale = "收缩态与舒张态腔室面积代理差值偏低，提示教学参考下的收缩幅度不足。"
        } else if edgeDensity > 0.30 || entropy > 0.74 {
            label = "节段性室壁运动异常"
            rationale = "B-mode 差分矩阵边缘密度或纹理熵偏高，且未达到明确瓣膜反流阈值，教学规则归入室壁运动异常。"
        } else if dopplerActive > 0.045 {
            label = defaultMildValveLabel(views: views, signed: signed, towards: towards, away: away)
            rationale = "Doppler 活跃区存在但湍流代理不高，因此输出对应切面的轻度瓣膜反流教学标签。"
        } else if !enoughPhase {
            label = "图像证据不足，倾向未见明确异常"
            rationale = "缺少可靠的收缩/舒张配对，当前只能给出低置信度的教学参考判断。"
        } else {
            label = "未见明确心脏超声异常"
            rationale = "B-mode 结构代理、收缩舒张差异和 Doppler 代理未达到异常阈值。"
        }

        let confidence: String
        if broadCoverage && enoughPhase {
            confidence = "中等"
        } else if enoughPhase {
            confidence = "中低"
        } else {
            confidence = "低"
        }
        return TeachingJudgment(label: label, confidence: confidence, rationale: rationale)
    }

    static func heuristicDiagnosis(study: StudyAnalysis, judgment: TeachingJudgment? = nil) -> String {
        let judgment = judgment ?? classifyTeachingCondition(study)
        let b = study.meanBMode
        let f = study.meanFlow
        var phasePhrase = "系统自动识别出 \(study.diastoleCount) 个舒张态、\(study.systoleCount) 个收缩态"
        if study.systoleCount == 0 || study.diastoleCount == 0 {
            phasePhrase += "，收缩/舒张配对不足"
        }
        let warning = study.coverageWarning.isEmpty ? "" : " \(study.coverageWarning)"
        return """
        教学参考病症判断：\(judgment.label)。本次输入包含 \(study.inputCount) 个文件/帧，覆盖约 \(study.viewCount) 个体位，\(phasePhrase)；判断依据为：\(judgment.rationale)B-mode 边缘密度 \(b[safe: 5, fallback: 0].f3)、纹理熵 \(b[safe: 6, fallback: 0].f3)、收缩舒张腔室面积代理差值 \(study.contractilityProxy.f3)；Color Doppler 活跃区比例 \(f[safe: 4, fallback: 0].f3)、湍流代理 \(f[safe: 5, fallback: 0].f3)、涡量代理 \(f[safe: 8, fallback: 0].f3)。综合当前体位覆盖、相位识别和边缘计算特征，本次教学参考置信度为\(judgment.confidence)。\(warning)该结论是为了医学教学和算法演示而给出的明确参考判断，不作为临床最终诊断、治疗建议或医嘱；正式判断仍需结合完整标准切面、DICOM 标尺、连续动态帧、病史、体征和超声医师报告。
        """
    }

    static func buildGemma4Prompt(study: StudyAnalysis, judgment: TeachingJudgment) -> String {
        """
        你是离线运行在 iPhone/macOS 设备上的 Gemma4 4B 医学教学辅助工具。你正在分析脱敏心脏超声图像的本地边缘计算特征。

        任务：必须给出一个明确的“教学参考病症判断”，病症名称要精确到具体超声常见病症，例如“轻度二尖瓣反流”“轻度三尖瓣反流”“主动脉瓣轻度狭窄倾向”“左心室收缩功能减低”等，不要只说“异常血流”或“瓣膜病变”。但必须说明该判断仅用于医学教学参考，不能替代临床诊断。

        输入范围：
        - 最大输入：标准心脏超声 12 个体位，每个体位可包含收缩态与舒张态。
        - 最小输入：任意一个体位的收缩态与舒张态。
        - 系统已自动区分收缩态/舒张态，若信息不足会标注置信度。

        请输出一段中文自然语言，包含明确病症判断、教学参考置信度、判断依据、局限性和安全声明。
        预判标签：\(judgment.label)
        预判置信度：\(judgment.confidence)

        特征摘要：
        \(study.featureSummary)

        紧凑特征：
        \(study.compactFeatureText())
        """
    }

    private static func defaultMildValveLabel(views: Set<String>, signed: Double, towards: Double, away: Double) -> String {
        if views.contains("A4C") && signed >= 0.52 {
            return "轻度三尖瓣反流"
        }
        if views.contains("PLAX") || views.contains("A3C") || views.contains("A2C") {
            return "轻度二尖瓣反流"
        }
        if views.contains("A5C") {
            return away > towards ? "轻度主动脉瓣反流" : "主动脉瓣轻度狭窄倾向"
        }
        if views.contains("PSAX-AV") {
            return "肺动脉瓣轻度反流"
        }
        return "轻度二尖瓣反流"
    }
}

struct Gemma4Runner {
    func status(config: ModelConfig) -> String {
        #if os(macOS)
        let exeReady = !config.llamaExecutable.isEmpty && FileManager.default.fileExists(atPath: expanded(config.llamaExecutable))
        let modelReady = FileManager.default.fileExists(atPath: expanded(config.modelPath))
        if exeReady && modelReady {
            return "Gemma4 4B offline: \(URL(fileURLWithPath: expanded(config.modelPath)).lastPathComponent)"
        }
        var missing: [String] = []
        if !exeReady { missing.append("llama-cli") }
        if !modelReady { missing.append("Gemma4 4B GGUF") }
        return "Rule fallback active; missing \(missing.joined(separator: ", "))"
        #else
        return "iPhone local rule fallback active; native Gemma4 4B backend requires llama.cpp/Metal XCFramework"
        #endif
    }

    func generate(prompt: String, config: ModelConfig) async -> String? {
        #if os(macOS)
        let exe = expanded(config.llamaExecutable)
        let model = expanded(config.modelPath)
        guard !exe.isEmpty, FileManager.default.fileExists(atPath: exe), FileManager.default.fileExists(atPath: model) else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exe)
            process.currentDirectoryURL = URL(fileURLWithPath: exe).deletingLastPathComponent()
            process.arguments = [
                "-m", model,
                "-p", prompt,
                "-n", "\(config.maxTokens)",
                "--temp", "\(config.temperature)",
                "--no-display-prompt"
            ]
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return text?.isEmpty == false ? text : nil
            } catch {
                return nil
            }
        }.value
        #else
        return nil
        #endif
    }

    private func expanded(_ path: String) -> String {
        let ns = path as NSString
        if path.hasPrefix("~") {
            return ns.expandingTildeInPath
        }
        if path.hasPrefix("/") {
            return path
        }
        let current = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: current).appendingPathComponent(path).path
    }
}
