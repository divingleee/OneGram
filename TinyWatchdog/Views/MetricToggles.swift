//
//  MetricToggles.swift
//  TinyWatchdog
//
//  【View 层】「显示图标 + 4 个指标」这一组开关。
//  下拉菜单（MenuBarContentView）和偏好设置（SettingsView）都用它，
//  保证两处状态完全一致。
//
//  注意：这里只输出「内容」，不套外面的容器（VStack / Form Section），
//  由调用方决定排版。
//

import SwiftUI

struct MetricToggles: View {

    @ObservedObject var settings: AppSettings

    /// true = 开关固定在右侧。
    /// macOS 的 `.switch` 默认把开关画在**左侧**，和 iOS 相反；
    /// 下拉菜单里想要「文字在左、开关在右」就传 true。
    /// 偏好设置（Form）里系统自带右侧开关，传默认值 false 即可。
    var trailingSwitch: Bool = false

    var body: some View {
        Group {
            row("显示图标", $settings.showMenuBarIcon)
            ForEach(MetricType.allCases) { metric in
                row(metric.title, settings.binding(for: metric))
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ isOn: Binding<Bool>) -> some View {
        if trailingSwitch {
            // 手动排版：文字靠左、开关靠右。
            HStack {
                Text(title)
                Spacer()
                Toggle(title, isOn: isOn)   // 保留无障碍标签
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        } else {
            Toggle(title, isOn: isOn)
        }
    }
}
