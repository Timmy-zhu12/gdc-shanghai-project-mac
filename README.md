# CardioConsult Apple 版中文说明

CardioConsult Apple 版是基于 PC 版功能重新制作的 iPhone / macOS 版本。项目目标是尽量保留 PC 端完整工作流：导入脱敏心脏超声 PNG / DICOM / DCOM 文件，在本机完成边缘计算，自动识别体位与收缩/舒张相位，并输出明确到病症名称的中文教学参考判断。

> 医学安全声明：本项目仅用于医学教学、比赛演示和算法验证，不作为临床最终诊断、治疗建议或医嘱。正式医学判断仍需结合完整标准切面、DICOM 标尺、连续动态帧、病史、体征和超声医师报告。

## 重要实现说明

本仓库包含两个 Apple 目标：

- `CardioConsultMac`：macOS SwiftUI App。保留 PC 端完整功能，并且可以通过本机 `llama-cli` 调用离线 Gemma4 4B GGUF 模型。
- `CardioConsultiOS`：iPhone / iPad SwiftUI App。保留同一套导入、边缘计算、体位/相位识别、精确病症规则和模型文件契约。由于 iOS 不能像 macOS 一样直接运行外部 `llama-cli` 进程，真正的 iPhone 端 GGUF 推理需要额外接入 llama.cpp / Metal XCFramework 或等价原生后端；未接入前，iPhone 端会使用与 PC 同源的本地规则后备，保证应用可离线演示。

换句话说：

- macOS：已实现离线 Gemma4 4B 计算入口，可直接配置 `llama-cli` + GGUF。
- iPhone：已实现完整应用、输入处理和诊断规则，Gemma4 4B 原生推理接口预留；接入原生后端前使用本地规则后备。

## 仓库地址

```text
https://github.com/Timmy-zhu12/gdc-shanghai-project-mac
```

建议在 D 盘保存源码：

```bat
D:\cardioconsult_Apple_runbook
```

如果从 GitHub clone 到 Mac 上，建议目录：

```bash
git clone https://github.com/Timmy-zhu12/gdc-shanghai-project-mac.git
cd gdc-shanghai-project-mac
```

## 功能对齐 PC 版

已移植的 PC 端功能包括：

- 多文件导入。
- PNG / JPG / TIFF / BMP 图片读取。
- DICOM / DCOM 轻量解析。
- 未压缩 DICOM 多帧拆分。
- 最大输入目标：标准心脏超声 12 个体位。
- 最小输入目标：任意一个体位的收缩态与舒张态。
- 自动体位识别：PLAX、PSAX-AV、PSAX-MV、PSAX-PM、PSAX-APEX、A4C、A5C、A2C、A3C、SUBCOSTAL-4C、IVC、SUPRASTERNAL。
- 自动相位识别：优先看文件名，缺失时使用腔室面积代理。
- B-mode 差分矩阵与 DoG 特征。
- Color Doppler HSV 到二维血流向量转换。
- 血流活跃区、方向代理、湍流代理、涡量代理。
- StudyAnalysis 聚合。
- 与 PC 同源的明确病症标签规则。
- macOS 离线 Gemma4 4B `llama-cli` 调用。
- 模型缺失时规则后备。
- 结果导出为 `.txt`。

## 当前可输出的教学参考病症标签

示例包括：

- 轻度二尖瓣反流
- 轻度三尖瓣反流
- 中度二尖瓣反流
- 中度三尖瓣反流
- 轻度主动脉瓣反流
- 主动脉瓣轻度狭窄倾向
- 肺动脉瓣轻度反流
- 左心室收缩功能减低
- 节段性室壁运动异常
- 图像证据不足，倾向未见明确异常
- 未见明确心脏超声异常

这些标签是教学参考输出，不是临床诊断结论。

## 项目结构

```text
cardioconsult_Apple_runbook/
├── CardioConsultApple.xcodeproj/
│   └── project.pbxproj
├── Package.swift
├── Sources/CardioConsultApple/
│   ├── CardioConsultAppleApp.swift
│   ├── ContentView.swift
│   ├── ViewModel.swift
│   ├── Models.swift
│   ├── ImageLoader.swift
│   ├── FeatureExtractor.swift
│   └── DiagnosisEngine.swift
├── Models/
│   └── README.md
├── Scripts/
│   ├── build_mac.sh
│   ├── build_ios_simulator.sh
│   ├── copy_models_to_ios_simulator.sh
│   └── run_mac_with_llama_example.sh
├── Samples/
└── Exports/
```

## 开发环境

必须在 macOS 上构建 iPhone / macOS 应用。

推荐环境：

- macOS 14 或以上
- Xcode 15 或以上
- Swift 5.9 或以上
- iPhone 真机或 iOS Simulator
- macOS 本机运行 Gemma4 4B 时建议 16 GB RAM 起步，推荐 24 GB 或以上

这份源码是在 Windows 上生成并推送的，因此不能在当前机器上完成 Xcode 编译验证。请在 Mac 上打开工程并构建。

## macOS 部署

### 1. 打开工程

在 Mac 上运行：

```bash
open CardioConsultApple.xcodeproj
```

选择 scheme：

```text
CardioConsultMac
```

运行目标选择：

```text
My Mac
```

点击 Run。

### 2. 命令行构建

也可以使用脚本：

```bash
chmod +x Scripts/*.sh
Scripts/build_mac.sh
```

脚本内部会执行：

```bash
xcodebuild \
  -project CardioConsultApple.xcodeproj \
  -scheme CardioConsultMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

### 3. 配置 macOS 离线 Gemma4 4B

准备本地 `llama-cli`，例如：

```text
/opt/homebrew/bin/llama-cli
```

准备模型文件，例如：

```text
/Users/<you>/Models/gemma-4-4b-it-Q4_K_M.gguf
```

打开 App 后进入：

```text
Gemma4 Settings
```

填写：

- `llama-cli path`
- `GGUF model path`
- `mmproj path`，可选预留
- `max tokens`
- `temperature`

当 `llama-cli` 和 GGUF 模型都存在时，macOS 目标会通过 `Process` 直接调用本地离线 Gemma4 4B。若调用失败或模型缺失，系统会自动回退到本地规则诊断。

## iPhone / iPad 部署

### 1. 打开工程

```bash
open CardioConsultApple.xcodeproj
```

选择 scheme：

```text
CardioConsultiOS
```

选择运行目标：

- iPhone Simulator
- 连接的 iPhone 真机

点击 Run。

### 2. 命令行构建 iOS Simulator

```bash
chmod +x Scripts/*.sh
Scripts/build_ios_simulator.sh
```

脚本内部会执行：

```bash
xcodebuild \
  -project CardioConsultApple.xcodeproj \
  -scheme CardioConsultiOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

如果你的模拟器名字不是 `iPhone 15`，先查看可用目标：

```bash
xcrun simctl list devices
```

然后修改脚本中的 destination。

### 3. 真机部署

真机部署需要：

- Apple Developer 账号
- Xcode 自动签名
- iPhone 打开开发者模式
- 使用 USB 或 Wi-Fi 连接到 Xcode

在 Xcode 中：

1. 选择 `CardioConsultiOS`。
2. 选择你的 iPhone。
3. 打开 target signing。
4. 选择你的 Team。
5. 修改 Bundle Identifier，必要时改为你自己的唯一值。
6. 点击 Run。

## iPhone 端 Gemma4 4B 离线说明

iPhone 与 macOS 最大差异是沙盒限制：

- macOS 可以用 `Process` 运行外部 `llama-cli`。
- iOS 不允许 App 直接运行外部命令行程序。

因此 iPhone 若要真正运行 GGUF Gemma4 4B，需要把 llama.cpp / Metal 推理后端编译进 App，例如：

- llama.cpp iOS / Metal XCFramework
- 自定义 C API bridge
- Swift 调用原生推理接口
- 将 GGUF 模型通过 App Documents、Files app 或 bundled resource 放入可访问目录

当前仓库已经保留同一套模型文件契约：

```text
gemma-4-4b-it-Q4_K_M.gguf
gemma-4-4b-mmproj-Q4_0.gguf
```

但默认没有提交 llama.cpp 编译产物和大模型文件。这样做是为了保持 GitHub 仓库可下载、可审查、不会被大文件撑爆。未接入 iOS 原生后端时，iPhone 端仍会离线运行完整边缘计算与规则后备诊断。

## 输入文件规范

支持：

```text
.png
.jpg
.jpeg
.bmp
.tif
.tiff
.dcm
.dicom
.dcom
```

推荐命名：

```text
A4C_ED.png
A4C_ES.png
PLAX_ED.png
PLAX_ES.png
A5C_color_doppler.png
```

相位关键词：

- 舒张态：`ED`、`diastole`、`diastolic`、`end_diastole`、`舒张`
- 收缩态：`ES`、`systole`、`systolic`、`end_systole`、`收缩`

体位关键词：

- `PLAX`
- `PSAX-AV`
- `PSAX-MV`
- `PSAX-PM`
- `PSAX-APEX`
- `A4C`
- `A5C`
- `A2C`
- `A3C`
- `SUBCOSTAL-4C`
- `IVC`
- `SUPRASTERNAL`

## 应用使用流程

1. 打开 App。
2. 点击 `Import PNG / DICOM Batch`。
3. 选择一张或多张脱敏心脏超声图像。
4. 检查 `Selected Input` 和 `Edge Computing Summary`。
5. 点击 `Start Diagnosis`。
6. 查看 `教学参考病症判断`。
7. 如需保存，点击 `Export Report`。

## 边缘计算框架

### B-mode

B-mode 图像会转换为灰度矩阵，并提取：

- 灰度均值
- 灰度方差
- 横向差分
- 纵向差分
- 梯度强度
- 边缘密度
- 纹理熵
- DoG 均值
- DoG 高响应比例
- 腔室面积代理

### Color Doppler

Color Doppler 图会转换到 HSV 空间，并构造二维血流向量场：

```text
speed = saturation * value
vx = speed * cos(theta)
vy = speed * sin(theta)
```

提取：

- 朝向探头代理比例
- 远离探头代理比例
- 平均速度代理
- 有符号方向代理
- 血流活跃区比例
- 湍流代理
- 梯度能量
- 散度代理
- 涡量代理
- 置信度代理

## 已知限制

- 本项目是医学教学原型，不是医疗器械。
- 规则阈值没有经过大规模临床验证。
- 轻量 DICOM 解析器主要支持未压缩 Little Endian DICOM。
- 压缩 DICOM 需要额外解码库。
- iPhone 端默认不能直接运行外部 `llama-cli`。
- iPhone 端如需真正 Gemma4 4B GGUF 推理，需要接入 native llama.cpp / Metal 后端。
- macOS 离线 Gemma4 4B 推理质量取决于本地模型、量化精度和 `llama-cli` 构建。

## GitHub 大文件策略

不会提交：

- `.build/`
- `DerivedData/`
- `.app`
- `.ipa`
- `.dSYM`
- `Models/*.gguf`
- 本地签名文件
- 本地导出报告

模型文件请通过单独渠道保存。

## 与 PC 版的关系

本 Apple 版以 PC 版为基准移植：

- 诊断标签规则保持一致。
- 特征顺序保持一致。
- prompt 结构保持一致。
- macOS 离线 Gemma4 4B 计算方式与 PC 版同样使用本地 `llama-cli`。
- iPhone 版因系统限制不能直接运行 CLI，因此需要原生后端才能完全等价运行 Gemma4 4B。

## 推荐比赛展示方式

如果现场有 Mac：

1. 运行 `CardioConsultMac`。
2. 配置 `llama-cli` 与 Gemma4 4B GGUF。
3. 导入 PNG / DICOM 样例。
4. 展示离线模型生成的中文教学参考判断。

如果现场展示 iPhone：

1. 运行 `CardioConsultiOS`。
2. 从 Files app 导入脱敏图像。
3. 展示手机端本地边缘计算和规则后备诊断。
4. 说明 Gemma4 4B 原生后端为后续接入点，模型文件契约与 macOS/PC 保持一致。

## 许可证

本仓库原创代码、脚本、UI、配置与文档采用 Apache License 2.0 发布，详见 [LICENSE](LICENSE)。

注意：该许可证不覆盖第三方模型权重、GGUF 文件、移动/桌面系统 SDK、超声软件、医学影像数据集、第三方商标或用户提供的教学/临床数据；这些内容仍受其各自许可、平台条款或伦理/机构授权约束。详细边界见 [NOTICE](NOTICE)。
