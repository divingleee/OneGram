//
//  LaunchAtLogin.swift
//  TinyWatchdog
//
//  【Service 层】「登录时启动」开关的封装。
//
//  macOS 13 起官方推荐用 ServiceManagement 框架里的 SMAppService 来注册登录项，
//  不需要再手写 LaunchAgent plist，也不需要用已废弃的 SMLoginItemSetEnabled。
//
//  注意：
//   - 真实的开关状态以 SMAppService.mainApp.status 为准，不要自己用 UserDefaults 记，
//     否则用户在「系统设置 → 通用 → 登录项」里手动改了，界面就会显示错误。
//   - App 需要被正常签名；用 Xcode 直接 Run 时可以，命令行 CODE_SIGNING_ALLOWED=NO
//     构建出来的包可能注册失败，此时会把错误信息显示在设置窗口里。
//

import Combine            // ObservableObject / @Published
import ServiceManagement  // SMAppService
import SwiftUI            // Binding

@MainActor
final class LaunchAtLogin: ObservableObject {

    // 当前是否真的已经注册为登录项（只读，外部不能直接改）。
    @Published private(set) var isEnabled = false

    // 系统要求用户去「登录项」里手动允许（macOS 13+ 可能出现的状态）。
    @Published private(set) var needsApproval = false

    // 注册 / 注销失败时的错误提示。
    @Published private(set) var errorMessage: String?

    init() {
        // 初始化时先同步一次真实状态。
        refresh()
    }

    // 拨动开关时调用。
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                // 注册为登录项；重复注册不会报错。
                try SMAppService.mainApp.register()
            } else {
                // 取消登录项。
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            // 例如未签名、或没有权限，这里把系统给的错误信息显示出来。
            errorMessage = error.localizedDescription
        }

        // 无论成功失败，都重新读一次真实状态，保证界面和系统一致。
        refresh()
    }

    // 重新读取系统里的真实状态。
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    // 转成 SwiftUI 的 Toggle 能用的 Binding<Bool>。
    var binding: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isEnabled ?? false },
            set: { [weak self] in self?.setEnabled($0) }
        )
    }
}
