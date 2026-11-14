// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TesseraClock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TesseraClockApp",
            path: "App"
        ),
    ]
)
