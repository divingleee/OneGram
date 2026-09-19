//
//  MenuBarContentView.swift
//  TinyWatchdog
//
//  【View 层】点击菜单栏图标后弹出的内容。
//
//  用 `.window` 样式：这是一个普通的 SwiftUI 视图（popover），
//  不再是原生菜单，所以可以用任意布局和控件。
//
//  结构（自上而下）：
//    1. 「显示图标」+ 5 个指标开关
//    2. 分隔线
//    3. 「偏好设置」「退出」两个按钮
//

import AppKit   // NSApp（激活应用 / 退出）
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var settings: AppSettings

    // 打开偏好设置窗口的系统动作（macOS 14+ 提供的环境值）。
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 指标开关（开关在右侧）。
            MetricToggles(settings: settings, trailingSwitch: true)

            Divider()

            HStack(spacing: 12) {
                // 先激活 App 再打开设置窗口，否则窗口可能创建在后台。
                Button {
                    NSApp.activate()
                    openSettings()
                } label: {
                    Label("偏好设置", systemImage: "gearshape")
                }

                Spacer()

                // 菜单栏 App 没有窗口，必须显式退出。
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}
