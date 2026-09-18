//
//  CPUCollector.swift
//  TinyWatchdog
//
//  【Service 层】负责采集 CPU 使用率。
//
//  原理：macOS 内核会一直累加每个 CPU 核心在「用户态 / 系统态 / 空闲」等状态下的
//  时钟滴答数（tick，只增不减）。所以占用率不能用单次读数算，而是要：
//      占用率 = (本次总 tick - 上次总 tick) 中「非空闲」的比例
//  这里通过 host_processor_info 这个系统接口读取，属于内存级读取，开销极小。
//

import Darwin  // macOS 的底层 C 系统接口（mach 内核接口就在这里）

// final 表示这个类不能被继承，编译器可以做额外优化。
final class CPUCollector {

    // mach_host_self() 拿到「本机 host 端口」，读取系统信息都要用它。
    // 只取一次并保存，避免每次采样都重复申请系统资源。
    private let host = mach_host_self()

    // 上一次采样得到的 tick 数组，用来和本次做差。
    private var previous: [UInt32] = []

    // 配置变化时清空基线：下次采样还没有对比数据，会返回 nil，再下一次才准确。
    func reset() {
        previous = []
    }

    // 采样一次，返回 0.0 ~ 1.0 的占用率；数据不足（第一次）时返回 nil。
    // 注意返回值是 Double?（可选值），调用方需要处理 nil。
    func sample() -> Double? {
        // 这些是 C 接口要求的「输出参数」：先声明空变量，接口会把结果写进来。
        var cpuInfo: processor_info_array_t?          // 结果缓冲区（稍后必须手动释放）
        var infoCount: mach_msg_type_number_t = 0     // 缓冲区里有几个整数
        var cpuCount: natural_t = 0                   // 有几个 CPU 核心

        // 读取每个核心的 tick 计数。PROCESSOR_CPU_LOAD_INFO 表示要「各状态累计 tick」。
        let result = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &infoCount
        )
        // guard = 条件不成立就提前返回。这里同时把 cpuInfo 从可选值解包成非可选。
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }

        let ticks = Int(infoCount)

        // defer 里的代码会在函数返回前执行，用来释放系统分配的缓冲区。
        // 这类 C 接口分配的内存 ARC 不会自动回收，不释放就会内存泄漏。
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: UnsafeMutableRawPointer(cpuInfo)),
                vm_size_t(ticks) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        // 把 C 指针里的数据拷进 Swift 数组，方便后续使用。
        // 内核返回的是有符号整数，但实际是无符号计数，所以用 bitPattern 按位转换。
        var current = [UInt32](repeating: 0, count: ticks)
        for index in 0..<ticks {
            current[index] = UInt32(bitPattern: cpuInfo[index])
        }

        // 保存本次结果，供下一次做差；defer 保证返回前一定执行。
        defer { previous = current }

        // 第一次采样没有基线（previous 为空或长度不匹配），无法计算，先返回 nil。
        guard previous.count == ticks else { return nil }

        // 每个核心的数组里依次是 4 个状态：USER / SYSTEM / NICE / IDLE。
        let states = Int(CPU_STATE_MAX)
        var busy: UInt64 = 0   // 非空闲 tick 合计
        var total: UInt64 = 0  // 全部 tick 合计

        for cpu in 0..<Int(cpuCount) {
            // 第 cpu 个核心的数据从数组下标 cpu * 4 开始。
            let base = cpu * states

            // `&-` 是「允许溢出的减法」：tick 是 32 位计数，回绕时也不会崩溃。
            let user = UInt64(current[base + Int(CPU_STATE_USER)] &- previous[base + Int(CPU_STATE_USER)])
            let system = UInt64(current[base + Int(CPU_STATE_SYSTEM)] &- previous[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(current[base + Int(CPU_STATE_NICE)] &- previous[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(current[base + Int(CPU_STATE_IDLE)] &- previous[base + Int(CPU_STATE_IDLE)])

            busy += user + system + nice
            total += user + system + nice + idle
        }

        // 两次采样之间没有任何 tick 变化（间隔太短），避免除以 0。
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }
}
