import AppKit
import CoreGraphics

// MARK: - Hotkey
struct Hotkey: Codable, Equatable {
    /// 修饰键掩码: 1=⌘, 2=⇧, 4=⌥, 8=⌃
    var modifiers: Int
    /// 虚拟按键码（物理键位，与键盘布局无关）
    var keyCode: Int
    /// 显示名称（录制时按当前键盘布局获取，仅用于展示）
    var displayName: String
    
    static let command = 1
    static let shift = 2
    static let option = 4
    static let control = 8
    
    static let escKeyCode = 53
    
    static let defaultShow = Hotkey(modifiers: command, keyCode: escKeyCode, displayName: "esc")
    static let defaultPrev = Hotkey(modifiers: command | shift, keyCode: escKeyCode, displayName: "esc")
    
    /// 修饰键符号，按 macOS 习惯顺序：⌃ ⌥ ⇧ ⌘
    var modifierString: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s
    }
    
    /// 完整显示文本，如 "⌘ esc"
    var displayString: String {
        guard !modifierString.isEmpty else { return displayName }
        return modifierString + " " + displayName
    }
    
    /// 「选择应用」行的提示文本
    var releaseHint: String {
        guard !modifierString.isEmpty else { return "松开修饰键" }
        if modifierString.count == 1 { return "松开 \(modifierString) 键" }
        return "松开全部修饰键（\(modifierString)）"
    }
    
    /// 把 NSEvent 修饰键转成掩码
    static func mask(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= command }
        if flags.contains(.shift) { m |= shift }
        if flags.contains(.option) { m |= option }
        if flags.contains(.control) { m |= control }
        return m
    }
    
    /// 把 CGEvent 修饰键转成掩码
    static func mask(_ flags: CGEventFlags) -> Int {
        var m = 0
        if flags.contains(.maskCommand) { m |= command }
        if flags.contains(.maskShift) { m |= shift }
        if flags.contains(.maskAlternate) { m |= option }
        if flags.contains(.maskControl) { m |= control }
        return m
    }
    
    /// 特殊按键的显示名（不依赖键盘布局）
    static let specialKeyNames: [Int: String] = [
        36: "↩",      // Return
        48: "⇥",      // Tab
        49: "Space",  // Space
        51: "⌫",      // Delete (Backspace)
        53: "esc",    // Escape
        63: "fn",     // Function
        64: "F17",
        76: "↩",      // Keypad Enter
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        110: "菜单", 114: "帮助", 115: "Home", 116: "PgUp", 117: "⌦",
        118: "F4", 119: "End", 120: "F2", 121: "PgDn", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
    
    /// 生成按键显示名：优先特殊键表，其次取录制时的按键字符
    static func displayName(for keyCode: Int, characters: String?) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        if let ch = characters?.first, ch.isASCII, ch >= " " {
            return ch.uppercased()
        }
        if let ch = characters, ch.count == 1,
           let sc = ch.unicodeScalars.first, sc.value >= 0x21, sc.value != 0x7F {
            return ch
        }
        return "Key \(keyCode)"
    }
}
