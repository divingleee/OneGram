//
//  MenuBarLabelView.swift
//  OneGram
//
//  【View 层】菜单栏上常驻显示的内容。
//
//  真正的排版在 MenuBarLabelRenderer 里画成了一张图片，
//  这里只负责：数据变化时重新生成图片并交给 MenuBarExtra 显示。
//
//  为什么用 @ObservedObject？
//  标记为 @ObservedObject 的属性对象一旦发布变化，这个 View 就会重新构建，
//  菜单栏内容因此能实时刷新。
//

import SwiftUI

struct MenuBarLabelView: View {

    // viewModel 提供实时数据 metrics；settings 提供「哪些指标要显示」。
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        // 渲染器一定会返回一张图：
        //   · 有勾选指标 → 图标（可选）+ 两行指标；
        //   · 一个都没勾选 → 只画图标（即使「显示图标」关着也会画，
        //     否则菜单栏上会是个点不到的空白项）。
        //
        // 注意：**不要**加 .renderingMode(.template)。
        // 渲染器画出来的是彩色图（图标带白色圆角底），
        // 一旦按模板渲染就会被压成一个纯色方块、抓痕也看不见了。
        //
        // 另外也**不要**在这里直接用 App 图标（NSImage(named: .applicationIconName)）：
        // 它的原始尺寸是 512pt，不加约束会被 SwiftUI 按原尺寸塞进菜单栏。
        Image(nsImage: MenuBarLabelRenderer.image(
            metrics: viewModel.metrics,
            enabled: settings.enabledMetrics,
            showIcon: settings.showMenuBarIcon
        ))
    }
}
