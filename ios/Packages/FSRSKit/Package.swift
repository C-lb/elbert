// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FSRSKit",
    // macOS is here only so `swift test` can run the package's own tests from the command line
    // without a simulator. The app itself is iOS 17+.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FSRSKit", targets: ["FSRSKit"]),
    ],
    dependencies: [
        // A bare revision, not a tag. The only tagged release, 5.0.0, keeps its entire
        // scheduling API internal and cannot be driven from another module at all. See
        // ios/README.md and the task 6 notes in the spec.
        .package(
            url: "https://github.com/open-spaced-repetition/swift-fsrs",
            revision: "4fbaf20184d62f82a9f44f343337c61a2c5483e9"
        ),
    ],
    targets: [
        .target(name: "FSRSKit", dependencies: [.product(name: "FSRS", package: "swift-fsrs")]),
        .testTarget(name: "FSRSKitTests", dependencies: ["FSRSKit"]),
    ]
)
