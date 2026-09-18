//
//  MenuBarLabelRenderer.swift
//  TinyWatchdog
//
//  【View 层 / 绘制】把「指标数据」画成一张菜单栏用的图片。
//
//  样式参考（每个指标一列，共两行）：
//      19%      11%      75%      ↑ 3.1 K/s
//      CPU      GPU      MEM      ↓ 28.7 K/s
//  列与列之间是一条细竖线；上排是数值、下排是名称。
//
//  【垂直布局模型】把图片沿水平「分界线」切成上下两块：
//      · 上块：上排文字「吸底」——文字底部贴着分界线，中间留 topRowPadding；
//      · 下块：下排文字「吸顶」——文字顶部贴着分界线，中间留 bottomRowPadding。
//  两行之间的实际空隙 = topRowPadding + bottomRowPadding，改这两个值即可控制疏密。
//  网络列可以单独设置字体和上下 padding。
//
//  为什么要画图而不是直接用 SwiftUI 的 VStack？
//  MenuBarExtra 的 label 对复杂布局（多行、任意 Stack）支持有限，
//  最稳妥的做法是把它当成一张图片。
//
//  图片会被设成 template（模板），系统会按菜单栏深浅色自动上色，
//  所以这里统一用黑色绘制即可。
//
//  【性能设计】渲染分三步：makeColumns（组装文字）→ measure（量尺寸）→ render（画）。
//  并且做了三层缓存/复用，避免每次界面刷新都重复干活：
//      1. 文字内容没变 → 直接复用上次画好的 NSImage（缓存键 = 文字 + 是否显示图标）；
//      2. 小狗图标只创建一次（SF Symbol 查找和配置不便宜）；
//      3. 每段文字只创建一次 CoreText 行，同时读出上/下墨迹（原来创建两次）。
//
//  ★ 想调整菜单栏字体 / 大小 / 间距，只改下面「字体与布局配置」那一块即可。
//

import AppKit
import CoreText

@MainActor
enum MenuBarLabelRenderer {

    // MARK: - 字体与布局配置（要手动调样式，改这里）

    /// 上排数值字体：CPU / GPU / 内存的百分比数字。
    /// monospacedDigit = 等宽数字，数值跳动时宽度不会抖。
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    /// 下排名称字体：CPU / GPU / MEM 这些文字。
    private static let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)

    /// 网络专用字体：上行（↑）和下行（↓）**两行都用它**，所以大小天然一致。
    /// 想单独调网络的字号，只改这一行即可，不影响其它指标。
    private static let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)

    /// ★ 上块文字「吸底」：文字底部与分界线之间的留白（点）。调大 = 两行更松。
    private static let topRowPadding: CGFloat = 1

    /// ★ 下块文字「吸顶」：分界线与文字顶部之间的留白（点）。调大 = 两行更松。
    private static let bottomRowPadding: CGFloat = 1

    /// ★ 网络列单独的上留白（吸底）。
    private static let networkTopRowPadding: CGFloat = 0

    /// ★ 网络列单独的下留白（吸顶）。
    private static let networkBottomRowPadding: CGFloat = 0

    /// ★ 网络列文字距离**矩形左边框**的留白（点）。
    /// 网络列是左对齐的：文字从「矩形左边 + 这个留白」开始排，0 = 紧贴左边。
    private static let networkLeftPadding: CGFloat = 0

    /// ★ 上块高度 : 下块高度的比例（普通指标列），这里就是 3:2。
    /// 每个指标的矩形内部沿垂直方向按 3:2 切分：上 3 份放数字、下 2 份放名称。
    private static let upperToLowerRatio: CGFloat = 3.0 / 2

    /// ★ 网络列单独的比例（1 = 上下两块等高）。
    private static let networkUpperToLowerRatio: CGFloat = 1 / 1

    /// 列之间那条细竖线的宽度（点）。1 在 Retina 上就是 2 个像素，比较精致。
    private static let separatorLineWidth: CGFloat = 1

    /// ★ 竖线距离图片**顶部**的留白（点）。调大 = 竖线变短。
    private static let separatorTopPadding: CGFloat = 2

    /// ★ 竖线距离图片**底部**的留白（点）。调大 = 竖线变短。
    private static let separatorBottomPadding: CGFloat = 2

    /// ★ 是否画出「上块 / 下块」的背景色，用来区分这两块区域。
    /// ⚠️ 打开后图片不再是模板图（`isTemplate = false`），颜色会原样保留，
    ///    因此不再跟随菜单栏的浅色 / 深色自动反色。只想看正常效果时设成 false。
    private static let showsBlockBackgrounds = false

    /// 上块（数字那一行）的背景色。用**不透明**的浅色：
    /// 半透明色叠在深色菜单栏上会变暗、黑字就看不清了。
    private static let upperBlockColor = NSColor(srgbRed: 1, green: 4, blue: 1.00, alpha: 1)

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

    /// 垂直居中时的微调量（点）。
    /// CoreText 量出来的「墨迹」比实际渲染出来的会略高一点点，
    /// 直接按墨迹居中会看起来偏上，用这个值把整块往下压一点儿。
    private static let blockCenteringNudge: CGFloat = 0.75

    /// ★ 图片的**固定高度**（点）。
    /// 设成固定值后，菜单栏这一块的高度不会随数值 / 指标变化而跳动。
    /// 内容（数字 + 名称 + 留白）会在这块高度里整体垂直居中。
    /// 只有当你把它设得太小、放不下文字时，才会自动撑到刚好放得下（避免被裁）。
    private static let imageHeight: CGFloat = 22

    /// ★ 每个百分比指标（CPU / GPU / 内存）列的**固定宽度**（点）。
    /// 固定宽度可以避免数值变化时菜单栏宽度抖动；31 刚好放下 "100%"。
    private static let metricColumnWidth: CGFloat = 31

    /// ★ 网络列的**固定宽度**（点），比其它列宽一些，能放下 "↓ 1023 K/s"。
    /// ★ 网络列的固定宽度（点）。**设为 0 表示「不固定，按内容自适应」**：
    /// 数值短（如 "↑ 0.5 K/s"）列就窄，数值长（如 "↓ 1023 K/s"）列就宽。
    private static let networkColumnWidth: CGFloat = 52

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

    /// 一列的内容：上下两行文字、字体、宽度和对齐方式。
    /// 网络列的两行都用 `networkFont`，其余列上排用 `valueFont`、下排用 `labelFont`。
    private struct Column {
        let top: String
        let bottom: String
        let topFont: NSFont
        let bottomFont: NSFont
        /// 这一列的固定宽度（点）。
        let columnWidth: CGFloat
        /// 上排文字「吸底」时与分界线的留白。
        let topPadding: CGFloat
        /// 下排文字「吸顶」时与分界线的留白。
        let bottomPadding: CGFloat
        /// 上块高度是下块高度的多少倍（普通指标 3:2，网络 1:1）。
        let upperToLowerRatio: CGFloat
        /// true = 两行文字都靠左对齐（↑ 和 ↓ 对齐）；false = 每行各自在矩形内水平居中。
        var leftAligned: Bool = false
        /// true = 把「上下两行」当成一整块，在矩形里**垂直居中**（网络模块用）。
        /// false = 按 upperToLowerRatio 切分。
        var centersBlock: Bool = false
        /// 左对齐时，文字距离矩形左边框的留白（点）。居中时用不到。
        var leftPadding: CGFloat = 0
    }

    /// 量好尺寸后的一列：富文本 + 宽度 + 墨迹度量。
    private struct MeasuredColumn {
        let top: NSAttributedString
        let bottom: NSAttributedString
        let topFont: NSFont
        let bottomFont: NSFont
        let leftAligned: Bool
        let centersBlock: Bool
        let leftPadding: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
        /// 上块高度是下块高度的多少倍。
        let upperToLowerRatio: CGFloat

        let topWidth: CGFloat      // 上排文字的实际宽度
        let bottomWidth: CGFloat   // 下排文字的实际宽度
        let contentWidth: CGFloat  // 两行中较宽的那个（= 内容块宽度）
        let columnWidth: CGFloat   // 这一列的固定宽度（至少能放下内容，防止被裁）

        // ---- 墨迹度量（CoreText 按字形轮廓算，单位：点，统一用正数）----
        let topInkTop: CGFloat       // 上排文字在基线之上的高度
        let topInkBottom: CGFloat    // 上排文字在基线之下的深度（"/" 会比较大）
        let bottomInkTop: CGFloat    // 下排文字在基线之上的高度
        let bottomInkBottom: CGFloat // 下排文字在基线之下的深度

        /// 上排文字（含留白）最少需要的高度。
        var requiredUpper: CGFloat { topPadding + topInkBottom + topInkTop }
        /// 下排文字（含留白）最少需要的高度。
        var requiredLower: CGFloat { bottomPadding + bottomInkTop + bottomInkBottom }
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
    static func image(metrics: SystemMetrics, enabled: Set<MetricType>, showIcon: Bool = true) -> NSImage {
        let columns = makeColumns(metrics: metrics, enabled: enabled)

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

        // 竖线左右各留 gap 的空白。
        let separatorTotal = separatorLineWidth + gap * 2

        // 小狗图标。关掉「显示图标」时是 nil，宽度计算和绘制都会自动跳过它。
        // 画了背景色（非模板图）时，图标要自己染成和菜单栏对比的颜色。
        let ink = inkColor
        let icon = drawIcon ? clawImage : nil

        // 先把所有绘制位置算好（水平偏移 + 基线 y），绘制闭包里就只剩画。
        let items = layout(measured, topInset: verticalPadding, availableHeight: availableHeight)

        // 计算总宽度。
        var totalWidth = padding * 2
        if let icon {
            totalWidth += iconWidth(icon)
            // 后面还有指标列时才需要间隔；只有一个图标时不能加，否则右边会多出一块空白。
            if !items.isEmpty { totalWidth += gap }
        }
        for (index, item) in items.enumerated() {
            if index > 0 { totalWidth += separatorTotal }
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
                x += w + (items.isEmpty ? 0 : gap)
            }

            // 2) 每个指标一列，列与列之间画一条细竖线。
            for item in items {
                if item.hasSeparator {
                    // 竖线从底部留白画到顶部留白处（见 separatorTopPadding / separatorBottomPadding）。
                    ink.setFill()
                    NSBezierPath.fill(NSRect(
                        x: x + gap,
                        y: lineY,
                        width: separatorLineWidth,
                        height: lineHeight
                    ))
                    x += separatorTotal
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
            let top = attributed(column.top, font: column.topFont, color: textColor)
            let bottom = attributed(column.bottom, font: column.bottomFont, color: textColor)

            let topWidth = ceil(top.size().width)
            let bottomWidth = ceil(bottom.size().width)
            let contentWidth = max(topWidth, bottomWidth)
            // 每段文字只建一次 CoreText 行，同时取上、下两个墨迹值。
            let topInk = inkMetrics(of: top)
            let bottomInk = inkMetrics(of: bottom)

            return MeasuredColumn(
                top: top,
                bottom: bottom,
                topFont: column.topFont,
                bottomFont: column.bottomFont,
                leftAligned: column.leftAligned,
                centersBlock: column.centersBlock,
                leftPadding: column.leftPadding,
                topPadding: column.topPadding,
                bottomPadding: column.bottomPadding,
                upperToLowerRatio: column.upperToLowerRatio,
                topWidth: topWidth,
                bottomWidth: bottomWidth,
                contentWidth: contentWidth,
                columnWidth: max(column.columnWidth, contentWidth),
                topInkTop: topInk.top,
                topInkBottom: topInk.bottom,
                bottomInkTop: bottomInk.top,
                bottomInkBottom: bottomInk.bottom
            )
        }
    }

    /// 把测量结果换算成「绘制指令」：水平偏移 + 基线 y。
    /// - Parameters:
    ///   - topInset: 图片顶部留白（分界线从这里往下算）。
    ///   - availableHeight: 去掉上下留白后可用于摆放文字的内部高度。
    private static func layout(_ measured: [MeasuredColumn], topInset: CGFloat, availableHeight: CGFloat) -> [DrawItem] {
        measured.enumerated().map { index, item in
            // 分界线位置（自下而上到「下排文字顶部」的距离）：
            //  · centersBlock：把两行当成一整块垂直居中 → 上下剩余空白各一半；
            //  · 其它：按 upperToLowerRatio 切分（下块 = available / (1 + ratio)），
            //    再用「最少需要的高度」夹紧，保证任何比例下都不会把文字裁掉。
            let lowerHeight: CGFloat
            if item.centersBlock {
                let slack = max(0, availableHeight - item.requiredUpper - item.requiredLower)
                // 分界线往下挪 nudge → 整块跟着往下挪，抵消上面的测量误差
                lowerHeight = item.requiredLower + slack / 2 - blockCenteringNudge
            } else {
                let desiredLower = availableHeight / (1 + item.upperToLowerRatio)
                lowerHeight = min(
                    max(desiredLower, item.requiredLower),
                    availableHeight - item.requiredUpper
                )
            }
            let splitY = topInset + lowerHeight

            // 上排「吸底」：墨迹底部在分界线上方 topPadding 处。
            let topBaseline = splitY + item.topPadding + item.topInkBottom
            // 下排「吸顶」：墨迹顶部在分界线下方 bottomPadding 处。
            let bottomBaseline = splitY - item.bottomPadding - item.bottomInkTop

            // 水平位置：
            //  · 普通列：上下两行各自在矩形内水平居中；
            //  · 网络列（leftAligned）：两行左对齐（↑ 和 ↓ 对齐），
            //    整块从「矩形左边 + leftPadding」开始排。
            let blockX = item.leftAligned
                ? item.leftPadding
                : (item.columnWidth - item.contentWidth) / 2
            return DrawItem(
                top: item.top,
                bottom: item.bottom,
                topDX: item.leftAligned ? blockX : (item.columnWidth - item.topWidth) / 2,
                bottomDX: item.leftAligned ? blockX : (item.columnWidth - item.bottomWidth) / 2,
                // draw(at:) 用的是文字包围盒左下角，所以要从基线往下挪一个 descender。
                topY: topBaseline + item.topFont.descender,
                bottomY: bottomBaseline + item.bottomFont.descender,
                columnWidth: item.columnWidth,
                hasSeparator: index > 0,
                // 背景矩形：
                //  · centersBlock（网络）：整列就是**一个**矩形，铺满可用高度；
                //  · 其它：按分界线切成「上块 / 下块」两块。
                upperBlockRect: item.centersBlock
                    ? NSRect(x: 0, y: topInset, width: item.columnWidth, height: availableHeight)
                    : NSRect(x: 0, y: splitY, width: item.columnWidth, height: availableHeight - lowerHeight),
                lowerBlockRect: item.centersBlock
                    ? .zero
                    : NSRect(x: 0, y: splitY - lowerHeight, width: item.columnWidth, height: lowerHeight)
            )
        }
    }

    // MARK: - 字形墨迹测量（用于精确计算行间距）

    /// 一段文字在基线上方 / 下方的墨迹高度（都取正数）。
    /// 用 CoreText 的 `.useGlyphPathBounds` 按「字形轮廓」算，而不是按字体行高，
    /// 这样 ↑↓ 箭头、"/" 这些特殊字形都能算准。
    private static func inkMetrics(of string: NSAttributedString) -> (top: CGFloat, bottom: CGFloat) {
        guard string.length > 0 else { return (0, 0) }
        let line = CTLineCreateWithAttributedString(string)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return (bounds.maxY, abs(bounds.minY))
    }

    /// 生成一段「带字体和颜色」的富文本。
    private static func attributed(_ string: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    // MARK: - 组装各列内容

    private static func makeColumns(metrics: SystemMetrics, enabled: Set<MetricType>) -> [Column] {
        var columns: [Column] = []

        if enabled.contains(.cpu) {
            columns.append(Column(
                top: MetricFormatter.percent(metrics.cpu),
                bottom: "CPU",
                topFont: valueFont,
                bottomFont: labelFont,
                columnWidth: metricColumnWidth,
                topPadding: topRowPadding,
                bottomPadding: bottomRowPadding,
                upperToLowerRatio: upperToLowerRatio
            ))
        }
        if enabled.contains(.gpu) {
            columns.append(Column(
                top: MetricFormatter.percent(metrics.gpu),
                bottom: "GPU",
                topFont: valueFont,
                bottomFont: labelFont,
                columnWidth: metricColumnWidth,
                topPadding: topRowPadding,
                bottomPadding: bottomRowPadding,
                upperToLowerRatio: upperToLowerRatio
            ))
        }
        if enabled.contains(.memory) {
            columns.append(Column(
                top: MetricFormatter.percent(metrics.memory),
                bottom: "MEM",
                topFont: valueFont,
                bottomFont: labelFont,
                columnWidth: metricColumnWidth,
                topPadding: topRowPadding,
                bottomPadding: bottomRowPadding,
                upperToLowerRatio: upperToLowerRatio
            ))
        }

        // 网络上行、下行合成同一列：上行在上、下行在下。
        // 两行统一使用 networkFont，保证上下行字号完全一致。
        // 箭头后面留一个空格，和参考样式一致： "↑ 3.1 K/s"。
        // 上下留白用 network*Padding，可以单独调（不受其它指标影响）。
        if enabled.contains(.network) {
            // 上行、下行放在**同一个文本**里，用换行符 \n 分成两行。
            let text = "↑ " + MetricFormatter.rate(metrics.upload)
                + "\n"
                + "↓ " + MetricFormatter.rate(metrics.download)

            // 内部再按 \n 拆成两行分别排版：
            // 直接用「多行文本」绘制的话，行距只能用字体默认行高（10pt 字体约 12pt/行），
            // 两行加起来就超过菜单栏高度了；拆开后可以用 ink + padding 精确控制行距。
            let lines = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            columns.append(Column(
                top: lines.first ?? "",
                bottom: lines.count > 1 ? lines[1] : "",
                topFont: networkFont,
                bottomFont: networkFont,
                columnWidth: networkColumnWidth,
                topPadding: networkTopRowPadding,
                bottomPadding: networkBottomRowPadding,
                upperToLowerRatio: networkUpperToLowerRatio,
                leftAligned: true,
                centersBlock: true,
                leftPadding: networkLeftPadding
            ))
        }

        return columns
    }
}
