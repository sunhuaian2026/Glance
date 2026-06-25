//
//  TimeBucket.swift
//  Glance
//
//  D4 时间分段算法（spec v2-design 5.3 §228-246）：
//  5 段固定 — 今天 / 昨天 / 本周 / 本月 / 更早。
//  Calendar.startOfDay 严格午夜对齐；时区 device-local（不做 UTC 归一化）。
//

import Foundation

enum TimeBucket: Int, CaseIterable, Identifiable {
    case today      = 0
    case yesterday  = 1
    case thisWeek   = 2
    case thisMonth  = 3
    case earlier    = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .today:     return "今天"
        case .yesterday: return "昨天"
        case .thisWeek:  return "本周"
        case .thisMonth: return "本月"
        case .earlier:   return "更早"
        }
    }

    /// 各 bucket 起点边界（device-local timezone）。
    struct Boundaries {
        let today: Date
        let yesterday: Date
        let thisWeek: Date
        let thisMonth: Date
    }

    static func boundaries(now: Date, calendar: Calendar = .current) -> Boundaries {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let weekComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let thisWeek = calendar.date(from: weekComps) ?? today
        let monthComps = calendar.dateComponents([.year, .month], from: today)
        let thisMonth = calendar.date(from: monthComps) ?? today
        return Boundaries(today: today, yesterday: yesterday, thisWeek: thisWeek, thisMonth: thisMonth)
    }

    static func bucket(for date: Date, boundaries b: Boundaries) -> TimeBucket {
        if date >= b.today      { return .today }
        if date >= b.yesterday  { return .yesterday }
        if date >= b.thisWeek   { return .thisWeek }
        if date >= b.thisMonth  { return .thisMonth }
        return .earlier
    }
}

struct TimeBucketSection: Identifiable, Equatable {
    let bucket: TimeBucket
    let images: [IndexedImage]
    var id: Int { bucket.rawValue }
}

/// 输入按 birth_time DESC（SmartFolderEngine 已保证），单遍 O(n) group。
/// 跳过空段；返回顺序固定 today → yesterday → thisWeek → thisMonth → earlier。
func groupedByTimeBucket(
    _ images: [IndexedImage],
    now: Date,
    calendar: Calendar = .current
) -> [TimeBucketSection] {
    guard !images.isEmpty else { return [] }
    let b = TimeBucket.boundaries(now: now, calendar: calendar)
    var byBucket: [TimeBucket: [IndexedImage]] = [:]
    for image in images {
        let bucket = TimeBucket.bucket(for: image.birthTime, boundaries: b)
        byBucket[bucket, default: []].append(image)
    }
    return TimeBucket.allCases.compactMap { bucket in
        guard let imgs = byBucket[bucket], !imgs.isEmpty else { return nil }
        return TimeBucketSection(bucket: bucket, images: imgs)
    }
}
