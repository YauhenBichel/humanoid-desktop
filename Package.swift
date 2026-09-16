// swift-tools-version: 6.0
// humanoid-desktop: a floating humanoid teammate on the Mac desktop.
//
//   TeammateKit       everything that is not UI: settings and teammate files, the conversation with the
//                     model, reply validation, the speech and transcription clients. Tested by `swift test`.
//   HumanoidDesktop   the app: the floating character, the chat bubble, the menu bar item, voice in and out.
//                     scripts/build-app.sh wraps it in HumanoidDesktop.app.
import PackageDescription

let package = Package(
    name: "humanoid-desktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HumanoidDesktop", targets: ["HumanoidDesktop"]),
        .library(name: "TeammateKit", targets: ["TeammateKit"]),
    ],
    targets: [
        .target(name: "TeammateKit"),
        .executableTarget(name: "HumanoidDesktop", dependencies: ["TeammateKit"]),
        // Fixtures/ holds files written by humanoid-companion itself (its settings and teammate templates):
        // both apps must read the same files.
        .testTarget(name: "TeammateKitTests", dependencies: ["TeammateKit"], resources: [.copy("Fixtures")]),
    ]
)
