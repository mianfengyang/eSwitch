import AppKit

// MARK: - Status Bar
var statusItem: NSStatusItem?

/// 托盘图标：代码绘制的「中间卡片 + 双向箭头」模板图标，与新 App 图标同构，自动适配深浅菜单栏。
/// lockFocus 按屏幕 backing scale 渲染（Retina 自动 2x），矢量绘制 18pt 下锐利不糊。
func statusBarIconImage() -> NSImage {
    let s: CGFloat = 18
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    NSColor.white.setFill()

    // 中间圆角卡片（实心）
    let card = NSBezierPath(
        roundedRect: NSRect(x: 5.0, y: 5.0, width: 8.0, height: 8.0),
        xRadius: 2.0, yRadius: 2.0
    )
    card.fill()

    // 左侧左向箭头（杆在卡片背后，只露出头部）
    let leftArrow = NSBezierPath()
    leftArrow.move(to: NSPoint(x: 0.8, y: 9.0))          // 箭尖
    leftArrow.line(to: NSPoint(x: 3.6, y: 11.0))
    leftArrow.line(to: NSPoint(x: 3.6, y: 10.0))
    leftArrow.line(to: NSPoint(x: 5.0, y: 10.0))
    leftArrow.line(to: NSPoint(x: 5.0, y: 8.0))
    leftArrow.line(to: NSPoint(x: 3.6, y: 8.0))
    leftArrow.line(to: NSPoint(x: 3.6, y: 7.0))
    leftArrow.close()
    leftArrow.fill()

    // 右侧右向箭头（镜像）
    let rightArrow = NSBezierPath()
    rightArrow.move(to: NSPoint(x: 17.2, y: 9.0))        // 箭尖
    rightArrow.line(to: NSPoint(x: 14.4, y: 11.0))
    rightArrow.line(to: NSPoint(x: 14.4, y: 10.0))
    rightArrow.line(to: NSPoint(x: 13.0, y: 10.0))
    rightArrow.line(to: NSPoint(x: 13.0, y: 8.0))
    rightArrow.line(to: NSPoint(x: 14.4, y: 8.0))
    rightArrow.line(to: NSPoint(x: 14.4, y: 7.0))
    rightArrow.close()
    rightArrow.fill()

    img.unlockFocus()
    img.isTemplate = true  // 单色模板：深色菜单栏显示白色，浅色菜单栏显示黑色
    return img
}

func setupStatusBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.button?.image = statusBarIconImage()
    
    let menu = NSMenu()
    
    let titleItem = NSMenuItem(title: "eSwitch v1.4", action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    menu.addItem(titleItem)
    menu.addItem(NSMenuItem.separator())
    
    let settingsItem = NSMenuItem(title: "设置...", action: #selector(AppDelegate.showSettingsAction), keyEquivalent: ",")
    settingsItem.target = AppDelegate.shared
    menu.addItem(settingsItem)
    
    let accItem = NSMenuItem(title: "辅助功能权限", action: #selector(AppDelegate.checkAccessibility), keyEquivalent: "")
    accItem.target = AppDelegate.shared
    menu.addItem(accItem)
    
    menu.addItem(NSMenuItem.separator())
    
    let quitItem = NSMenuItem(title: "退出", action: #selector(AppDelegate.quit), keyEquivalent: "q")
    quitItem.target = AppDelegate.shared
    menu.addItem(quitItem)
    
    statusItem?.menu = menu
}
