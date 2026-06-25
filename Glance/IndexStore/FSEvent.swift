//
//  FSEvent.swift
//  Glance
//
//  Slice G — FSEvents 事件 record。从 FSEventsWatcher.swift 拆出来对齐
//  CLAUDE.md "每个文件只声明一个 public 类型" 规则（codex P1）。
//

import CoreServices

struct FSEvent {
    let path: String
    let flags: FSEventStreamEventFlags

    var isFile: Bool       { flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 }
    var isCreated: Bool    { flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 }
    var isRemoved: Bool    { flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 }
    var isRenamed: Bool    { flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 }
    var isModified: Bool   { flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 }
    var isInodeMetaMod: Bool { flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0 }
    /// root 被改名/移动 — 当前 watcher 失效，caller 应 stop + 重启 watch
    var isRootChanged: Bool { flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 }
}
