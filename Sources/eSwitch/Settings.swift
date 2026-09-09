import Combine
import ServiceManagement

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            setLaunchAtLogin(launchAtLogin)
        }
    }
    
    @Published var panelScreenMode: PanelScreenMode {
        didSet {
            UserDefaults.standard.set(panelScreenMode.rawValue, forKey: "panelScreenMode")
        }
    }
    
    @Published var showHotkey: Hotkey {
        didSet {
            saveHotkey(showHotkey, key: "hotkeyShow")
        }
    }
    
    @Published var prevHotkey: Hotkey {
        didSet {
            saveHotkey(prevHotkey, key: "hotkeyPrev")
        }
    }
    
    @Published var windowPreview: Bool {
        didSet {
            UserDefaults.standard.set(windowPreview, forKey: "windowPreview")
            if !windowPreview {
                WindowPreviewProvider.shared.clear()
            }
        }
    }
    
    private init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        // 窗口预览默认开；无屏幕录制权限时启动探测会关掉它
        self.windowPreview = UserDefaults.standard.object(forKey: "windowPreview") as? Bool ?? true
        if let savedRaw = UserDefaults.standard.string(forKey: "panelScreenMode"),
           let mode = PanelScreenMode(rawValue: savedRaw) {
            self.panelScreenMode = mode
        } else {
            self.panelScreenMode = .mainScreen  // default: main screen
        }
        self.showHotkey = Self.loadHotkey(key: "hotkeyShow", fallback: .defaultShow)
        self.prevHotkey = Self.loadHotkey(key: "hotkeyPrev", fallback: .defaultPrev)
    }
    
    private static func loadHotkey(key: String, fallback: Hotkey) -> Hotkey {
        guard let data = UserDefaults.standard.data(forKey: key),
              let hk = try? JSONDecoder().decode(Hotkey.self, from: data) else {
            return fallback
        }
        return hk
    }
    
    private func saveHotkey(_ hk: Hotkey, key: String) {
        if let data = try? JSONEncoder().encode(hk) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                log("Launch at login error: \(error)")
            }
        } else {
            SMLoginItemSetEnabled((Bundle.main.bundleIdentifier ?? "") as CFString, enabled)
        }
    }
}
