import Foundation
import TeammateKit

/// Remembers the chosen teammate across launches.
@MainActor
final class UserDefaultsChoiceStore: TeammateChoiceStore {
    private let defaults: UserDefaults
    private let key = "teammate"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var chosenKey: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
