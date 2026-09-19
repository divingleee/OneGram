//
//  MenuBarLabelRenderer.swift
//  TinyWatchdog
//
//  【View 层 / 绘制】把「指标数据」画成一张菜单栏用的图片。
//
//  每个指标一列、共两行（上数值 / 下说明），列与列之间一条细竖线：
//
//      19%      11%      75%      1.5M     345K
//      CPU      GPU      MEM      UPLOAD   DOWN
//
//  为什么画成一张图：MenuBarExtra 的 label 只支持 Text / Image，装不下多行布局。
//
//  图片**不是**模板图（isTemplate = false）：左侧 App 图标是彩色图、带白色圆角底，
//  按模板渲染会被压成纯色方块，所以文字颜色按菜单栏深浅色自己选黑 / 白。
//
//  流程：makeColumns（组装文案）→ layout（测量 + 盒式布局，产出绝对坐标）→ draw（落笔）。
//  内容没变时直接复用上次的 NSImage（缓存键 = 各列文字 + 图标开关 + 深浅色）。
//
//  ★ 字体 / 大小 / 间距都在 Style.current 里调。
//

import AppKit

@MainActor
enum MenuBarLabelRenderer {

    // MARK: - 样式配置（要调样式只改这里）

    private struct Style {
        /// 数值字体：等宽数字，数值跳动时宽度不抖。
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let labelFont = NSFont.systemFont(ofSize: 6, weight: .medium)
        /// 网络两列的字体，默认与指标列一致（同字号才能协调）。
        let networkValueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let networkLabelFont = NSFont.systemFont(ofSize: 6, weight: .medium)

        /// 上块 : 下块的高度比。
        let metricUpperToLowerRatio: CGFloat = 3.0 / 1.5

        /// 网络列文字的水平对齐方式（left / center / right）。普通指标列固定居中。
        let networkAlignment = TextAlignment.center

        let separatorWidth: CGFloat = 1        // 1pt 在 Retina 上 = 2px
        let separatorTopPadding: CGFloat = 2   // 竖线距图片顶部的留白，调大 = 竖线变短
        let separatorBottomPadding: CGFloat = 2

        let showsIconSeparator = true          // 图标与第一列之间是否画分隔线
        let iconSeparatorGap: CGFloat = 6      // 图标到「第一根分隔线 / 第一列」的距离
        let gap: CGFloat = 3                   // 文字与竖线之间的间距

        let iconSize: CGFloat = 20             // 图标显示高度（素材自带 ~8% 透明边）
        let padding: CGFloat = 1               // 图片左右留白
        let verticalPadding: CGFloat = 0       // 图片上下留白

        /// 图片固定高度：菜单栏高度不随数值 / 指标变化而跳动；
        /// 只有放不下文字时才会自动撑高（见 minimumHeight）。
        let imageHeight: CGFloat = 22

        let metricColumnWidth: CGFloat = 35    // 刚好放下 "100%"
        let networkColumnWidth: CGFloat = 35    // 0 = 按内容自适应

        /// 调试用：给上 / 下两块涂色。打开后文字固定黑色、不再跟随深浅色。
        let showsBlockBackgrounds = false
        let upperBlockColor = NSColor(srgbRed: 0.74, green: 0.85, blue: 1.00, alpha: 1)
        let lowerBlockColor = NSColor(srgbRed: 1.00, green: 0.76, blue: 0.76, alpha: 1)

        static let current = Style()
    }
    private static let style = Style.current

    // MARK: - 通用取值

    /// 菜单栏是不是深色。图片不是模板图，文字和图标颜色要自己选黑 / 白。
    private static var menuBarIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
    private static var inkColor: NSColor { menuBarIsDark ? .white : .black }

    /// 图标按 iconSize 缩放后的宽度（保持原图比例）。
    private static func iconWidth(_ image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return style.iconSize }
        return style.iconSize * image.size.width / image.size.height
    }

    /// 一行文字「最少需要的高度」的保守估算（capHeight + 余量，↑ 比 capHeight 高一点）。
    /// 只用于 imageHeight 放不下时的安全兜底，不做精确排版。
    private static func rowNeed(font: NSFont, extra: CGFloat) -> CGFloat {
        font.capHeight + extra
    }

    /// 按对齐方式算出文字相对列左边缘的 x 偏移。
    private static func dx(for textWidth: CGFloat, columnWidth: CGFloat, alignment: TextAlignment) -> CGFloat {
        switch alignment {
        case .left:   return 0
        case .center: return (columnWidth - textWidth) / 2
        case .right:  return columnWidth - textWidth
        }
    }

    // MARK: - 数据模型

    /// 一列内文字的水平对齐方式。
    enum TextAlignment {
        case left, center, right
    }

    /// 一列的样式。宽度为 0 = 按内容自适应。
    private struct ColumnStyle {
        let topFont: NSFont
        let bottomFont: NSFont
        let columnWidth: CGFloat
        let upperToLowerRatio: CGFloat
        let textAlignment: TextAlignment
    }

    private struct Column {
        let top: String
        let bottom: String
        let style: ColumnStyle
    }

    private struct MeasuredColumn {
        let top: NSAttributedString
        let bottom: NSAttributedString
        let style: ColumnStyle
        let topSize: CGSize
        let bottomSize: CGSize
        let columnWidth: CGFloat   // max(固定宽度, 内容宽度)，防止裁字
    }

    /// 一列的绘制指令。坐标全部是图片里的绝对坐标。
    private struct ColumnDraw {
        let topText: NSAttributedString
        let bottomText: NSAttributedString
        let topOrigin: NSPoint
        let bottomOrigin: NSPoint
        let separatorRect: NSRect?      // nil = 本列左边不画竖线
        let upperBlockRect: NSRect
        let lowerBlockRect: NSRect
    }

    /// 一次布局的完整结果：图片尺寸 + 图标 + 所有列。
    private struct LayoutPlan {
        let size: NSSize
        let iconFrame: NSRect?
        let columns: [ColumnDraw]
    }

    // MARK: - 对外入口（带缓存）

    private static let clawImage = NSImage(named: NSImage.applicationIconName)
    private static var cachedKey: String?
    private static var cachedImage: NSImage?

    /// 生成菜单栏图片，一定会返回一张图。
    static func image(metrics: SystemMetrics, enabled: Set<MetricType>, showIcon: Bool = true) -> NSImage {
        let columns = makeColumns(metrics: metrics, enabled: enabled)
        // 一个指标都没勾选时，即使用户关掉了图标也强制画：否则菜单栏上是点不到的空白项。
        let drawIcon = showIcon || columns.isEmpty

        // 数值经常连续几次不变（如 CPU 一直是 18%），缓存能跳过全部绘制。
        let key = cacheKey(for: columns, drawIcon: drawIcon) + (menuBarIsDark ? "#d" : "#l")
        if key == cachedKey, let cachedImage {
            return cachedImage
        }

        let plan = layout(columns: columns, drawIcon: drawIcon)
        let image = draw(plan)
        cachedKey = key
        cachedImage = image
        return image
    }

    private static func cacheKey(for columns: [Column], drawIcon: Bool) -> String {
        (drawIcon ? "1" : "0") + columns.map { "|\($0.top)/\($0.bottom)" }.joined()
    }

    // MARK: - 布局（测量 → 盒式布局 → 单遍算出全部绝对坐标）

    private static func layout(columns: [Column], drawIcon: Bool) -> LayoutPlan {
        let textColor = style.showsBlockBackgrounds ? NSColor.black : inkColor
        let measured = columns.map { column -> MeasuredColumn in
            let top = attributed(column.top, font: column.style.topFont, color: textColor)
            let bottom = attributed(column.bottom, font: column.style.bottomFont, color: textColor)
            let contentWidth = max(top.size().width, bottom.size().width)
            return MeasuredColumn(
                top: top, bottom: bottom, style: column.style,
                topSize: top.size(), bottomSize: bottom.size(),
                columnWidth: max(column.style.columnWidth, contentWidth)
            )
        }

        // 高度：固定 imageHeight；只有装不下时才按「估算的最少高度」自动撑高。
        let minimumHeight = style.verticalPadding * 2
            + (measured.map { rowNeed(font: $0.style.topFont, extra: 3) + rowNeed(font: $0.style.bottomFont, extra: 2) }.max() ?? 0)
        let contentHeight = max(style.imageHeight, ceil(minimumHeight))
        let availableHeight = contentHeight - style.verticalPadding * 2

        // 竖线从底部留白一直画到「图片高 - 顶部留白」。
        let lineY = style.separatorBottomPadding
        let lineHeight = max(0, contentHeight - style.separatorTopPadding - style.separatorBottomPadding)

        let icon = drawIcon ? clawImage : nil
        let firstSeparator = icon != nil && style.showsIconSeparator && !measured.isEmpty

        // 单遍水平游标：一次算完所有绝对 x，总宽 = 游标终值。
        var x = style.padding
        var iconFrame: NSRect?
        if let icon {
            let w = iconWidth(icon)
            iconFrame = NSRect(x: x, y: (contentHeight - style.iconSize) / 2, width: w, height: style.iconSize)
            x += w
        }

        var draws: [ColumnDraw] = []
        for (index, m) in measured.enumerated() {
            let isFirst = index == 0

            // 竖线（第一列只在有图标时画）。
            var separatorRect: NSRect?
            if index > 0 || firstSeparator {
                let leading = isFirst ? style.iconSeparatorGap : style.gap
                separatorRect = NSRect(x: x + leading, y: lineY, width: style.separatorWidth, height: lineHeight)
                x += leading + style.separatorWidth + style.gap
            } else if isFirst, icon != nil {
                x += style.iconSeparatorGap   // 不画线时，图标与第一列之间也留个间隔
            }

            // 垂直：按比例切分上 / 下两块，再用「最少需要的高度」夹紧防裁字；
            // 两行文字各自在自己的块里居中。
            let lowerNeed = rowNeed(font: m.style.bottomFont, extra: 2)
            let upperNeed = rowNeed(font: m.style.topFont, extra: 3)
            let lowerHeight = min(
                max(availableHeight / (1 + m.style.upperToLowerRatio), lowerNeed),
                availableHeight - upperNeed
            )
            let splitY = style.verticalPadding + lowerHeight
            let upperHeight = availableHeight - lowerHeight

            // draw(at:) 的 y 是文字包围盒的左下角（unflipped 上下文）。
            // x 按列的对齐方式排（普通指标列固定居中，网络列可配）。
            let topDX = dx(for: m.topSize.width, columnWidth: m.columnWidth, alignment: m.style.textAlignment)
            let bottomDX = dx(for: m.bottomSize.width, columnWidth: m.columnWidth, alignment: m.style.textAlignment)
            let topOrigin = NSPoint(
                x: x + topDX,
                y: splitY + (upperHeight - m.topSize.height) / 2
            )
            let bottomOrigin = NSPoint(
                x: x + bottomDX,
                y: splitY - lowerHeight + (lowerHeight - m.bottomSize.height) / 2
            )

            draws.append(ColumnDraw(
                topText: m.top,
                bottomText: m.bottom,
                topOrigin: topOrigin,
                bottomOrigin: bottomOrigin,
                separatorRect: separatorRect,
                upperBlockRect: NSRect(x: x, y: splitY, width: m.columnWidth, height: upperHeight),
                lowerBlockRect: NSRect(x: x, y: splitY - lowerHeight, width: m.columnWidth, height: lowerHeight)
            ))
            x += m.columnWidth
        }

        return LayoutPlan(
            size: NSSize(width: ceil(x + style.padding), height: contentHeight),
            iconFrame: iconFrame,
            columns: draws
        )
    }

    // MARK: - 绘制（只落笔，不做任何计算）

    private static func draw(_ plan: LayoutPlan) -> NSImage {
        let image = NSImage(size: plan.size, flipped: false) { _ in
            if let frame = plan.iconFrame {
                clawImage?.draw(in: frame)
            }
            for column in plan.columns {
                if style.showsBlockBackgrounds {
                    style.upperBlockColor.setFill()
                    NSBezierPath.fill(column.upperBlockRect)
                    style.lowerBlockColor.setFill()
                    NSBezierPath.fill(column.lowerBlockRect)
                }
                column.topText.draw(at: column.topOrigin)
                column.bottomText.draw(at: column.bottomOrigin)
                if let rect = column.separatorRect {
                    inkColor.setFill()
                    NSBezierPath.fill(rect)
                }
            }
            return true
        }
        // 模板图会丢掉颜色（只留形状），彩色 App 图标（带白底）会被压成实心方块。
        image.isTemplate = false
        return image
    }

    // MARK: - 组装文案

    private static func attributed(_ string: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    private static func makeColumns(metrics: SystemMetrics, enabled: Set<MetricType>) -> [Column] {
        let metricStyle = ColumnStyle(
            topFont: style.valueFont, bottomFont: style.labelFont,
            columnWidth: style.metricColumnWidth,
            upperToLowerRatio: style.metricUpperToLowerRatio,
            textAlignment: .center
        )
        let networkStyle = ColumnStyle(
            topFont: style.networkValueFont, bottomFont: style.networkLabelFont,
            columnWidth: style.networkColumnWidth,
            upperToLowerRatio: style.metricUpperToLowerRatio,
            textAlignment: style.networkAlignment
        )

        var columns: [Column] = []
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

        // 网络拆成两列、独立开关，各列与指标列同构（数值 + 说明）。
        if enabled.contains(.upload) {
            columns.append(Column(
                top: MetricFormatter.rate(metrics.upload),
                bottom: "UPLOAD",
                style: networkStyle
            ))
        }
        if enabled.contains(.download) {
            columns.append(Column(
                top: MetricFormatter.rate(metrics.download),
                bottom: "DOWN",
                style: networkStyle
            ))
        }
        return columns
    }
}
