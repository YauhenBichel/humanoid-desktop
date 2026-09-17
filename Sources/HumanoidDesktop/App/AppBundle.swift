import Foundation
import TeammateKit

extension Bundle {
    /// The app's strings, one `.lproj` per language (see `Bundle.packaged`).
    static let app = packaged("humanoid-desktop_HumanoidDesktop", fallback: .module)
}
