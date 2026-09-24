//
//  MenuBarTextColor.swift
//  OneGram
//
//  【Model 层】菜单栏文字颜色选项。
//  auto：跟随系统深浅色自动选黑 / 白；black / white：用户强制指定。
//  原始值（rawValue）会存进 UserDefaults。
//

import Foundation

enum MenuBarTextColor: String, CaseIterable, Identifiable {
    case auto
    case black
    case white

    var id: String { rawValue }

    // 展示给用户的中文名（偏好设置里用）。
    var title: String {
        switch self {
        case .auto:  return "自动"
        case .black: return "黑色"
        case .white: return "白色"
        }
    }
}
