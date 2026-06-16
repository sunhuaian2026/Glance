//
//  DesignSystem.swift
//  Glance
//
//  所有 UI 常量的唯一来源，遵循 specs/UI.md 规范。
//  使用方式：DS.Spacing.md、DS.Color.appBackground、DS.Anim.normal
//

import SwiftUI

enum DS {

    // MARK: - Spacing（8pt Grid）

    enum Spacing {
        /// 结构性无间距（VStack/HStack spacing: 0 等价语义）
        static let zero: CGFloat = 0
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Thumbnail

    enum Thumbnail {
        static let defaultSize: CGFloat = 180
        static let minSize: CGFloat = 80
        static let maxSize: CGFloat = 280
        static let spacing: CGFloat = 12
        static let cornerRadius: CGFloat = 8
    }

    // MARK: - Sidebar

    enum Sidebar {
        static let width: CGFloat = 220
        static let minWidth: CGFloat = 180
        static let maxWidth: CGFloat = 300
        static let rowHeight: CGFloat = 36
        static let rowPaddingH: CGFloat = 8
        static let iconSize: CGFloat = 16
        // 拖拽添加文件夹 drop target 高亮
        static let dropBorderWidth: CGFloat = 2
        static let dropBorderPadding: CGFloat = 4
        static let dropBorderCornerRadius: CGFloat = 10
        static let dropBorderOpacity: Double = 0.45
    }

    // MARK: - Viewer

    enum Viewer {
        static let filmstripHeight: CGFloat = 72
        static let filmstripThumbSize: CGFloat = 56
        // ImageIO 加载请求的最大像素尺寸（独立于 SwiftUI 渲染 frame，
        // 略大于 thumbSize 允许 retina 时不糊）。Int 类型对齐 loadThumbnail
        // 的 maxPixelSize 参数
        static let filmstripThumbLoadSize: Int = 80
        static let cardCornerRadius: CGFloat = 16
        static let cardPadding: CGFloat = 12
        // 缩放范围（QuickViewerViewModel 依赖）
        static let minZoom: CGFloat = 0.1
        static let maxZoom: CGFloat = 16.0
        // 原生 1:1 scale sentinel（视图不做任何变换，按图片原生像素尺寸呈现）
        static let nativeScale: CGFloat = 1.0
        // 适合窗口缩放：大图缩到窗口 fitPadding 占比，四周留呼吸边；小图 (≤ 窗口) 保 nativeScale 不上采样
        static let fitPadding: CGFloat = 0.9
        // 鼠标移动 / 切图后工具栏自动隐藏延迟（秒）。对齐 macOS Quick Look ~4s 节奏
        static let controlsAutoHideSeconds: Double = 4.0
    }

    // MARK: - About

    enum About {
        static let windowWidth: CGFloat = 320
        static let appIconSize: CGFloat = 96
        static let toastMaxWidth: CGFloat = 280
        static let toastDurationSeconds: TimeInterval = 1.5
    }

    // MARK: - Inspector

    enum Inspector {
        static let width: CGFloat = 260
        static let previewHeight: CGFloat = 120
        static let previewCornerRadius: CGFloat = 10
        // leading 边线宽度（macOS HiDPI 下 0.5pt = 1 物理像素，跟系统 separator 一致）
        static let separatorWidth: CGFloat = 0.5
    }

    // MARK: - Toolbar

    enum Toolbar {
        static let height: CGFloat = 44
        static let cornerRadius: CGFloat = 12
    }

    // MARK: - SectionHeader（V2 时间分段 chip）

    enum SectionHeader {
        // chip strokeBorder hairline — 现仅供进度/错误 chip（IndexingProgress / FeaturePrint / 错误 banner）复用；
        // 时间分段 chip 已改反色实底（chipFill/chipText），实底自带边界不再用 hairline。
        // 0.5pt 在 HiDPI 下对应 1 物理像素；opacity 0.12 跟系统 separator 视觉强度一致
        static let chipBorderWidth: CGFloat = 0.5
        static let chipBorderOpacity: Double = 0.12

        // 时间分段 chip 反色实底：dark 模式浅底 / light 模式深底，跟背景永远拉开整级明度差，
        // 解决同明度撞色（dark+dark / light+light）下半透明 material chip 边界糊的问题。
        // 参考 macOS Photos.app 日期 pill：告别 material 透感，用不透明实底。
        static let chipFill = AdaptiveColor(
            light: SwiftUI.Color(red: 0.30, green: 0.30, blue: 0.33),  // 中深灰实底，压浅色背景（比近黑收敛，克制不抢）
            dark:  SwiftUI.Color(red: 0.84, green: 0.84, blue: 0.86)   // 米白实底，压深色背景（比纯白收敛亮度/锐度）
        )
        static let chipText = AdaptiveColor(
            light: SwiftUI.Color(red: 0.97, green: 0.97, blue: 0.98),  // 浅字配深底
            dark:  SwiftUI.Color(red: 0.11, green: 0.11, blue: 0.13)   // 深字配浅底
        )
    }

    // MARK: - IndexingProgress（V2 Slice I.1 进度 chip + Slice I.2 错误 banner）

    enum IndexingProgress {
        /// SwiftUI ProgressView 默认 .controlSize(.small) 后再 70% 缩放，跟 chip 字号视觉协调
        static let spinnerScale: CGFloat = 0.7
        /// 错误 banner Capsule strokeBorder 强度（红色 hairline 比 SectionHeader chip 强一档让 banner 跳出）
        static let errorBorderOpacity: Double = 0.3
    }

    // MARK: - Similarity（V2 M2 Slice J — feature print 索引进度 chip）

    enum Similarity {
        /// fp 进度 chip 用紫色调（视觉与扫描进度区分；DS.Color.glowPrimary 系）
        static let chipAccent: SwiftUI.Color = .accentColor
        static let spinnerScale: CGFloat = 0.7
        /// D13 — 类似图查找返回的 top-N 数量。M2 写死 30，未来需要可调改 setting。
        static let topNResults: Int = 30
        /// FeaturePrintIndexer 单批 fetch 张数：SQLite IO + Vision 单线程吞吐折中
        static let indexerBatchSize: Int = 50
        /// EphemeralResultView 顶部关闭按钮的圆形容器尺寸
        static let closeButtonSize: CGFloat = 28
        /// EphemeralResultView 关闭按钮 + banner row 的背景透明度
        static let closeButtonBgOpacity: Double = 0.15
        static let bannerBgOpacity: Double = 0.08
        /// EphemeralResultView 空态图标 + 顶部留白
        static let emptyStateIconSize: CGFloat = 48
        static let emptyStateTopPadding: CGFloat = 80
        /// 中性灰背景色（EphemeralResultView close button 圆形 + banner row 背景）
        static let neutralOverlay: SwiftUI.Color = .gray
        /// QV 找类似按钮：unsupported 格式时 disabled / enabled 透明度
        static let buttonEnabledOpacity: Double = 1.0
        static let buttonDisabledOpacity: Double = 0.4
        /// K.2 — 瞬时 extractFailed 单图重试上限（同一 pipeline run 内）；
        /// 超过即标 supports=0 跳过避免无限 retry 同一坏文件。
        /// 跨 session 重置（per-pipeline-run，非持久化）— in-memory 实现见 FeaturePrintIndexer.runLoop
        static let extractRetryThreshold: Int = 3
    }

    // MARK: - Search（V2 M3 Slice M — 全局搜索 overlay）

    enum Search {
        /// SearchOverlayView 最大宽度（detail 区宽度受限于此 cap，居中显示）。
        static let overlayMaxWidth: CGFloat = 600
        /// overlay 内 padding（HStack search field + close button 上下左右）。
        static let overlayPadding: CGFloat = 12
        /// overlay 圆角半径。
        static let overlayCornerRadius: CGFloat = 12
        /// onChange debounce 毫秒数（200ms = Spotlight 同款节奏）。
        static let debounceMs: Int = 200
        /// modifier hint 行文字透明度（永远可见的教学行）。
        static let modifierHintOpacity: Double = 0.55
        /// overlay strokeBorder 透明度（hairline 边界）。
        static let overlayBorderOpacity: Double = 0.12
        /// overlay strokeBorder lineWidth（hairline）。
        static let overlayBorderWidth: CGFloat = 0.5
        // M3 chips
        static let chipSpacing: CGFloat = 8
        static let chipCornerRadius: CGFloat = 8
        static let chipHPadding: CGFloat = 10
        static let chipVPadding: CGFloat = 5
        static let chipSelectedOpacity: CGFloat = 0.18     // 选中态 accent 填充
        static let chipUnselectedOpacity: CGFloat = 0.12   // 未选 chip 背景填充
        static let chipStrokeOpacity: CGFloat = 0.5        // 选中态 accent 描边
        static let chipStrokeWidth: CGFloat = 1
        static let popoverMinWidth: CGFloat = 180
    }

    // MARK: - External Viewer（方向2 独立看图窗）

    enum ExternalViewer {
        /// 独立看图窗首次创建的默认尺寸（用户可 resize / 进全屏）。
        static let defaultWindowWidth: CGFloat = 1280
        static let defaultWindowHeight: CGFloat = 800
    }

    enum Settings {
        /// 方向2 Slice2：Settings scene 占位 view 尺寸（Glance 暂无设置项，最小占位）。
        static let placeholderWidth: CGFloat = 360
        static let placeholderHeight: CGFloat = 120
    }

    // MARK: - Animation

    enum Anim {
        static let fast   = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let normal = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let slow   = SwiftUI.Animation.easeInOut(duration: 0.35)
    }

    // MARK: - Color

    enum Color {
        // 背景层（AdaptiveColor，响应 SwiftUI per-view colorScheme 环境）
        static let appBackground  = AdaptiveColor(
            light: SwiftUI.Color(red: 0.95, green: 0.95, blue: 0.97),  // #F2F2F7
            dark:  SwiftUI.Color(red: 0.07, green: 0.07, blue: 0.09)   // #121217
        )
        static let gridBackground = AdaptiveColor(
            light: SwiftUI.Color.white,                                // #FFFFFF（内容区焦点，跟 Finder/Notes 一致）
            dark:  SwiftUI.Color(red: 0.08, green: 0.08, blue: 0.11)   // #141419
        )

        // 悬停/交互（AdaptiveColor）
        static let hoverOverlay   = AdaptiveColor(
            light: SwiftUI.Color.black.opacity(0.05),
            dark:  SwiftUI.Color.white.opacity(0.06)
        )
        static let separatorColor = AdaptiveColor(
            light: SwiftUI.Color.black.opacity(0.08),
            dark:  SwiftUI.Color.white.opacity(0.08)
        )

        // 环境光（Liquid Glass 光晕，两种模式均适用，保持 SwiftUI.Color）
        static let glowPrimary    = SwiftUI.Color(red: 0.49, green: 0.42, blue: 1.0)  // 紫
        static let glowSecondary  = SwiftUI.Color(red: 0.2,  green: 0.6,  blue: 0.5)  // 青绿

        // 次级文本（标题之外的描述/版本号/copyright 等），alias 到 SwiftUI 标准
        // 语义色 .secondary，自动响应 colorScheme
        static let secondaryText: SwiftUI.Color = .secondary

        // 错误状态色（V2 Slice I.2 banner / Slice H 失败 chip 等），alias 到 SwiftUI .red
        // 语义色，dark/light 自动适配（macOS standard error red）
        static let errorAccent: SwiftUI.Color = .red
    }

    // MARK: - M4 重复清理总览专属常量

    /// M4 — 重复清理总览专属常量（任务 1 只读 UI 用；任务 2 加删除按钮 / 进度配色再补）。
    enum Dedup {
        /// model bridge observer debounce — 后台索引活动激增（FSEvents batch / dedup full pass 完成）
        /// 时频繁 fire，500ms debounce 后 reload 避免抖动；UI 实际感知接近实时。
        static let reloadDebounceMillis: Int = 500
        /// 组与组之间的垂直间距（LazyVStack spacing）
        static let groupRowSpacing: CGFloat = DS.Spacing.lg
        /// 组内缩略图渲染尺寸（保留张 + 副本展示位）
        static let groupCellThumbnailSize: CGFloat = 96
        /// loadThumbnail 请求的最大像素（高 DPI 屏 Retina 缩放）；类型 Int 对齐 loadThumbnail(maxPixelSize: Int) 签名
        static let groupCellThumbnailMaxPixel: Int = 192
        /// 保留张 badge 文字 / 边框配色（绿系，accent 提示「这张留下」D28）
        /// SwiftUI.Color 全限定：enum DS 内嵌套 enum Color 不含 SwiftUI 系统色，必须显式 namespace
        static let canonicalBadgeColor: SwiftUI.Color = .green
        /// 顶部统计条字号（mirror IndexingProgressView caption 风格）
        static let statsBarFont: Font = .body.weight(.semibold)
        /// 空态字号
        static let emptyStateFont: Font = .body
        /// 副本相对保留张的视觉弱化 opacity
        static let duplicateThumbnailOpacity: Double = 0.7
    }

    // MARK: - Icons（SF Symbols）

    enum Icon {
        static let folder     = "folder"
        static let album      = "photo.on.rectangle"
        static let add        = "plus"
        static let trash      = "trash"
        static let favorite   = "heart"
        static let search     = "magnifyingglass"
        static let previous   = "arrow.left"
        static let next       = "arrow.right"
        static let fullscreen = "arrow.up.left.and.arrow.down.right"
        static let info       = "info.circle"
        static let infoFilled = "info.circle.fill"
        static let close      = "xmark"
    }
}

// MARK: - AdaptiveColor
// 通过 ShapeStyle.resolve(in:) 从 EnvironmentValues 读取 colorScheme，
// 正确响应 SwiftUI per-view preferredColorScheme 覆盖（如 QuickViewerOverlay 的强制深色）。

struct AdaptiveColor: ShapeStyle, View {
    let light: SwiftUI.Color
    let dark: SwiftUI.Color

    /// ShapeStyle 路径：由 SwiftUI 渲染时注入完整 EnvironmentValues，colorScheme 已反映视图级覆盖
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.colorScheme == .dark ? dark : light
    }

    /// View 路径：通过独立 View 读取 @Environment(\.colorScheme)，供 .ignoresSafeArea() 等 View 修饰符使用
    var body: some View {
        _AdaptiveColorBody(light: light, dark: dark)
    }
}

private struct _AdaptiveColorBody: View {
    let light: SwiftUI.Color
    let dark: SwiftUI.Color
    @Environment(\.colorScheme) private var colorScheme
    var body: some View { colorScheme == .dark ? dark : light }
}
