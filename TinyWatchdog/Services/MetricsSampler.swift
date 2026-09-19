//
//  MetricsSampler.swift
//  TinyWatchdog
//
//  【Service 层】采集调度器：把 4 个采集器组合起来，对外只暴露一个 sample 方法。
//
//  这是「省资源」的关键所在：只调用当前被勾选的指标对应的采集器，
//  没有勾选的指标完全不会触发任何系统调用。
//

import Foundation

// @MainActor：整个类在主线程运行，方便和界面状态安全地交互。
@MainActor
final class MetricsSampler {

    // 每种指标各有一个采集器对象。它们会记住上一次的读数（基线），
    // 所以必须长久持有、不能每次采样都新建。
    private let cpuCollector = CPUCollector()
    private let gpuCollector = GPUCollector()
    private let memoryCollector = MemoryCollector()
    private let networkCollector = NetworkCollector()

    /// 只重建指定指标的采样基线（用在「刚从关闭切成打开」的指标上），
    /// 其它指标完全不动，所以已经在显示的数值不会受影响。
    /// 重建基线的意义：避免用「跨越很久的两个采样点」算出一个没意义的平均值
    /// （计数器可能已经回绕多次）。
    func reset(_ metrics: Set<MetricType>) {
        if metrics.contains(.cpu) { cpuCollector.reset() }
        if metrics.contains(.gpu) { gpuCollector.reset() }
        if metrics.contains(.network) { networkCollector.reset() }
        // 内存占用率是一次性读取，没有基线，不需要重置。
    }

    // 按需采集：enabled 是用户当前勾选的指标集合。
    func sample(enabled: Set<MetricType>) -> SystemMetrics {
        var metrics = SystemMetrics()

        // `.contains(...)` 判断集合里有没有这个指标，没有就完全不碰对应采集器。
        if enabled.contains(.cpu) {
            metrics.cpu = cpuCollector.sample()
        }
        if enabled.contains(.gpu) {
            metrics.gpu = gpuCollector.sample()
        }
        if enabled.contains(.memory) {
            metrics.memory = memoryCollector.sample()
        }

        // 网络上下行是同一个开关，被勾选时一次读取同时拿到两个方向。
        if enabled.contains(.network) {
            let rates = networkCollector.sample()
            metrics.upload = rates?.up
            metrics.download = rates?.down
        }

        return metrics
    }
}
