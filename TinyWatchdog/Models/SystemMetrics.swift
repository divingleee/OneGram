//
//  SystemMetrics.swift
//  TinyWatchdog
//
//  【Model 层】一次采样得到的数据快照。
//  界面只读这个结构体，不关心数据是怎么采集来的。
//

import Foundation

// Equatable：让两个 SystemMetrics 可以比较是否相等（SwiftUI 用它判断要不要刷新界面）。
struct SystemMetrics: Equatable {
    // 类型后面加 `?` 表示「可选值（Optional）」，可能没有值（nil）。
    // 这里用可选的原因是：
    //   - 第一次采样只能拿到基线，还算不出占用率，所以暂时是 nil；
    //   - 某些机器没有 GPU 统计，也会一直是 nil。
    // 数值含义：cpu/gpu/memory 是 0.0 ~ 1.0 的占比；upload/download 是「字节/秒」。
    var cpu: Double?
    var gpu: Double?
    var memory: Double?
    var upload: Double?
    var download: Double?
}
