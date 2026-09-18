//
//  MenuBarContentView.swift
//  TinyWatchdog
//
//  【View 层】点击菜单栏图标后弹出的下拉菜单内容。
//
//  结构（自上而下）：
//    1. 一个「显示图标」开关 + 4 个指标开关（网络上下行合并为一个）
//    2. 一条分隔线
//    3. 「偏好设置」——倒数第二个按钮
//    4. 「退出」——最后一个按钮
//
//  这些内容会按照 SwiftUI 在「菜单」场景下的规则自动渲染成原生菜单项。
//

import AppKit   // NSApp（激活应用 / 退出）
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject var settings: AppSettings

    // 打开偏好设置窗口的系统动作（macOS 14+ 提供的环境值）。
    // 比 SettingsLink 更可控：可以先激活 App 再打开窗口。
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Section 会在菜单里显示一个分组标题。
        Section("菜单栏显示") {
            // 是否在菜单栏显示最左侧的图标（和偏好设置里那个开关是同一个值）。
            Toggle("显示图标", isOn: $settings.showMenuBarIcon)

            // ForEach 遍历全部指标，为每个生成一个开关。
            // MetricType 遵循了 Identifiable，SwiftUI 才知道怎么区分它们。
            ForEach(MetricType.allCases) { metric in
                // Toggle 在菜单里会显示成带勾选标记的菜单项。
                // isOn 需要一个 Binding<Bool>，由 settings 提供读写逻辑。
                Toggle(metric.title, isOn: settings.binding(for: metric))
            }
        }

        // 分隔线，把「开关」和「操作按钮」分成两组。
        Divider()

        // 打开偏好设置。
        // 关键：先 NSApp.activate() 把应用激活，再 openSettings()，
        // 否则 Settings 窗口可能创建在后台，看起来像“点了没反应”。
        Button {
            NSApp.activate()
            openSettings()
        } label: {
            Label("偏好设置", systemImage: "gearshape")
        }

        // 普通按钮：点击后调用 AppKit 的 NSApp.terminate 退出整个 App。
        // 菜单栏 App 没有窗口，没法像普通 App 那样关窗口退出，所以需要这个按钮。
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("退出", systemImage: "power")
        }
    }
}
