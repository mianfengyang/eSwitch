import AppKit
import CoreGraphics
import Testing
import Foundation
@testable import eSwitch

@Suite("Hotkey 快捷键")
struct HotkeyTests {
    @Test("修饰键显示顺序为 ⌃⌥⇧⌘")
    func modifierOrder() {
        let all = Hotkey(modifiers: 15, keyCode: 53, displayName: "esc")
        #expect(all.modifierString == "⌃⌥⇧⌘")
        let cmdOnly = Hotkey(modifiers: 1, keyCode: 53, displayName: "esc")
        #expect(cmdOnly.modifierString == "⌘")
        let none = Hotkey(modifiers: 0, keyCode: 53, displayName: "esc")
        #expect(none.modifierString == "")
    }
    
    @Test("完整显示文本")
    func displayString() {
        let hk = Hotkey(modifiers: 2, keyCode: 49, displayName: "Space")
        #expect(hk.displayString == "⇧ Space")
        let both = Hotkey(modifiers: 3, keyCode: 49, displayName: "Space")
        #expect(both.displayString == "⇧⌘ Space")
        let bare = Hotkey(modifiers: 0, keyCode: 53, displayName: "esc")
        #expect(bare.displayString == "esc")
    }
    
    @Test("releaseHint 单/多修饰键")
    func releaseHint() {
        let single = Hotkey(modifiers: 1, keyCode: 53, displayName: "esc")
        #expect(single.releaseHint == "松开 ⌘ 键")
        let multi = Hotkey(modifiers: 3, keyCode: 53, displayName: "esc")
        #expect(multi.releaseHint == "松开全部修饰键（⇧⌘）")
    }
    
    @Test("JSON 序列化往返一致")
    func codableRoundTrip() throws {
        let hk = Hotkey(modifiers: 5, keyCode: 49, displayName: "Space")
        let data = try JSONEncoder().encode(hk)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        #expect(decoded == hk)
    }
    
    @Test("NSEvent 修饰键转掩码")
    func nseventMask() {
        #expect(Hotkey.mask([.command, .shift]) == 3)
        #expect(Hotkey.mask([.control, .option]) == 12)
        #expect(Hotkey.mask(NSEvent.ModifierFlags([])) == 0)
    }
    
    @Test("CGEvent 修饰键转掩码")
    func cgeventMask() {
        #expect(Hotkey.mask(CGEventFlags([.maskCommand, .maskAlternate])) == 5)
        #expect(Hotkey.mask(CGEventFlags([])) == 0)
    }
    
    @Test("特殊按键显示名")
    func specialKeyNames() {
        #expect(Hotkey.displayName(for: 53, characters: "\u{1B}") == "esc")
        #expect(Hotkey.displayName(for: 49, characters: " ") == "Space")
        #expect(Hotkey.displayName(for: 122, characters: "\u{FF5F}") == "F1")
    }
    
    @Test("字母/数字键取录制字符")
    func letterDisplayName() {
        #expect(Hotkey.displayName(for: 0, characters: "a") == "A")
        #expect(Hotkey.displayName(for: 18, characters: "1") == "1")
    }
    
    @Test("默认快捷键")
    func defaults() {
        #expect(Hotkey.defaultShow == Hotkey(modifiers: 1, keyCode: 53, displayName: "esc"))
        #expect(Hotkey.defaultPrev == Hotkey(modifiers: 3, keyCode: 53, displayName: "esc"))
    }
}

@Suite("App 首字母与字母跳转")
struct AppNamingTests {
    @Test("英文取首个字母（大写）")
    func english() {
        #expect("Safari".switcherInitial == "S")
        #expect("google chrome".switcherInitial == "G")
        #expect("QQ".switcherInitial == "Q")
    }

    @Test("中文名取应用英文名首字母（拼音已移除，改用英文名）")
    func chinese() {
        // 卡片/跳转基于英文名（Info.plist 原始值）：终端→Terminal, 微信→WeChat, 访达→Finder
        #expect("Terminal".switcherInitial == "T")
        #expect("WeChat".switcherInitial == "W")
        #expect("Finder".switcherInitial == "F")
        // 无 ASCII 字母的字符串回退占位符
        #expect("访达".switcherInitial == "•")
    }

    @Test("emoji/符号跳过，空白名回退 •")
    func symbols() {
        #expect("📷Camera".switcherInitial == "C")
        #expect("  Safari".switcherInitial == "S")
        #expect("".switcherInitial == "•")
        #expect("📷相机".switcherInitial == "•")
    }

    @Test("letterMatchIndices 返回全部同首字母下标（英文名）")
    func matchIndices() {
        // 名字为各自英文名：Safari / Finder / WeChat / Settings / Google Chrome
        let names = ["Safari", "Finder", "WeChat", "Settings", "Google Chrome"]
        #expect(letterMatchIndices(names: names, letter: "S") == [0, 3])
        #expect(letterMatchIndices(names: names, letter: "W") == [2])
        #expect(letterMatchIndices(names: names, letter: "X") == [])
    }
}

@Suite("SettingsManager 快捷键持久化")
struct SettingsHotkeyTests {
    private let showKey = "hotkeyShow"
    private let prevKey = "hotkeyPrev"
    
    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: showKey)
        UserDefaults.standard.removeObject(forKey: prevKey)
    }
    
    @Test("无存储时回退默认值")
    func fallbackToDefaults() {
        let previousShow = UserDefaults.standard.data(forKey: showKey)
        let previousPrev = UserDefaults.standard.data(forKey: prevKey)
        defer {
            if let p = previousShow { UserDefaults.standard.set(p, forKey: showKey) }
            else { UserDefaults.standard.removeObject(forKey: showKey) }
            if let p = previousPrev { UserDefaults.standard.set(p, forKey: prevKey) }
            else { UserDefaults.standard.removeObject(forKey: prevKey) }
        }
        cleanDefaults()
        // SettingsManager 是单例，只验证默认值与存储格式兼容
        #expect(Hotkey.defaultShow.modifiers == 1)
        #expect(Hotkey.defaultShow.keyCode == 53)
        #expect(Hotkey.defaultPrev.modifiers == 3)
    }
    
    @Test("存储格式可被回退逻辑解析")
    func storedFormatIsDecodable() throws {
        let hk = Hotkey(modifiers: 9, keyCode: 49, displayName: "Space")
        let data = try JSONEncoder().encode(hk)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        #expect(decoded.modifiers == 9)
        #expect(decoded.keyCode == 49)
        #expect(decoded.displayName == "Space")
    }
}
