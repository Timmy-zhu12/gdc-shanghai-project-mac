// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CardioConsultApple",
    platforms: [
        .macOS(.v13),
        .iOS(.16)
    ],
    products: [
        .executable(name: "CardioConsultApple", targets: ["CardioConsultApple"])
    ],
    targets: [
        .executableTarget(
            name: "CardioConsultApple",
            path: "Sources/CardioConsultApple"
        )
    ]
)

