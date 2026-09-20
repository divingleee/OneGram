//
//  MemoryCollector.swift
//  OneGram
//
//  【Service 层】负责采集内存使用率。
//
//  原理：向内核查询「内存页」的统计信息（host_statistics64），
//  再按页大小换算成字节。全程只是读取内核里已有的计数，不分配额外内存、不启动进程。
//

import Darwin     // mach 内核接口
import Foundation // ProcessInfo

final class MemoryCollector {

    private let host = mach_host_self()

    // 内核按「页」管理内存，需要知道一页多少字节（Apple Silicon 通常是 16KB）。
    private let pageSize = UInt64(vm_kernel_page_size)

    // 机器的物理内存总量，用来算百分比。
    private let totalMemory = ProcessInfo.processInfo.physicalMemory

    // 采样一次，返回 0.0 ~ 1.0 的内存占用率。
    func sample() -> Double? {
        guard totalMemory > 0 else { return nil }

        // vm_statistics64 是内核定义的结构体，用来接收统计结果。
        var stats = vm_statistics64()

        // C 接口要求传入「缓冲区能容纳多少个整数」，
        // 这里用结构体大小除以整数大小得到（相当于旧宏 HOST_VM_INFO64_COUNT）。
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        // host_statistics64 需要 integer_t 类型的缓冲区，
        // 所以用 withUnsafeMutablePointer + withMemoryRebound 把 &stats 临时「换个视角」传进去。
        // 这是 Swift 调用 C 接口时常见的写法，不必深究细节。
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(host, HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // 统计值是「页数」，乘以页大小换算成字节。
        let active = UInt64(stats.active_count) * pageSize       // 正在使用的内存
        let wired = UInt64(stats.wire_count) * pageSize          // 被系统锁住、不可换出的内存
        let compressed = UInt64(stats.compressor_page_count) * pageSize // 被压缩过的内存

        // `&+` 是「允许溢出的加法」，避免极端情况下崩溃。
        let used = active &+ wired &+ compressed

        // min(1.0, ...) 保证结果不超过 100%。
        return min(1.0, Double(used) / Double(totalMemory))
    }
}
