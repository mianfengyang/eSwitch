# Changelog

All notable changes to CubeTab will be documented in this file.

---

## [Unreleased]

### Added
- **面板屏幕选择设置** — 在 `CubeTab → 设置...` 中新增「面板屏幕」选项，支持两种模式：
    - **主屏幕**（默认）— 面板始终出现在物理主显示器上，不受鼠标位置影响
    - **跟随光标所在屏** — 面板根据当前鼠标指针所在的显示器定位

### Changed
- `getTargetScreen()` helper — 使用 `NSScreen.screens.first`（固定主屏）替代 `NSScreen.main`（会随光标移动），确保「主屏幕」模式行为稳定
- `showSwitcher()` — 每次调用都重新获取目标屏幕并更新面板位置，不再受限于首次创建时的定位

---

## [1.3] - 2026-07-??
### Changed
- GPU优化 + 修复渲染问题

## [1.2] - 2026-??-??
### Added
- 界面缩小 + 顺时针白光流动动画
- 冰块立体视觉效果

## [1.1] - 2026-??-??
### Added
- UI增强 + 新功能

## [1.0] - 2026-??-??
### Added
- macOS 3D应用切换器 — Command+esc呼出，按住⌘键循环切换
