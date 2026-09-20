//
//  DockIconController.swift
//  OneGram
//
//  【Service 层】控制「是否在 Dock 中显示图标」。
//
//  原理：
//   - 应用启动时的初始形态由 Info.plist 的 LSUIElement 决定
//     （本项目在工程设置 INFOPLIST_KEY_LSUIElement 中配置，见 README）。
//   - 运行期间可以用 NSApplication.setActivationPolicy 随时切换：
//       .regular  = 普通应用，显示 Dock 图标、出现在 ⌘Tab 里
//       .accessory = 菜单栏工具，不显示 Dock 图标
//

import AppKit

// 用 enum + static 方法做「无实例的工具类」，不需要创建对象。
enum DockIconController {

    // 和 AppSettings 里使用的 UserDefaults key 保持一致。
    private static let storageKey = "showDockIcon"

    // 读取用户上次的选择并应用；App 启动完成时调用。
    static func applySaved() {
        // 没存过时默认「显示 Dock 图标」。
        let show = UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
        apply(show)
    }

    // 根据开关值切换激活策略。
    static func apply(_ show: Bool) {
        NSApplication.shared.setActivationPolicy(show ? .regular : .accessory)
    }
}
