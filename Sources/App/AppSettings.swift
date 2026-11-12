import Foundation

struct AppSettings {
    private enum Key {
        static let autoReconnect = "autoReconnect"
        static let connectAtLogin = "connectAtLogin"
    }

    var autoReconnect: Bool {
        get {
            UserDefaults.standard.object(forKey: Key.autoReconnect) as? Bool ?? true
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: Key.autoReconnect)
        }
    }

    var connectAtLogin: Bool {
        get {
            UserDefaults.standard.object(forKey: Key.connectAtLogin) as? Bool ?? false
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: Key.connectAtLogin)
        }
    }
}
