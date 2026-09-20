//
//  SettingsView.swift
//  OneGram
//
//  【View 层】偏好设置窗口（macOS 原生首选项窗口）的内容。
//  由 OneGramApp.swift 里的 Settings 场景负责显示。
//
//  功能与下拉菜单一致：勾选要显示的指标、设置刷新间隔，
//  另外还有「登录时启动」「在 Dock 中显示图标」两个通用开关。
//  因为到处共用同一份 settings / launchAtLogin 数据，所以改哪边都会同步。
//

import SwiftUI

struct SettingsView: View {

    // @ObservedObject：对象变化时这个界面会自动刷新。
    @ObservedObject var settings: AppSettings
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        // Form 是 macOS 设置界面的标准容器，
        // 会自动按「标签 - 控件」的样式排版。
        Form {
            Section("菜单栏显示") {
                // 「显示图标 + 5 个指标」开关，和下拉菜单共用同一份。
                MetricToggles(settings: settings)
            }

            Section("采样") {
                // Picker 是下拉选择器；$settings.refreshInterval 前面的
                // `$` 表示「双向绑定」：既显示当前值，选择后也会写回 settings。
                // .tag(...) 里的值和 refreshInterval 类型一致（Double），才能对应上。
                Picker("刷新间隔", selection: $settings.refreshInterval) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("3 秒").tag(3.0)
                    Text("5 秒").tag(5.0)
                }
                // .inline 让选项直接平铺显示，而不是收进下拉框。
                .pickerStyle(.inline)

                // 一句说明文字，解释「关闭全部指标 = 不采样」，方便理解省资源的设计。
                Text("只采集已勾选的指标；全部关闭时应用不做任何采样。")
                    .font(.footnote)               // 小号字
                    .foregroundStyle(.secondary)   // 次要文字颜色（灰色）
            }

            Section("通用") {
                // 登录时启动：真实状态由系统（SMAppService）决定，不自己记 UserDefaults。
                Toggle("登录时启动", isOn: launchAtLogin.binding)

                // 如果系统要求用户手动允许，给一句提示。
                if launchAtLogin.needsApproval {
                    Text("请到「系统设置 → 通用 → 登录项」中允许 OneGram。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // 注册失败时（例如未签名的开发构建）把系统错误显示出来。
                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                // 在 Dock 中显示图标：立即切换 NSApplication 的激活策略并持久化。
                Toggle("在 Dock 中显示图标", isOn: $settings.showDockIcon)

                Text("关闭后本应用只保留菜单栏图标，不占用 Dock 和 ⌘Tab。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        // 分组式表单样式，是 macOS 设置窗口的经典外观。
        .formStyle(.grouped)
        // fixedSize + frame(width:) 让窗口宽度固定、高度随内容自适应。
        .frame(width: 380)
        .fixedSize()
    }
}
