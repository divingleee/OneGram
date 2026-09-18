//
//  MetricFormatter.swift
//  TinyWatchdog
//
//  【工具】把原始数字格式化成菜单栏上简短好读的文字。
//  纯函数（输入相同、输出一定相同），方便单独测试和复用。
//
//  说明：没有数据（nil）时不再显示 "--"，而是按 0 显示。
//  原因是刚启动的那一两次采样还没拿到基线，显示 "--" 会闪一下，看起来像出错。
//

import Foundation

enum MetricFormatter {

    // 用「类型名.方法名」直接调用，所以方法都是 static（属于类型本身，不需要创建实例）。

    /// 把 0~1 的比例变成百分比文字。
    /// 例如：0.1234 -> "12%"；没有数据（nil）-> "0%"
    static func percent(_ value: Double?) -> String {
        // nil 按 0 处理，并夹紧到 0~1，避免出现负数或超过 100%。
        let ratio = min(max(value ?? 0, 0), 1)
        // 乘以 100，四舍五入后取整。\(...) 是字符串插值，把计算结果塞进文字里。
        return "\(Int((ratio * 100).rounded()))%"
    }

    /// 把「字节/秒」变成紧凑的速率文字，单位自动换档，**最小单位是 K/s**。
    /// 例如：0 -> "0.0 K/s"，512 -> "0.5 K/s"，1536 -> "1.5 K/s"，1572864 -> "1.5 M/s"
    /// 没有数据（nil）时按 0 显示："0.0 K/s"。
    /// 数字和单位之间有一个空格，和菜单栏里 "↑ 3.1 K/s" 的样式一致。
    static func rate(_ bytesPerSecond: Double?) -> String {
        // nil / 负数都按 0 处理。
        let bytes = max(bytesPerSecond ?? 0, 0)

        // 最小单位是 K，所以先把字节换算成 K；
        // 之后每满 1024 再进一档，单位最多到 T。
        let units = ["K", "M", "G", "T"]
        var value = bytes / 1024
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }

        // 数字大时（>=100）不显示小数，让菜单栏文字宽度稳定、不要跳来跳去。
        let decimals = value >= 100 ? 0 : 1

        // String(format:) 是类似 C 语言 printf 的格式化写法：
        // "%.1f" 表示保留 1 位小数，"%@" 表示插入一段字符串。
        // 数字和单位之间的空格就是格式串里的那个空格。
        return String(format: "%.\(decimals)f %@/s", value, units[index])
    }
}
