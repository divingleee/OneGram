//
//  MenuBarViewModel.swift
//  OneGram
//
//  【ViewModel 层】MVVM 里的 VM：连接「数据（Model/Service）」和「界面（View）」。
//
//  职责：
//   1. 持有采样结果 metrics，界面订阅它来显示；
//   2. 按设定的间隔循环采样；
//   3. 当设置变化时调整采样循环（两种情况都**保留已有数据**）：
//        - 指标集合变了 → 只重建「新打开」指标的基线，其它指标沿用上一次的值
//        - 只改刷新间隔 → 什么都不动，只换采样节奏
//
//  省资源设计：只用一个 Task 循环，而不是 Timer。
//  所有指标都关闭时，循环直接结束（return），CPU 占用降为零。
//

import Combine   // ObservableObject / @Published
import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {

    // @Published + private(set)：
    //   界面能订阅到变化，但只有 VM 内部能修改，保证数据来源唯一。
    @Published private(set) var metrics = SystemMetrics()

    // 用户设置（勾选项、刷新间隔）。View 也需要它来显示开关状态。
    let settings: AppSettings

    // 采集调度器（内部会记住采样基线）。
    private let sampler = MetricsSampler()

    // 当前正在运行的采样循环。Task 可以理解成「可以取消的异步任务」。
    private var loop: Task<Void, Never>?

    // 注意：参数默认值不能直接用 AppSettings()，
    // 因为默认参数在非主线程上下文求值，而 AppSettings 要求主线程。
    // 所以这里用可选值，进到初始化方法内部（主线程）再创建。
    init(settings: AppSettings? = nil) {
        let settings = settings ?? AppSettings()
        self.settings = settings

        // [weak self] 避免闭包强引用 self 导致内存泄漏：
        // 当 VM 应该被释放时，闭包里的 self 自动变成 nil。
        settings.onChange = { [weak self] change in
            self?.handle(change)
        }

        // 启动时先跑一次（此时本来也没有数据）。
        restartSampling()
    }

    // 设置变化时的处理。两种都「不清空数据」，避免关掉一个指标时
    // 其它指标的数值突然变成 0。
    private func handle(_ change: AppSettings.Change) {
        switch change {
        case .metrics(let added):
            // 只给「这次新打开」的指标重建基线：它下一轮采样还没对比数据，
            // 会先显示 0，再下一轮就是真实值。其它指标完全不受影响。
            if !added.isEmpty {
                sampler.reset(added)
            }
            restartSampling()
        case .interval:
            restartSampling()
        }
    }

    // 重启采样循环。注意：不会清空 metrics，也不会动已有基线。
    private func restartSampling() {
        // 先取消旧循环，防止出现两个循环同时采样。
        loop?.cancel()
        loop = nil

        // 一个指标都没勾选：不启动任何循环，彻底不消耗资源。
        guard !settings.enabledMetrics.isEmpty else { return }

        // 间隔最小 0.5 秒，防止用户设置得过小导致频繁采样。
        let interval = max(0.5, settings.refreshInterval)
        // Task.sleep 的单位是纳秒（1 秒 = 10 亿纳秒）。
        let nanoseconds = UInt64(interval * 1_000_000_000)

        // 创建一个异步循环任务。
        // 因为在 @MainActor 类里创建，Task 里的代码会自动在主线程执行。
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }  // VM 已释放就结束循环

                // 每次循环都重新读一遍勾选项，保证和用户设置实时同步。
                let enabled = self.settings.enabledMetrics
                let next = self.sampler.sample(enabled: enabled)
                // 数值和上次完全一样就不发布：SystemMetrics 是 Equatable，
                // 这样 SwiftUI 不会做无谓的界面刷新（菜单栏标签那边也能命中缓存）。
                if next != self.metrics {
                    self.metrics = next
                }

                // 睡一会儿再采下一次。Task.sleep 是可取消的：
                // 一旦循环被 cancel()，这里会立刻抛出并结束，不会白白等下去。
                // try? 表示忽略「被取消」这个错误。
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }
}
