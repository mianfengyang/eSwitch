import AppKit
import CoreGraphics

// MARK: - Keyboard
var globalEventTap: CFMachPort?

/// 从 CGEvent 取按键产生的字符（首个）。受 layout 影响、忽略 command 修饰（大小写由 shift 决定），
/// 用于「按住呼出修饰键按字母」的快速定位。
func cgEventLetter(_ event: CGEvent) -> Character? {
    var buffer = [UniChar](repeating: 0, count: 8)
    var actual = 0
    event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &actual, unicodeString: &buffer)
    guard actual > 0 else { return nil }
    return String(utf16CodeUnits: buffer, count: actual).first
}

/// 录制快捷键期间暂停/恢复全局事件监听
func setHotkeyTapEnabled(_ enabled: Bool) {
    guard let tap = globalEventTap else { return }
    CGEvent.tapEnable(tap: tap, enable: enabled)
}

func setupKeyboard() {
    log("Setting up keyboard...")
    
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                            (1 << CGEventType.flagsChanged.rawValue)
    
    let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            // 系统因超时/用户输入而禁用 tap 时自动恢复
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = globalEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let mods = Hotkey.mask(event.flags)
            
            if type == .flagsChanged {
                // 切换器显示时：呼出快捷键的全部修饰键被松开 = 确认选择
                if isVisible {
                    let showMods = SettingsManager.shared.showHotkey.modifiers
                    if (mods & showMods) != showMods {
                        DispatchQueue.main.async {
                            if isVisible { hideSwitcher() }
                        }
                    }
                }
            } else if type == .keyDown {
                let settings = SettingsManager.shared
                let show = settings.showHotkey
                let prev = settings.prevHotkey
                
                if mods != 0 || isVisible {
                    log("Tap keyDown keyCode=\(keyCode) mods=\(mods) show=\(show.modifiers)+\(show.keyCode) prev=\(prev.modifiers)+\(prev.keyCode)")
                }
                
                if mods == show.modifiers && keyCode == show.keyCode {
                    // 呼出/切换：未显示则呼出，显示中则下一个
                    DispatchQueue.main.async {
                        if isVisible { rotateNext() } else { showSwitcher() }
                    }
                    return nil
                } else if mods == show.modifiers,
                          let letter = cgEventLetter(event),
                          "a"..."z" ~= letter || "A"..."Z" ~= letter {
                    // 快速定位：按住呼出修饰键按字母 → 跳到该字母应用（同字母多个时右侧候选高亮，再按轮换）
                    if isVisible {
                        log("jump letter '\(letter)'")
                        let l = letter
                        DispatchQueue.main.async { jumpToLetter(l) }
                        return nil
                    }
                    // 未显示时是呼出修饰键的组合（非呼出键本身），让事件继续透传
                    return Unmanaged.passUnretained(event)
                } else if isVisible && mods == prev.modifiers && keyCode == prev.keyCode {
                    // 反向切换：上一个
                    DispatchQueue.main.async { rotatePrev() }
                    return nil
                } else if isVisible && mods == 0 && keyCode == Hotkey.escKeyCode {
                    // 切换器显示时单独按 Esc = 取消（不激活应用）
                    DispatchQueue.main.async {
                        if isVisible { hideSwitcher(activate: false) }
                    }
                    return nil
                }
            }
            
            return Unmanaged.passUnretained(event)
        },
        userInfo: nil
    )
    
    if let tap = tap {
        globalEventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("CGEvent tap OK")
    } else {
        log("CGEvent tap FAILED")
    }
}
