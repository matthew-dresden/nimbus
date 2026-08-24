import AppKit
import Foundation

// Single source of truth for all user preferences.
final class PreferencesManager {

    static let shared = PreferencesManager()
    private init() {}

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key: String {
        case hotKeyCode      = "NimbusHotKeyCode"
        case hotKeyModifiers = "NimbusHotKeyModifiers"
        case saveFolderPath  = "NimbusSaveFolderPath"
        case autoCopyURL     = "NimbusAutoCopyURL"
        case autoSave        = "NimbusAutoSave"
        case imgurClientID   = "NimbusImgurClientID"
    }

    // MARK: - Properties

    var imgurClientID: String {
        get { defaults.string(forKey: Key.imgurClientID.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.imgurClientID.rawValue) }
    }

    var hotKeyCode: Int {
        get { defaults.integer(forKey: Key.hotKeyCode.rawValue).nonZero ?? 21 } // default: '4'
        set { defaults.set(newValue, forKey: Key.hotKeyCode.rawValue) }
    }

    var hotKeyModifiers: Int {
        get { defaults.integer(forKey: Key.hotKeyModifiers.rawValue).nonZero ?? 1048576 } // 1048576 = cmdKey
        set { defaults.set(newValue, forKey: Key.hotKeyModifiers.rawValue) }
    }

    var saveFolder: URL {
        get {
            if let path = defaults.string(forKey: Key.saveFolderPath.rawValue) {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Nimbus", isDirectory: true)
        }
        set {
            defaults.set(newValue.path, forKey: Key.saveFolderPath.rawValue)
            try? FileManager.default.createDirectory(at: newValue, withIntermediateDirectories: true)
        }
    }

    var autoCopyURL: Bool {
        get { defaults.bool(forKey: Key.autoCopyURL.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoCopyURL.rawValue) }
    }

    var autoSave: Bool {
        get { defaults.bool(forKey: Key.autoSave.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoSave.rawValue) }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
