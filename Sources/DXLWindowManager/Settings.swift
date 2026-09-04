import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard

    static var snapEnabled: Bool {
        get { defaults.object(forKey: "snapEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "snapEnabled") }
    }

    static var snapAssistEnabled: Bool {
        get { defaults.object(forKey: "snapAssistEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "snapAssistEnabled") }
    }

    static var gap: Double {
        get {
            if defaults.object(forKey: "gap") == nil { return 8 }
            return defaults.double(forKey: "gap")
        }
        set { defaults.set(newValue, forKey: "gap") }
    }
}
