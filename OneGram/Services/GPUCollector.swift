//
//  GPUCollector.swift
//  OneGram
//
//  【Service 层】负责采集 GPU 使用率。
//
//  macOS 没有公开的简单 GPU 占用率接口，通用做法是：
//  通过 IOKit 找到显卡的 IOAccelerator 服务，读取它暴露的
//  PerformanceStatistics 字典，里面有系统算好的「Device Utilization %」。
//
//  性能考虑：查找服务需要遍历 IORegistry，比较慢，
//  所以找到后把句柄缓存起来重复使用，而不是每次采样都重新查找。
//
//  注意：读取 IOKit 需要关闭 App Sandbox（本项目已在工程设置里关闭）。
//

import Foundation
import IOKit  // IOKit 框架：访问硬件 / 驱动的注册表

final class GPUCollector {

    // io_object_t 就是系统服务对象的句柄；0 表示「还没有找到」。
    private var service: io_object_t = 0

    func reset() {
        releaseService()
    }

    // deinit 在对象被销毁时调用，确保句柄被释放（deinit 不需要 deinit() 写法）。
    deinit {
        releaseService()
    }

    // 采样一次，返回 0.0 ~ 1.0 的 GPU 占用率；不支持或读取失败时返回 nil。
    func sample() -> Double? {
        // 第一次调用时才去查找显卡服务，之后一直复用。
        if service == 0 {
            service = Self.findAccelerator()
        }
        guard service != 0 else { return nil }  // 这台机器没有可用的 IOAccelerator

        // 读取当前统计数据；读不到说明句柄失效（比如显卡切换），释放后下次重新找。
        guard let statistics = Self.performanceStatistics(of: service) else {
            releaseService()
            return nil
        }

        // 不同 GPU / 驱动暴露的 key 名字不完全一样，按优先级依次尝试。
        // as? Int 是「尝试转成整数」，失败会是 nil。
        for key in ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"] {
            if let value = statistics[key] as? Int {
                // 系统给的是 0~100，统一换算成 0~1，并用 min/max 夹紧防止越界。
                return min(1.0, max(0.0, Double(value) / 100.0))
            }
            if let value = statistics[key] as? Double {
                return min(1.0, max(0.0, value / 100.0))
            }
        }
        return nil
    }

    // 释放服务句柄，避免泄漏系统资源。
    private func releaseService() {
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }
    }

    // 在 IORegistry 里查找 IOAccelerator 服务，返回第一个带统计数据的那一个。
    private static func findAccelerator() -> io_object_t {
        var iterator: io_iterator_t = 0

        // IOServiceMatching 表示「按类名匹配」，IOAccelerator 是显卡加速器的通用类名。
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else { return 0 }
        // 迭代器本身也要释放。
        defer { IOObjectRelease(iterator) }

        var found: io_object_t = 0
        var entry = IOIteratorNext(iterator)  // 取第一个匹配项

        // 遍历所有匹配项，把用不到的立刻释放，避免资源泄漏。
        while entry != 0 {
            if found == 0, performanceStatistics(of: entry) != nil {
                found = entry  // 选中它，保留句柄
            } else {
                IOObjectRelease(entry)  // 用不到的直接释放
            }
            entry = IOIteratorNext(iterator)
        }
        return found
    }

    // 读取某个服务的 "PerformanceStatistics" 属性，转成 Swift 字典。
    private static func performanceStatistics(of service: io_object_t) -> [String: Any]? {
        // IORegistryEntryCreateCFProperty 返回的是 Core Foundation 对象。
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }

        // takeRetainedValue() 表示「我接管这个对象的所有权」，Swift 会自动管理内存。
        return property.takeRetainedValue() as? [String: Any]
    }
}
