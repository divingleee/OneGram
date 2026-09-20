//
//  NetworkCollector.swift
//  OneGram
//
//  【Service 层】负责采集网络上行 / 下行速率。
//
//  原理：系统为每块网卡维护「开机以来累计收发的字节数」。
//  速率 = (本次累计值 - 上次累计值) / 两次之间的秒数。
//  这里用系统接口 getifaddrs 直接读网卡数据，不启动任何子进程
//  （解析 netstat 命令那种做法要 fork 进程，开销大很多）。
//

import Darwin     // getifaddrs / if_data 等
import Foundation // Date、TimeInterval

final class NetworkCollector {

    // 一块网卡在上一次采样时的累计收发字节数。
    private struct Counters {
        var up: UInt32    // 已发送字节（上行）
        var down: UInt32  // 已接收字节（下行）
    }

    // 按网卡名字缓存上一次的值，例如 ["en0": ..., "utun0": ...]。
    private var previous: [String: Counters] = [:]

    // 上一次采样的时间点，用来算时间间隔。
    private var previousTime: TimeInterval?

    // 配置变化时清空基线，避免拿很久以前的数据算「速率」。
    func reset() {
        previous = [:]
        previousTime = nil
    }

    // 采样一次，返回 (上行字节/秒, 下行字节/秒)；第一次没有基线时返回 nil。
    func sample() -> (up: Double, down: Double)? {
        var current: [String: Counters] = [:]
        var upDelta: UInt64 = 0
        var downDelta: UInt64 = 0

        // getifaddrs 会分配一个链表，&ifaddr 是链表头指针（C 风格指针）。
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        // 有分配就要释放，defer 保证函数结束前一定调用。
        defer { freeifaddrs(ifaddr) }

        // 遍历链表：每个节点代表一块网卡的一条地址信息。
        var pointer = first
        while true {
            let interface = pointer.pointee  // pointee 表示「指针指向的内容」

            // 我们只关心 AF_LINK 类型（链路层统计，带收发包字节数），
            // 且需要有 ifa_data（统计数据）的网卡。
            if interface.ifa_name != nil,
               let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data {

                let name = String(cString: interface.ifa_name)

                // lo0 是本地回环（自己和自己通信），不算真实网络流量。
                if name != "lo0" {
                    // ifa_data 是 void*，用 assumingMemoryBound 告诉编译器它其实是 if_data 结构体。
                    let counters = data.assumingMemoryBound(to: if_data.self).pointee
                    let up = counters.ifi_obytes    // 累计发送字节
                    let down = counters.ifi_ibytes  // 累计接收字节

                    current[name] = Counters(up: up, down: down)

                    // 只有上一次也有这块网卡的数据时才能求差（新插上的网卡先跳过）。
                    if let last = previous[name] {
                        upDelta += Self.delta(current: up, previous: last.up)
                        downDelta += Self.delta(current: down, previous: last.down)
                    }
                }
            }

            // 移到链表下一个节点，没有就结束循环。
            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        // timeIntervalSinceReferenceDate 是从 2001-01-01 起算的秒数（Double）。
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = previousTime.map { now - $0 }  // 没有上次时间时是 nil
        let hadBaseline = elapsed != nil

        // 保存本次结果供下次使用。
        previous = current
        previousTime = now

        // 第一次运行没有基线，返回 nil；elapsed <= 0 说明时间异常，也返回 nil。
        guard hadBaseline, let elapsed, elapsed > 0 else { return nil }

        // 字节差 / 秒数 = 字节每秒。
        return (Double(upDelta) / elapsed, Double(downDelta) / elapsed)
    }

    // 网卡计数器是 32 位，万兆网卡下几秒就会「回绕」到 0。
    // 这里假设两次采样之间最多回绕一次，把差补回来。
    private static func delta(current: UInt32, previous: UInt32) -> UInt64 {
        if current >= previous {
            return UInt64(current - previous)
        }
        return UInt64(current) + (0x1_0000_0000 - UInt64(previous))
    }
}
