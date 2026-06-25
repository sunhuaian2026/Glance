import Foundation

enum BuiltInSmartFolders {

    /// All built-ins in display order. Slice A: 全部最近。Slice B-β: + 本周新增。
    /// M3.L: + 上个月 / 截图 / 大图。spec fixed order，sidebar 顶部按此顺序渲染。
    static let all: [SmartFolder] = [allRecent, thisWeekAdded, lastMonth, screenshots, largeImages]

    // MARK: - M3.L thresholds（domain semantics，不入 DS）

    /// 「大图」file_size 单值阈值：5 MB。spec v2-design §5.3 默认。
    private static let largeImageSizeThreshold: Int64 = 5_000_000
    /// 「大图」width / height AND 双值阈值：4000 px。spec v2-design §5.3 默认。
    private static let largeImageDimensionThreshold: Int64 = 4000
    /// 「截图」filename 关键字（macOS 桌面截图默认前缀 + 中文术语）。
    private static let screenshotFilenameKeyword1 = "Screenshot"
    private static let screenshotFilenameKeyword2 = "截图"

    static let allRecent: SmartFolder = SmartFolder(
        id: "all-recent",
        displayName: "全部最近",
        predicate: .and([
            .atom(.init(field: .managed, op: .eq, value: .bool(true))),
            .atom(.init(field: .hidden, op: .eq, value: .bool(false))),
            .atom(.init(field: .dedupCanonicalOrNull, op: .eq, value: .bool(true)))
        ]),
        sortBy: .birthTime,
        sortDescending: true,
        isBuiltIn: true
    )

    /// 「本周新增」— 最近 7 天内 birth_time 落入的图（滑动窗口，不是自然周）。
    /// 与 D4 时间分段段头"本周"（Calendar.firstDayOfWeek）双轨语义清晰：
    ///   - 此 SF：滑窗 -7d/now，跨自然周边界仍连续
    ///   - D4 段头：自然周边界 + 段标题文案
    static let thisWeekAdded: SmartFolder = SmartFolder(
        id: "this-week-added",
        displayName: "本周新增",
        predicate: .and([
            .atom(.init(field: .managed, op: .eq, value: .bool(true))),
            .atom(.init(field: .hidden, op: .eq, value: .bool(false))),
            .atom(.init(field: .dedupCanonicalOrNull, op: .eq, value: .bool(true))),
            .atom(.init(
                field: .birthTime,
                op: .betweenDuration,
                value: .relativeTimeRange(
                    start: thisWeekAddedWindowStart,
                    end: thisWeekAddedWindowEnd
                )
            ))
        ]),
        sortBy: .birthTime,
        sortDescending: true,
        isBuiltIn: true
    )

    /// 「本周新增」滑动窗口起点：往回数 7 天（resolveRelativeTime 解析 "-Nd" 格式，
    /// 见 SmartFolderQueryBuilder.swift:113）
    private static let thisWeekAddedWindowStart = "-7d"
    /// 滑动窗口终点：当前时刻（resolveRelativeTime 特殊 token）
    private static let thisWeekAddedWindowEnd = "now"

    // MARK: - M3.L: 上个月 / 截图 / 大图

    /// 「上个月」— 自然月边界（Calendar.current 算上月 1 日 00:00 → 本月 1 日 00:00-1s）。
    /// timezone 走 device local 跟 D4 时间分段同源。spec v2-design §5.3 / §6.1。
    static let lastMonth: SmartFolder = SmartFolder(
        id: "last-month",
        displayName: "上个月",
        predicate: .and([
            .atom(.init(field: .managed, op: .eq, value: .bool(true))),
            .atom(.init(field: .hidden, op: .eq, value: .bool(false))),
            .atom(.init(field: .dedupCanonicalOrNull, op: .eq, value: .bool(true))),
            .atom(.init(
                field: .birthTime,
                op: .betweenDuration,
                value: .relativeTimeRange(start: "last-month-start", end: "last-month-end")
            ))
        ]),
        sortBy: .birthTime,
        sortDescending: true,
        isBuiltIn: true
    )

    /// 「截图」— filename CONTAINS "Screenshot" OR "截图"。spec 的 path STARTS_WITH "~/Desktop"
    /// 分支本次不上（IndexStore 存 relative_path 跨 root 无法直判绝对路径，加 absolute_path 列
    /// 跟收益不平衡）。桌面截图绝大多数 filename 已带 "Screenshot" 前缀。
    static let screenshots: SmartFolder = SmartFolder(
        id: "screenshots",
        displayName: "截图",
        predicate: .and([
            .atom(.init(field: .managed, op: .eq, value: .bool(true))),
            .atom(.init(field: .hidden, op: .eq, value: .bool(false))),
            .atom(.init(field: .dedupCanonicalOrNull, op: .eq, value: .bool(true))),
            .or([
                .atom(.init(field: .filename, op: .contains, value: .string(screenshotFilenameKeyword1))),
                .atom(.init(field: .filename, op: .contains, value: .string(screenshotFilenameKeyword2)))
            ])
        ]),
        sortBy: .birthTime,
        sortDescending: true,
        isBuiltIn: true
    )

    /// 「大图」— file_size > 5MB OR (width > 4000 AND height > 4000)。spec v2-design §5.3。
    /// OR 内嵌 AND 是 D6 平铺二层结构（非嵌套），SmartFolderQueryBuilder 递归 emit 支持。
    static let largeImages: SmartFolder = SmartFolder(
        id: "large-images",
        displayName: "大图",
        predicate: .and([
            .atom(.init(field: .managed, op: .eq, value: .bool(true))),
            .atom(.init(field: .hidden, op: .eq, value: .bool(false))),
            .atom(.init(field: .dedupCanonicalOrNull, op: .eq, value: .bool(true))),
            .or([
                .atom(.init(field: .fileSize, op: .greaterThan, value: .int(largeImageSizeThreshold))),
                .and([
                    .atom(.init(field: .dimensionsWidth, op: .greaterThan, value: .int(largeImageDimensionThreshold))),
                    .atom(.init(field: .dimensionsHeight, op: .greaterThan, value: .int(largeImageDimensionThreshold)))
                ])
            ])
        ]),
        sortBy: .birthTime,
        sortDescending: true,
        isBuiltIn: true
    )
}
