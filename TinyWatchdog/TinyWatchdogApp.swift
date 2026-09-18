//
//  TinyWatchdogApp.swift
//  TinyWatchdog
//
//  这是整个 App 的「入口文件」。
//  Swift 程序从 @main 标记的类型开始执行，SwiftUI 里入口就是一个 App 类型。
//

import AppKit    // NSApplication / NSApplicationDelegate
import Combine   // 提供 ObservableObject / @Published（响应式数据）能力
import SwiftUI   // 提供界面与 App / Scene 等类型

// MARK: - AppDelegate（处理“启动完成后”这类 App 级事件）

// SwiftUI 的 App 生命周期里没有直接的“启动完成”回调，
// 但可以通过 NSApplicationDelegateAdaptor 塞一个传统的 AppKit 代理进来。
final class AppDelegate: NSObject, NSApplicationDelegate {

    // App 启动完成后执行：读取用户上次对 Dock 图标的选择并应用。
    // （初始形态由 Info.plist 的 LSUIElement 决定，运行时再用代码修正。）
    //
    // 注意：这里刻意不实现 applicationShouldHandleReopen。
    // 一旦自己接管窗口重开逻辑，容易和 SwiftUI 打开 Settings 窗口的行为打架，
    // 导致“偏好设置点了打不开”。
    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIconController.applySaved()
    }

    // 这是一个没有窗口的菜单栏 App，不需要保存/恢复窗口状态。
    // 关掉它可以避免 App 异常退出后，macOS 在下次启动时弹出
    // 「是否恢复窗口」的对话框——那个对话框会**卡住启动流程**，
    // 导致 applicationDidFinishLaunching 迟迟不执行。
    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool { false }
    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool { false }
}

// MARK: - App 入口

// @main 告诉系统：这里是程序启动点，整个项目只能有一个。
// 注意：@main 必须写成这种「属性」形式，不能只写在注释里。
@main
struct TinyWatchdogApp: App {

    // 把上面的 AppDelegate 接进 SwiftUI 生命周期。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // @StateObject = 由这个 App「自己持有」的对象，全生命周期只创建一次。
    // 数据变化时，用到它们的界面会自动刷新。
    @StateObject private var viewModel = MenuBarViewModel()
    @StateObject private var launchAtLogin = LaunchAtLogin()

    // body 描述这个 App 有哪些「场景（Scene）」。
    // Scene 不是普通界面，而是系统级窗口/菜单栏的声明。
    var body: some Scene {

        // MARK: 菜单栏图标（MenuBarExtra）
        // MenuBarExtra 会在 macOS 顶部菜单栏放一个图标：
        //   - 第一个闭包 { }  = 点击后弹出的下拉内容
        //   - label: 闭包      = 菜单栏上直接显示的图标与文字（常驻可见）
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel, settings: viewModel.settings)
        } label: {
            MenuBarLabelView(viewModel: viewModel, settings: viewModel.settings)
        }
        // .menuBarExtraStyle(.menu) 表示用「原生菜单」样式弹出，
        // 里面可以放 Toggle / Button，和系统菜单长得一样。
        .menuBarExtraStyle(.menu)

        // MARK: 偏好设置窗口（Settings）
        // Settings 是 macOS 原生首选项窗口：⌘, 或点击「偏好设置…」时出现。
        // 系统会自动记住它的位置，并且不会出现在 Dock / 程序切换里。
        Settings {
            SettingsView(settings: viewModel.settings, launchAtLogin: launchAtLogin)
        }
    }
}
