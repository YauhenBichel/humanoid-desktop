import Foundation

extension Bundle {
    /// A SwiftPM resource bundle, found where a packaged app keeps it (`Contents/Resources`), or else where SwiftPM
    /// put it. `Bundle.module` alone looks next to the `.app` and then in the build folder, so an app copied to
    /// another Mac, or built before a clean, would stop at launch; and a bundle next to `Contents` would break the
    /// app's signature.
    public static func packaged(_ name: String, fallback: @autoclosure () -> Bundle) -> Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("\(name).bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        return fallback()
    }

    static let teammateKit = packaged("humanoid-desktop_TeammateKit", fallback: .module)
}
