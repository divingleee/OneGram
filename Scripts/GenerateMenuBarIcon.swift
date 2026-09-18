//
//  GenerateMenuBarIcon.swift
//  TinyWatchdog
//
//  ⚠️ 目前菜单栏图标直接用 App 图标（`NSImage(named: NSImage.applicationIconName)`），
//  **没有**使用 `MenuBarIcon` imageset，所以这个脚本暂时用不到，保留备用。
//
//  ⚠️ 如果要重新启用：macOS 的 imageset **只支持 1x / 2x**（不支持 3x），
//  多放一个 3x 会被 Xcode 报 "has an unassigned child" 警告。
//
//  【开发脚本】从一张方形透明 PNG 生成菜单栏用的 `MenuBarIcon` imageset。
//
//  为什么需要它：菜单栏图标只有 13~15pt，直接用整张 1024px 素材会显得又小又虚
//  （素材四周有大量透明留白）。这个脚本会：
//    1. 找到非透明像素的包围盒，裁成正方形（保留少量留白）；
//    2. 缩放到 13 / 26 / 39 px（1x / 2x / 3x）；
//    3. 把 alpha 二值化，边缘更「实」，小尺寸下不糊。
//
//  用法：
//      swift Scripts/GenerateMenuBarIcon.swift <源PNG> <输出目录>
//  例：
//      swift Scripts/GenerateMenuBarIcon.swift \
//        ~/Downloads/macOS_AppIcon_Transparent_Bundle/icon_1024x1024_transparent.png \
//        TinyWatchdog/Assets.xcassets/MenuBarIcon.imageset
//
//  生成后 imageset 的 Contents.json 需要包含这两个文件（1x / 2x）
//  （并建议设置 "template-rendering-intent" : "template"）。
//

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift GenerateMenuBarIcon.swift <源PNG> <输出目录>")
    exit(1)
}
let srcPath = args[1]
let outDir = args[2]

guard let img = NSImage(contentsOfFile: srcPath),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let cg = rep.cgImage else {
    print("读不到源图: \(srcPath)")
    exit(1)
}

// ---- 1) 找非透明像素的包围盒 ----
let w = rep.pixelsWide, h = rep.pixelsHigh
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.06 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX > minX, maxY > minY else {
    print("源图是全透明的？")
    exit(1)
}

// ---- 2) 以内容为中心裁成正方形（保持比例，不失真）----
let side = max(maxX - minX, maxY - minY) + 24
let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
let crop = CGRect(
    x: max(0, min(w - side, cx - side / 2)),
    y: max(0, min(h - side, cy - side / 2)),
    width: min(side, w),
    height: min(side, h)
)
guard let cropped = cg.cropping(to: crop) else { exit(1) }

func render(_ size: Int) -> NSBitmapImageRep {
    let r = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(cgImage: cropped, size: NSSize(width: size, height: size))
        .draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return r
}

/// alpha 二值化：>= 阈值就全不透明，否则全透明。小尺寸下边缘更干脆。
func thresholded(_ rep: NSBitmapImageRep, threshold: CGFloat = 0.5) -> NSBitmapImageRep {
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            let a = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
            rep.setColor(a >= threshold ? .black : .clear, atX: x, y: y)
        }
    }
    return rep
}

for (name, size) in [("menubar.png", 13), ("menubar@2x.png", 26)] {
    let r = thresholded(render(size))
    guard let data = r.representation(using: .png, properties: [:]) else { continue }
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    print("wrote \(name) (\(size)px)")
}
