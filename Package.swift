// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framelet",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Framelet", targets: ["Framelet"])],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "2.2.3")
    ],
    targets: [
        .executableTarget(
            name: "Framelet",
            dependencies: [.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            path: "Framelet",
            exclude: ["Assets.xcassets", "Framelet.entitlements", "Localizable.xcstrings", "AppIcon.icns", "PrivacyInfo.xcprivacy"]
        )
    ]
)
