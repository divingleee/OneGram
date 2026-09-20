//
//  GenerateAppIcon.swift
//  OneGram
//
//  【开发脚本】把一张「透明底」的抓痕素材合成成完整的 macOS App 图标：
//  白色圆角底（留白 8%、圆角 22.37%、极浅灰描边）+ 居中缩放的素材。
//
//  为什么要加底：素材本身 87% 是透明的、可见部分又是深色，
//  直接当图标用，在深色模式的 Dock 上几乎看不见。
//  macOS 的 App 图标惯例也是「带底板」的圆角方块。
//
//  用法：
//      swift Scripts/GenerateAppIcon.swift <透明素材PNG> <输出目录>
//  例：
//      swift Scripts/GenerateAppIcon.swift \
//        ~/Downloads/macOS_AppIcon_Transparent_Bundle/icon_1024x1024_transparent.png \
//        OneGram/Assets.xcassets/AppIcon.appiconset
//

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift GenerateAppIcon.swift <透明素材PNG> <输出目录>")
    exit(1)
}
let srcPath = args[1]
let outDir = args[2]

guard let srcImage = NSImage(contentsOfFile: srcPath),
      let tiff = srcImage.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: tiff),
      let srcCG = srcRep.cgImage else {
    print("读不到素材: \(srcPath)")
    exit(1)
}

// ---- 1) 裁到素材的非透明包围盒，这样缩放时不会因为四周留白而变小 ----
let sw = srcRep.pixelsWide, sh = srcRep.pixelsHigh
var minX = sw, minY = sh, maxX = 0, maxY = 0
for y in 0..<sh {
    for x in 0..<sw where (srcRep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.06 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX > minX, maxY > minY else {
    print("素材是全透明的？")
    exit(1)
}
let side = max(maxX - minX, maxY - minY)
let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
let crop = CGRect(
    x: max(0, min(sw - side, cx - side / 2)),
    y: max(0, min(sh - side, cy - side / 2)),
    width: min(side, sw), height: min(side, sh)
)
guard let art = srcCG.cropping(to: crop) else { exit(1) }

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)

    // ---- 白色圆角底 ----
    let inset = size * 0.08
    let bgRect = canvas.insetBy(dx: inset, dy: inset)
    let radius = bgRect.width * 0.2237
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    NSColor.white.setFill()
    bg.fill()

    // 极浅灰描边：白色图标在浅色背景上也能看出轮廓
    NSColor(white: 0.86, alpha: 1).setStroke()
    bg.lineWidth = max(1, size * 0.012)
    bg.stroke()

    // ---- 把抓痕素材居中画上去（占底板 ~74%）----
    let artSide = bgRect.width * 0.74
    let artRect = NSRect(
        x: bgRect.midX - artSide / 2,
        y: bgRect.midY - artSide / 2,
        width: artSide,
        height: artSide
    )
    NSImage(cgImage: art, size: artRect.size).draw(in: artRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let targets: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for t in targets {
    let rep = renderIcon(size: CGFloat(t.px))
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(t.name))
    print("wrote \(t.name) (\(t.px)px)")
}
