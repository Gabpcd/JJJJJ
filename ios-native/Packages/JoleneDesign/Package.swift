// swift-tools-version:5.10
import PackageDescription

// Contrôle de concurrence strict (plan §4.1, DECISIONS_LOT0) : équivalent de
// `SWIFT_STRICT_CONCURRENCY = complete` de la cible app, appliqué aux cibles du package
// (jamais aux dépendances). Autorisé pour un package consommé par d'autres, contrairement
// à `unsafeFlags`.
let strictConcurrency: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "JoleneDesign",
    defaultLocalization: "fr",
    platforms: [.iOS(.v16)],
    products: [.library(name: "JoleneDesign", targets: ["JoleneDesign"])],
    dependencies: [.package(path: "../JoleneCore")],
    targets: [
        .target(name: "JoleneDesign", dependencies: ["JoleneCore"], swiftSettings: strictConcurrency),
        .testTarget(name: "JoleneDesignTests", dependencies: ["JoleneDesign", "JoleneCore"], swiftSettings: strictConcurrency),
    ]
)
