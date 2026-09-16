// swift-tools-version: 6.0
// humanoid-desktop: a floating humanoid teammate on the desktop.
//
//   TeammateKit       everything that is not UI: settings and teammate files, the conversation with the model,
//                     reply checks, languages, the speech and transcription clients. Portable: it builds and is
//                     tested on macOS and Linux, and uses nothing Apple-only, so apps for other systems can use it.
//   HumanoidDesktop   the macOS app: the floating character, the chat bubble, the menu bar item, voice in and out.
//                     scripts/build-app.sh wraps it in HumanoidDesktop.app. Built only on macOS.
import PackageDescription

var products: [Product] = [.library(name: "TeammateKit", targets: ["TeammateKit"])]
var targets: [Target] = [
    .target(name: "TeammateKit"),
    // Fixtures/ holds files written by humanoid-companion itself (its settings and teammate templates):
    // both apps must read the same files.
    .testTarget(name: "TeammateKitTests", dependencies: ["TeammateKit"], resources: [.copy("Fixtures")]),
]

#if os(macOS)
    products.append(.executable(name: "HumanoidDesktop", targets: ["HumanoidDesktop"]))
    targets.append(
        .executableTarget(
            name: "HumanoidDesktop", dependencies: ["TeammateKit"], resources: [.process("Resources")]))
#endif

let package = Package(
    name: "humanoid-desktop",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
