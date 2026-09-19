//
//  MetricType.swift
//  TinyWatchdog
//
//  【Model 层】定义「指标」这个枚举。
//  枚举（enum）表示「一组固定取值」，这里就是 App 关心的 4 个可开关指标。
//  注意：网络的上行和下行是同一个开关，所以只有一个 case（网络）。
//

import Foundation

// String  : 每个枚举值背后都有一个字符串（rawValue），用来存进 UserDefaults。
// CaseIterable : 让编译器自动生成 allCases，可以遍历全部指标。
// Identifiable : 让它在 SwiftUI 的 ForEach 里能唯一标识自己（配合下面 id）。
enum MetricType: String, CaseIterable, Identifiable {
    case cpu        // CPU 使用率
    case gpu        // GPU 使用率
    case memory     // 内存使用率
    case network    // 网络上行 + 下行（合并成一个开关）

    // Identifiable 协议要求有 id；用 rawValue 当 id 最省事。
    var id: String { rawValue }

    // 展示给用户的中文名（下拉菜单、偏好设置里用）。
    var title: String {
        switch self {
        case .cpu:     return "CPU 使用率"
        case .gpu:     return "GPU 使用率"
        case .memory:  return "内存使用率"
        case .network: return "网络上行 / 下行"
        }
    }
}
