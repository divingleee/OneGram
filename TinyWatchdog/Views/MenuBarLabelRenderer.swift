//
//  MenuBarLabelRenderer.swift
//  TinyWatchdog
//
//  【View 层 / 绘制】把「指标数据」画成一张菜单栏用的图片。
//
//  样式（每个指标一列，共两行）：
//      19%      11%      75%      ↑ 1.2 K/s
//      CPU      GPU      MEM      ↓ 3.4 K/s
//  列与列之间是一条细竖线；上排是数值、下排是名称（网络是上行/下行速度）。
//
//  【垂直布局模型】
//  图片高度固定（imageHeight），内部去掉上下留白后的空间叫 availableHeight：
//      · 每列沿「分界线」按 upperToLowerRatio 切分成上块 / 下块；
//        上排文字「吸底」（底部贴着分界线 + topRowPadding），
//        下排文字「吸顶」（顶部贴着分界线 - bottomRowPadding）。
//  两行之间的空隙由 topPadding / bottomPadding 控制。
//
//  为什么把菜单栏内容画成一张图？
//  MenuBarExtra 的 label 只支持 Text / Image，装不下多行 + 任意布局，所以自绘。
//
//  图片是彩色图（左侧 App 图标带白色圆角底），因此 **不是模板图**；
//  文字颜色根据菜单栏深浅色（menuBarIsDark）自己选黑 / 白。
//
//  【性能设计】makeColumns（组装）→ measure（量尺寸）→ layout（算位置）→ render（画）。
//  两层缓存/复用：
//      1. 内容没变 → 复用上次的 NSImage（缓存键 = 各列文字 + 是否画图标 + 深浅色）；
//      2. App 图标只取一次。
//
//  ★ 想调整字体 / 大小 / 间距，只改下面「字体与布局配置」那一块即可。
//

import AppKit
import CoreText

@MainActor
enum MenuBarLabelRenderer {

    // MARK: - 字体与布局配置（要手动调样式，改这里）

    /// 上排数值字体：所有指标的数值（CPU/GPU/内存的百分比、网络的速率）。
    /// monospacedDigit = 等宽数字，数值跳动时宽度不会抖。
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    /// 下排名称字体：CPU / GPU / MEM / 上行 / 下行 这些文字。
    private static let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)

    /// ★ 网络模块上排（上行速度）字体。
    private static let networkUpFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    /// ★ 网络模块下排（下行速度）字体。
    private static let networkDownFont = NSFont.systemFont(ofSize: 8, weight: .medium)

    /// ★ 上块文字「吸底」：文字底部与分界线之间的留白（点）。调大 = 两行更松。
    private static let topRowPadding: CGFloat = 1

    /// ★ 下块文字「吸顶」：分界线与文字顶部之间的留白（点）。调大 = 两行更松。
    private static let bottomRowPadding: CGFloat = 1

    /// ★ 上块高度 : 下块高度的比例（普通指标列），这里就是 3:2。
    /// 每个指标的矩形内部沿垂直方向按 3:2 切分：上 3 份放数字、下 2 份放名称。
    private static let upperToLowerRatio: CGFloat = 3.0 / 2

    /// 列之间那条细竖线的宽度（点）。1 在 Retina 上就是 2 个像素，比较精致。
    private static let separatorLineWidth: CGFloat = 1

    /// ★ 竖线距离图片**顶部**的留白（点）。调大 = 竖线变短。
    private static let separatorTopPadding: CGFloat = 2

    /// ★ 竖线距离图片**底部**的留白（点）。调大 = 竖线变短。
    private static let separatorBottomPadding: CGFloat = 2

    /// ★ 图标和第一个指标之间的分隔线**是否显示**。
    private static let showsIconSeparator = true

    /// ★ 图标到「第一根分隔线 / 第一个指标」的距离（点）。调大 = 图标离得更远。
    private static let iconSeparatorGap: CGFloat = 6

    /// ★ 是否画出「上块 / 下块」的背景色，用来区分这两块区域。
    /// ⚠️ 打开后图片不再是模板图（`isTemplate = false`），颜色会原样保留，
    ///    因此不再跟随菜单栏的浅色 / 深色自动反色。只想看正常效果时设成 false。
    private static let showsBlockBackgrounds = true

    /// 上块（数字那一行）的背景色。用**不透明**的浅色：
    /// 半透明色叠在深色菜单栏上会变暗、黑字就看不清了。
    private static let upperBlockColor = NSColor(srgbRed: 0.74, green: 0.85, blue: 1.00, alpha: 1)

    /// 下块（名称那一行）的背景色。同样用不透明浅色。
    private static let lowerBlockColor = NSColor(srgbRed: 1.00, green: 0.76, blue: 0.76, alpha: 1)

    /// 小狗与第一列之间、以及文字与竖线之间的间距。
    private static let gap: CGFloat = 3

    /// 最左侧图标在菜单栏里的显示高度（点）。想更大 / 更小只改这一行。
    /// 注意：App 图标四周自带约 8% 的透明留白，所以「看得见的白底方块」
    /// 大约是这里的 84%（20pt → 约 17pt）。再想更大就要同时调大 imageHeight。
    private static let clawIconSize: CGFloat = 20

    /// 整张图片最左 / 最右 / 最上 / 最下的留白。
    private static let padding: CGFloat = 1
    private static let verticalPadding: CGFloat = 0

    /// ★ 图片的**固定高度**（点）。
    /// 设成固定值后，菜单栏这一块的高度不会随数值 / 指标变化而跳动。
    /// 内容（数字 + 名称 + 留白）会在这块高度里整体垂直居中。
    /// 只有当你把它设得太小、放不下文字时，才会自动撑到刚好放得下（避免被裁）。
    private static let imageHeight: CGFloat = 22

    /// ★ 每个指标列的**固定宽度**（点）。
    /// 固定宽度可以避免数值变化时菜单栏宽度抖动；31 刚好放下 "100%"。
    private static let metricColumnWidth: CGFloat = 31

    /// ★ 网络模块的固定宽度（点）。`0` = 不固定、按内容自适应。
    private static let networkColumnWidth: CGFloat = 0

    /// 菜单栏背景是不是深色。
    /// 图片不是模板图时（画了彩色背景 / 用了彩色图标），文字和图标就得自己挑颜色。
    private static var menuBarIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// 小狗图标和竖线的颜色：深色菜单栏用白，浅色菜单栏用黑。
    private static var inkColor: NSColor { menuBarIsDark ? .white : .black }

    /// 图标按 clawIconSize 缩放后的宽度（保持原图比例）。
    private static func iconWidth(_ image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return clawIconSize }
        return clawIconSize * image.size.width / image.size.height
    }

    // MARK: - 复用资源（只创建一次）

    /// 最左侧图标：直接用 App 图标（带白色圆角底的那套抓痕素材）。
    /// ⚠️ 它是彩色图、而且有白色底，所以整张标签不能再按模板图渲染，
    ///    否则会被系统压成一个纯色方块（白底变实心、抓痕看不见）。
    private static let clawImage: NSImage? = NSImage(named: NSImage.applicationIconName)

    /// 上一次渲染的「输入指纹」和结果，用来跳过无意义的重复绘制。
    private static var cachedKey: String?
    private static var cachedImage: NSImage?

    // MARK: - 内部数据结构

    /// 一列的「样式」：字体、宽度、留白、对齐方式等排版参数。
    /// 普通指标列和网络列各有一个，`Column` 只引用它，避免字段到处重复。
    private struct ColumnStyle {
        let topFont: NSFont
        let bottomFont: NSFont
        /// 固定宽度（点），0 = 按内容自适应。
        let columnWidth: CGFloat
        /// 上排文字「吸底」时与分界线的留白。
        let topPadding: CGFloat
        /// 下排文字「吸顶」时与分界线的留白。
        let bottomPadding: CGFloat
        /// 上块高度是下块高度的多少倍（3:2）。
        var upperToLowerRatio: CGFloat = 1
    }

    /// 一列的内容：上下两行文字 + 样式。
    private struct Column {
        let top: String
        let bottom: String
        let style: ColumnStyle
    }

    /// 量好尺寸后的一列：富文本 + 宽度 + 墨迹度量。
    private struct MeasuredColumn {
        let top: NSAttributedString
        let bottom: NSAttributedString
        let style: ColumnStyle

        let topWidth: CGFloat      // 上排文字的实际宽度
        let bottomWidth: CGFloat   // 下排文字的实际宽度
        let contentWidth: CGFloat  // 两行中较宽的那个（= 内容块宽度）
        let columnWidth: CGFloat   // 最终列宽 = max(固定宽度, 内容宽度)，防止被裁

        // ---- 墨迹度量（CoreText 按字形轮廓算，单位：点，统一用正数）----
        let topInkTop: CGFloat       // 上排文字在基线之上的高度
        let topInkBottom: CGFloat    // 上排文字在基线之下的深度（"/" 会比较大）
        let bottomInkTop: CGFloat    // 下排文字在基线之上的高度
        let bottomInkBottom: CGFloat // 下排文字在基线之下的深度

        /// 上排文字（含留白）最少需要的高度。
        var requiredUpper: CGFloat { style.topPadding + topInkBottom + topInkTop }
        /// 下排文字（含留白）最少需要的高度。
        var requiredLower: CGFloat { style.bottomPadding + bottomInkTop + bottomInkBottom }
    }

    /// 算好的「绘制指令」：位置都提前算好，绘制时只负责落笔。
    private struct DrawItem {
        let top: NSAttributedString
        let bottom: NSAttributedString
        /// 相对本列左边缘的 x 偏移（文字在矩形内水平居中）。
        let topDX: CGFloat
        let bottomDX: CGFloat
        /// 绝对 y（draw(at:) 用的是文字包围盒左下角）。
        let topY: CGFloat
        let bottomY: CGFloat
        let columnWidth: CGFloat
        /// 本列左边是否画竖线（第一列不画）。
        let hasSeparator: Bool
        /// 上块 / 下块的背景矩形（x 相对本列左边缘，y 是绝对坐标）。
        let upperBlockRect: NSRect
        let lowerBlockRect: NSRect
    }

    // MARK: - 生成图片（带缓存）

    /// 生成菜单栏图片。一定会返回一张图（最差情况是「只有图标」）。
    /// - Parameter showIcon: 是否绘制最左侧的图标（偏好设置里可关）。
    static func image(metrics: SystemMetrics, enabled: Set<MetricType>, showIcon: Bool = true, swapNetwork: Bool = false) -> NSImage {
        let columns = makeColumns(metrics: metrics, enabled: enabled, swapNetwork: swapNetwork)

        // 一个模块都没勾选时，即使用户关掉了「显示图标」也强制画图标：
        // 否则菜单栏上会变成一个没有任何内容的空白项，根本点不到。
        let drawIcon = showIcon || columns.isEmpty

        // 缓存命中：内容完全一样时，直接复用上次画好的图片。
        // 数值经常连续几次刷新都不变（比如 CPU 一直是 18%），这一步能省掉全部绘制开销。
        let key = cacheKey(for: columns, drawIcon: drawIcon) + (menuBarIsDark ? "#d" : "#l")
        if key == cachedKey, let cachedImage {
            return cachedImage
        }

        let image = render(columns: columns, drawIcon: drawIcon)
        cachedKey = key
        cachedImage = image
        return image
    }

    /// 输入指纹：把每列的文字和「是否画图标」拼起来。
    private static func cacheKey(for columns: [Column], drawIcon: Bool) -> String {
        var key = drawIcon ? "1" : "0"
        for column in columns {
            key += "|"
            key += column.top
            key += "/"
            key += column.bottom
        }
        return key
    }

    // MARK: - 渲染（测量 → 布局 → 绘制）

    private static func render(columns: [Column], drawIcon: Bool) -> NSImage {
        // 文字颜色：
        //  · 画了背景块 → 文字在浅色块上，固定黑色；
        //  · 没画背景块 → 文字直接贴在菜单栏上，跟随菜单栏深浅色。
        let textColor = showsBlockBackgrounds ? NSColor.black : inkColor
        let measured = measure(columns, textColor: textColor)

        // ---- 垂直布局：上下两块，中间一条分界线 ----
        // 为什么用 CoreText 的墨迹（字形轮廓）而不是 capHeight / ascender？
        //   · ↑↓ 箭头比 capHeight 还高一点；
        //   · "/" 这类字符会伸到基线以下。
        // 用字体自带的度量会让「吸底/吸顶」算不准，两行可能贴在一起。
        // 内容最少需要的高度：每一列都要放得下「上排 + 下排」，否则会裁字。
        let minimumHeight = ceil(
            verticalPadding * 2
            // 没有勾选任何指标时 measured 是空的，用 ?? 0 兜底（否则会崩）。
            + (measured.map { $0.requiredUpper + $0.requiredLower }.max() ?? 0)
        )
        // 用固定高度；只有固定值放不下时才自动撑高。
        let contentHeight = max(imageHeight, minimumHeight)
        // 每列可用的内部高度（去掉上下留白），各列再按自己的比例切分。
        let availableHeight = contentHeight - verticalPadding * 2

        // 指标之间分隔线的总占宽（左右各留 gap）。
        let separatorTotal = separatorLineWidth + gap * 2
        // 图标后第一根分隔线的总占宽（前面用 iconSeparatorGap，后面用 gap）。
        let firstSeparatorTotal = iconSeparatorGap + separatorLineWidth + gap

        // 图标。关掉「显示图标」时是 nil。
        let ink = inkColor
        let icon = drawIcon ? clawImage : nil

        // 图标和第一个指标之间是否画分隔线。
        let firstSeparator = (icon != nil) && showsIconSeparator && !measured.isEmpty

        // 先把所有绘制位置算好（水平偏移 + 基线 y），绘制闭包里就只剩画。
        let items = layout(measured, topInset: verticalPadding, availableHeight: availableHeight, firstSeparator: firstSeparator)

        // 计算总宽度。
        var totalWidth = padding * 2
        if let icon { totalWidth += iconWidth(icon) }
        for (index, item) in items.enumerated() {
            let isFirst = index == 0
            if item.hasSeparator {
                totalWidth += isFirst ? firstSeparatorTotal : separatorTotal
            } else if isFirst, icon != nil {
                // 没画分隔线时，图标和第一个指标之间也留一个间隔。
                totalWidth += iconSeparatorGap
            }
            totalWidth += item.columnWidth
        }
        totalWidth = ceil(totalWidth)

        // 竖线：从底部留白一直画到「图片高 - 顶部留白」。
        // 两个留白都是 0 时，竖线占满整张图片的高度。
        let lineY = separatorBottomPadding
        let lineHeight = max(0, contentHeight - separatorTopPadding - separatorBottomPadding)
        let image = NSImage(size: NSSize(width: totalWidth, height: contentHeight), flipped: false) { _ in
            ink.setFill()
            var x = padding

            // 1) 图标：在整张图片里垂直居中。
            if let icon {
                let w = iconWidth(icon)
                icon.draw(in: NSRect(
                    x: x,
                    y: (contentHeight - clawIconSize) / 2,
                    width: w,
                    height: clawIconSize
                ))
                x += w
            }

            // 2) 每个指标一列，列与列之间画一条细竖线。
            for (index, item) in items.enumerated() {
                let isFirst = index == 0
                if item.hasSeparator {
                    // 竖线从底部留白画到顶部留白处（见 separatorTopPadding / separatorBottomPadding）。
                    // 图标后第一根前面用 iconSeparatorGap，其余用 gap。
                    let leading = isFirst ? iconSeparatorGap : gap
                    ink.setFill()
                    NSBezierPath.fill(NSRect(
                        x: x + leading,
                        y: lineY,
                        width: separatorLineWidth,
                        height: lineHeight
                    ))
                    x += leading + separatorLineWidth + gap
                } else if isFirst, icon != nil {
                    // 没画分隔线时，图标和第一个指标之间也留一个间隔。
                    x += iconSeparatorGap
                }

                // 上块 / 下块的背景色（用来区分两块区域）。
                if showsBlockBackgrounds {
                    upperBlockColor.setFill()
                    NSBezierPath.fill(item.upperBlockRect.offsetBy(dx: x, dy: 0))
                    lowerBlockColor.setFill()
                    NSBezierPath.fill(item.lowerBlockRect.offsetBy(dx: x, dy: 0))
                }

                item.top.draw(at: NSPoint(x: x + item.topDX, y: item.topY))
                item.bottom.draw(at: NSPoint(x: x + item.bottomDX, y: item.bottomY))
                x += item.columnWidth
            }
            return true
        }

        // 模板图会丢掉颜色（只留形状），所以：
        //  · 画了彩色背景块 → 必须关掉；
        //  · 用了彩色的 App 图标（带白底）→ 也必须关掉，否则白底会变成实心方块。
        image.isTemplate = false
        return image
    }

    /// 把每列的文字转成富文本，并量出宽度和墨迹。
    private static func measure(_ columns: [Column], textColor: NSColor) -> [MeasuredColumn] {
        columns.map { column in
            let style = column.style
            let top = attributed(column.top, font: style.topFont, color: textColor)
            let bottom = attributed(column.bottom, font: style.bottomFont, color: textColor)

            let topMetrics = lineMetrics(of: top)
            let bottomMetrics = lineMetrics(of: bottom)

            return MeasuredColumn(
                top: top,
                bottom: bottom,
                style: style,
                topWidth: ceil(topMetrics.width),
                bottomWidth: ceil(bottomMetrics.width),
                contentWidth: max(ceil(topMetrics.width), ceil(bottomMetrics.width)),
                columnWidth: max(style.columnWidth, max(ceil(topMetrics.width), ceil(bottomMetrics.width))),
                topInkTop: topMetrics.inkTop,
                topInkBottom: topMetrics.inkBottom,
                bottomInkTop: bottomMetrics.inkTop,
                bottomInkBottom: bottomMetrics.inkBottom
            )
        }
    }

    /// 把测量结果换算成「绘制指令」：水平偏移 + 基线 y。
    /// - Parameters:
    ///   - topInset: 图片顶部留白（分界线从这里往下算）。
    ///   - availableHeight: 去掉上下留白后可用于摆放文字的内部高度。
    ///   - firstSeparator: 图标和第一个指标之间是否画分隔线。
    private static func layout(_ measured: [MeasuredColumn], topInset: CGFloat, availableHeight: CGFloat, firstSeparator: Bool) -> [DrawItem] {
        measured.enumerated().map { index, item in
            // 分界线位置（自下而上到「下排文字顶部」的距离）：
            // 按 upperToLowerRatio 切分（下块 = available / (1 + ratio)），
            // 再用「最少需要的高度」夹紧，保证任何比例下都不会把文字裁掉。
            let desiredLower = availableHeight / (1 + item.style.upperToLowerRatio)
            let lowerHeight = min(
                max(desiredLower, item.requiredLower),
                availableHeight - item.requiredUpper
            )
            let splitY = topInset + lowerHeight

            // 上排「吸底」：墨迹底部在分界线上方 topPadding 处。
            let topBaseline = splitY + item.style.topPadding + item.topInkBottom
            // 下排「吸顶」：墨迹顶部在分界线下方 bottomPadding 处。
            let bottomBaseline = splitY - item.style.bottomPadding - item.bottomInkTop

            return DrawItem(
                top: item.top,
                bottom: item.bottom,
                // 上下两行各自在矩形内水平居中。
                topDX: (item.columnWidth - item.topWidth) / 2,
                bottomDX: (item.columnWidth - item.bottomWidth) / 2,
                // draw(at:) 用的是文字包围盒左下角，所以要从基线往下挪一个 descender。
                topY: topBaseline + item.style.topFont.descender,
                bottomY: bottomBaseline + item.style.bottomFont.descender,
                columnWidth: item.columnWidth,
                hasSeparator: index > 0 || firstSeparator,
                // 背景矩形：按分界线切成「上块 / 下块」两块。
                upperBlockRect: NSRect(x: 0, y: splitY, width: item.columnWidth, height: availableHeight - lowerHeight),
                lowerBlockRect: NSRect(x: 0, y: splitY - lowerHeight, width: item.columnWidth, height: lowerHeight)
            )
        }
    }

    // MARK: - 字形测量（用同一个 CTLine 取宽度 + 墨迹）

    /// 用**同一个** CTLine 拿到宽度、基线上方墨迹、基线下方墨迹。
    /// 宽度用排版宽度（CTLineGetTypographicBounds），墨迹用字形轮廓（.useGlyphPathBounds），
    /// 这样 ↑↓ 箭头、"/" 这些特殊字形都能算准。
    private static func lineMetrics(of string: NSAttributedString) -> (width: CGFloat, inkTop: CGFloat, inkBottom: CGFloat) {
        guard string.length > 0 else { return (0, 0, 0) }
        let line = CTLineCreateWithAttributedString(string)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return (width, bounds.maxY, abs(bounds.minY))
    }

    /// 生成一段「带字体和颜色」的富文本。
    private static func attributed(_ string: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    // MARK: - 组装各列内容

    private static func makeColumns(metrics: SystemMetrics, enabled: Set<MetricType>, swapNetwork: Bool) -> [Column] {
        var columns: [Column] = []

        // 所有指标共用一套样式：数值大字在上、名称小字在下，按 3:2 切分、居中。
        let metricStyle = ColumnStyle(
            topFont: valueFont,
            bottomFont: labelFont,
            columnWidth: metricColumnWidth,
            topPadding: topRowPadding,
            bottomPadding: bottomRowPadding,
            upperToLowerRatio: upperToLowerRatio
        )

        // 网络模块单独的样式：上下行字体、宽度都能独立调，其余（留白、比例、居中）和指标一致。
        let networkStyle = ColumnStyle(
            topFont: networkUpFont,
            bottomFont: networkDownFont,
            columnWidth: networkColumnWidth,
            topPadding: topRowPadding,
            bottomPadding: bottomRowPadding,
            upperToLowerRatio: upperToLowerRatio
        )

        // CPU / GPU / 内存：百分比 + 名称。
        let percents: [(metric: MetricType, label: String, value: Double?)] = [
            (.cpu, "CPU", metrics.cpu),
            (.gpu, "GPU", metrics.gpu),
            (.memory, "MEM", metrics.memory),
        ]
        for entry in percents where enabled.contains(entry.metric) {
            columns.append(Column(
                top: MetricFormatter.percent(entry.value),
                bottom: entry.label,
                style: metricStyle
            ))
        }

        // 网络上行 / 下行：合并成**一个**模块，样式和其它指标一样（3:2 切分、居中）。
        // 上排显示上行速度、下排显示下行速度，速度前加箭头。
        // swapNetwork = true 时上下互换（下行在上、上行在下）。
        if enabled.contains(.network) {
            let upText = "↑ " + MetricFormatter.rate(metrics.upload)
            let downText = "↓ " + MetricFormatter.rate(metrics.download)
            columns.append(Column(
                top: swapNetwork ? downText : upText,
                bottom: swapNetwork ? upText : downText,
                style: networkStyle
            ))
        }

        return columns
    }
}
