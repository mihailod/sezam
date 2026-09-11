import SwiftUI

@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// The twelve Dynamic Type steps, smallest first. Using the platform's own
    /// scale rather than a multiplier means every semantic font (.body,
    /// .caption, .headline …) scales by the same rules the rest of iOS uses.
    static let steps: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
    ]
    private static let key = "typeSizeOverride"

    /// nil means "follow the system text size" — the default, and what someone
    /// who has already set a size in iOS Settings expects. A value here is a
    /// deliberate in-app override, and it persists.
    var overrideIndex: Int? {
        didSet {
            if let v = overrideIndex { UserDefaults.standard.set(v, forKey: Self.key) }
            else { UserDefaults.standard.removeObject(forKey: Self.key) }
        }
    }

    private init() {
        // `object(forKey:)` rather than `integer(forKey:)`: the latter returns 0
        // for a missing key, which is a real step (.xSmall) and would silently
        // shrink the app for every first-time user.
        overrideIndex = UserDefaults.standard.object(forKey: Self.key) as? Int
    }

    var isOverriding: Bool { overrideIndex != nil }

    var overrideSize: DynamicTypeSize? {
        overrideIndex.map { Self.steps[min(Self.steps.count - 1, max(0, $0))] }
    }

    func matchSystem() { overrideIndex = nil }

    static func index(of size: DynamicTypeSize) -> Int {
        steps.firstIndex(of: size) ?? 3      // .large
    }

    static func name(of size: DynamicTypeSize) -> String {
        switch size {
        case .xSmall:   return "Extra Small"
        case .small:    return "Small"
        case .medium:   return "Medium"
        case .large:    return "Default"
        case .xLarge:   return "Large"
        case .xxLarge:  return "Extra Large"
        case .xxxLarge: return "Extra Extra Large"
        default:        return "Accessibility"
        }
    }

    /// Message bodies stay monospaced at every size — the archive is full of
    /// box-drawing art and hand-aligned columns a proportional face would break.
    /// Relative to .footnote so it scales; a fixed point size would ignore
    /// Dynamic Type entirely.
    var messageFont: Font { .system(.footnote, design: .monospaced) }
}

/// The system's own text size, published separately from
/// `\.dynamicTypeSize` — which downstream reads as the *effective* size once
/// the root has applied an override. Settings needs the underlying value to
/// tell "matching the system" apart from "overridden to the same step".
private struct SystemTypeSizeKey: EnvironmentKey {
    static let defaultValue: DynamicTypeSize = .large
}

extension EnvironmentValues {
    var systemTypeSize: DynamicTypeSize {
        get { self[SystemTypeSizeKey.self] }
        set { self[SystemTypeSizeKey.self] = newValue }
    }
}
