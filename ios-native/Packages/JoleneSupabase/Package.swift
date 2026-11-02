// swift-tools-version:5.10
import PackageDescription

// Contrôle de concurrence strict (plan §4.1, DECISIONS_LOT0) : équivalent de
// `SWIFT_STRICT_CONCURRENCY = complete` de la cible app, appliqué aux cibles du package
// (jamais aux dépendances). Autorisé pour un package consommé par d'autres, contrairement
// à `unsafeFlags`.
let strictConcurrency: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "JoleneSupabase",
    defaultLocalization: "fr",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "JoleneSupabase", targets: ["JoleneSupabase"])],
    dependencies: [
        .package(path: "../JoleneCore"),
        // 2.55.5 est la dernière version en swift-tools 6.1 (2.55.6 exige 6.4, Xcode 26).
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.5"),
    ],
    targets: [
        .target(name: "JoleneSupabase", dependencies: [
            "JoleneCore",
            .product(name: "Supabase", package: "supabase-swift"),
        ], swiftSettings: strictConcurrency),
        .testTarget(name: "JoleneSupabaseTests", dependencies: ["JoleneSupabase"], swiftSettings: strictConcurrency),
    ]
)
