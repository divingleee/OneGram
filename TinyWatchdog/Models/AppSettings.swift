//
//  AppSettings.swift
//  TinyWatchdog
//
//  【Model 层】用户偏好设置：显示哪些指标、多久刷新一次。
//  负责把设置存进 UserDefaults（macOS 自带的键值存储，退出 App 后仍然保留）。
//

import Combine    // ObservableObject / @Published
import Foundation // UserDefaults
import SwiftUI    // Binding

// @MainActor：这个类的代码只在「主线程」执行。
// 界面相关的状态都要求在主线程改动，这样能避免多线程竞争。
@MainActor
final class AppSettings: ObservableObject {

    /// 设置变化的原因。ViewModel 靠它区分「要不要重建采集基线」。
    enum Change {
        /// 勾选的指标集合变了。
        /// `added` = 这次**新打开**的指标，只有它们的采集基线需要重建；
        /// 其它指标的数据和基线都保留，所以不会突然变成 0。
        case metrics(added: Set<MetricType>)
        /// 只改了刷新间隔：数据、基线都保留，只换采样节奏。
        case interval
    }

    // 私有小枚举，集中存放 UserDefaults 的 key，
    // 避免写成魔法字符串，改的时候只改一处。
    private enum Key {
        static let metrics = "enabledMetrics"    // 勾选了哪些指标
        static let interval = "refreshInterval"  // 刷新间隔（秒）
        static let dockIcon = "showDockIcon"     // 是否在 Dock 中显示图标
        static let menuBarIcon = "showMenuBarIcon" // 是否在菜单栏显示小狗图标
    }

    // @Published：被它修饰的属性一旦变化，就会通知订阅它的界面刷新。
    // private(set)：外部只能读、不能直接改，必须走下面的方法，逻辑才能集中。
    @Published private(set) var enabledMetrics: Set<MetricType> {
        // didSet：属性被赋值后自动执行。
        didSet {
            // 新旧值一样就不做无谓的存储和重采样。
            guard enabledMetrics != oldValue else { return }
            persistMetrics()        // 存盘
            // 通知 ViewModel：只有「新打开」的那些指标需要重建基线
            onChange?(.metrics(added: enabledMetrics.subtracting(oldValue)))
        }
    }

    // 刷新间隔，单位秒。默认 2 秒，兼顾「看得见变化」和「省资源」。
    @Published var refreshInterval: Double {
        didSet {
            guard refreshInterval != oldValue else { return }
            defaults.set(refreshInterval, forKey: Key.interval)
            onChange?(.interval)    // 通知 ViewModel：只是间隔变了，不要清空数据
        }
    }

    // 是否在菜单栏显示最左侧的小狗图标。默认「显示」。
    // 只影响绘制（MenuBarLabelRenderer），和采样无关，所以不用触发 onChange。
    @Published var showMenuBarIcon: Bool {
        didSet {
            guard showMenuBarIcon != oldValue else { return }
            defaults.set(showMenuBarIcon, forKey: Key.menuBarIcon)
        }
    }

    // 是否在 Dock 中显示图标。默认「显示」。
    // 变化时立刻调用 DockIconController 切换激活策略，并写入 UserDefaults，
    // 下次启动时由 AppDelegate 读取并应用。
    @Published var showDockIcon: Bool {
        didSet {
            guard showDockIcon != oldValue else { return }
            defaults.set(showDockIcon, forKey: Key.dockIcon)
            DockIconController.apply(showDockIcon)
        }
    }

    // 设置变化时的回调。ViewModel 初始化时把自己的方法挂上来。
    // 参数说明变化原因（指标集合 or 刷新间隔），ViewModel 据此决定要不要清空数据。
    var onChange: ((Change) -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // 尝试读取上次保存的勾选项。
        if let stored = defaults.string(forKey: Key.metrics) {
            // 存的时候是 "cpu,memory" 这样的字符串，这里按逗号拆开还原成枚举集合。
            var metrics = Set(
                stored
                    .split(separator: ",")
                    .compactMap { MetricType(rawValue: String($0)) }
            )
            // 兼容旧版本：之前上行/下行曾合并成一个 network 开关，
            // 旧数据里出现过 network 就同时打开上行和下行。
            if stored.contains("network") {
                metrics.insert(.upload)
                metrics.insert(.download)
            }
            self.enabledMetrics = metrics
        } else {
            // 第一次运行：默认全部指标打开。
            self.enabledMetrics = Set(MetricType.allCases)
        }

        // double(forKey:) 在没存过时返回 0，所以用 > 0 判断，否则用默认 2 秒。
        let interval = defaults.double(forKey: Key.interval)
        self.refreshInterval = interval > 0 ? interval : 2.0

        // object(forKey:) 返回 Any?，转成 Bool 判断；没存过时默认 true（显示 Dock 图标）。
        self.showDockIcon = defaults.object(forKey: Key.dockIcon) as? Bool ?? true

        // 没存过时默认 true（菜单栏显示小狗图标）。
        self.showMenuBarIcon = defaults.object(forKey: Key.menuBarIcon) as? Bool ?? true
    }

    // 查询某个指标是否勾选。
    func isEnabled(_ metric: MetricType) -> Bool {
        enabledMetrics.contains(metric)
    }

    // 勾选 / 取消勾选某个指标。
    func setEnabled(_ enabled: Bool, for metric: MetricType) {
        if enabled {
            enabledMetrics.insert(metric)
        } else {
            enabledMetrics.remove(metric)
        }
    }

    // 给 SwiftUI 的 Toggle 用的「双向绑定」。
    // Toggle 需要 Binding<Bool>：读的时候调 get，拨动开关时调 set。
    // [weak self] 防止闭包强引用 self 造成内存无法释放。
    func binding(for metric: MetricType) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isEnabled(metric) ?? false },
            set: { [weak self] in self?.setEnabled($0, for: metric) }
        )
    }

    // 把勾选项以 "cpu,gpu,memory" 的形式存进 UserDefaults。
    private func persistMetrics() {
        let value = enabledMetrics
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        defaults.set(value, forKey: Key.metrics)
    }
}
