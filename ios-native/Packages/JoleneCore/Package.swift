// swift-tools-version:5.10
import PackageDescription

// Contrôle de concurrence strict (plan §4.1, DECISIONS_LOT0) : équivalent de
// `SWIFT_STRICT_CONCURRENCY = complete` de la cible app, appliqué aux cibles du package
// (jamais aux dépendances). Autorisé pour un package consommé par d'autres, contrairement
// à `unsafeFlags`.
let strictConcurrency: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "JoleneCore",
    defaultLocalization: "fr",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "JoleneCore", targets: ["JoleneCore"])],
    targets: [
        .target(name: "JoleneCore", resources: [.copy("Resources")], swiftSettings: strictConcurrency),
        .testTarget(name: "JoleneCoreTests", dependencies: ["JoleneCore"], resources: [.copy("Resources")], swiftSettings: strictConcurrency),
    ]
)
