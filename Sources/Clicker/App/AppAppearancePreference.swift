import Foundation
import SwiftUI

enum AppAppearancePreference: String, CaseIterable, Equatable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

protocol AppAppearancePreferenceProviding: AnyObject {
    var preference: AppAppearancePreference { get set }
}

final class AppAppearancePreferenceStore: AppAppearancePreferenceProviding {
    private let defaults: UserDefaults
    private let key = "clicker.appearancePreference"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preference: AppAppearancePreference {
        get {
            guard let rawValue = defaults.string(forKey: key),
                  let preference = AppAppearancePreference(rawValue: rawValue) else {
                return .system
            }
            return preference
        }
        set {
            defaults.set(newValue.rawValue, forKey: key)
        }
    }
}
