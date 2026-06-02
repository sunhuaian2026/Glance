# OpenWith — Glance 作为图片「打开方式」

> 状态：设计完成（2026-06-02 brainstorming + spike 实测落地），待 writing-plans 出 task 级切片。
> 入口：Finder 右键「打开方式 → Glance」/ Dock 图标拖放 / 拖图到窗口。

## 目标

让 Glance 出现在 Finder 右键「打开方式」列表（当前置灰），作为图片查看器打开外部图片文件；并按需把图所在文件夹融入现有浏览体验。

## 背景 — 为什么之前是灰的

`GENERATE_INFOPLIST_FILE = YES` 自动生成 Info.plist，**未声明** `CFBundleDocumentTypes` → LaunchServices 不知道 Glance 能打开图片 → "打开方式"里置灰。`WindowGroup { ContentView() }` 也没有 `.onOpenURL` / `application(_:open:)`，即使亮起来也无处理逻辑。

## 关键技术事实（2026-06-02 spike 实测钉死，durable）

通过最小 spike（声明文档类型 + `AppDelegate.application(_:open:)` + `contentsOfDirectory`）真机从 Finder「打开方式」打开一张**陌生文件夹**（`~/Documents/New project`，未被 Glance 添加过）的图，实测：

| 探测 | 结果 |
|------|------|
| 单文件 `startAccessingSecurityScopedResource()` | **true** — 看单图永远可行 |
| 陌生父目录 `contentsOfDirectory(at:)` | **❌ 失败**：「未能打开文件 "New project"，因为你没有查看它的权限」 |

**结论**：macOS 沙盒下，「打开方式」只授权**那一个文件**，**不授权父目录**。所以「打开图 → 自动添加文件夹 → 浏览整个文件夹」的**全自动零打扰版本不可能**——这是 Apple 框架铁律。要浏览整个文件夹，必须用户**主动经 `NSOpenPanel` 选一次文件夹**授权（= 现有"添加文件夹"路径）。

> 沙盒文件授权澄清：沙盒 app **从不**弹"想访问 XX，允许吗"式弹窗（那是相机/麦克风/通讯录）。文件权限只有两个来源，授权范围 = 用户主动指定的 item：(1) 在 `NSOpenPanel` 选中 → 授权所选（选文件夹=整个文件夹）；(2) 系统把文件交给 app（打开方式/双击/拖放）→ 只授权那一个文件。

## 行为设计（路线：看单图为主 + 按需浏览全部）

1. **单图打开** → 直接进 QuickViewer 全屏看这张（零打扰，单文件权限够）
2. **多图打开**（Finder 选多张）→ QuickViewer + filmstrip = 选中的这几张（每张 user-selected 自带权限，可靠）
3. **浏览所在文件夹** → QuickViewer 里给一个入口（文件夹按钮 / 文件夹名可点）→ 点击弹「选择文件夹」对话框（预定位父目录）→ 授权后**等同添加文件夹**：持久化 bookmark + 进 IndexStore + sidebar 加入 + grid 浏览全部 + 定位到这张图
4. **智能省一步** → 若打开的图父文件夹**已添加过**（已有 bookmark），"浏览所在文件夹"直接可用，不再弹对话框
5. **关闭 QuickViewer** → 退回 app 之前状态（冷启动→默认空态；已开着→之前浏览的文件夹）

## 技术架构（spike 已验证全链路通）

- **文档类型声明**：手写 `Glance/Info.plist`（`CFBundleDocumentTypes`：`CFBundleTypeRole=Viewer` / `LSItemContentTypes=public.image` / `LSHandlerRank=Alternate`）+ pbxproj 设 `INFOPLIST_FILE`，保留 `GENERATE_INFOPLIST_FILE = YES`。**已实测**：二者合并生效，`CFBundleDisplayName` / `CFBundleVersion`（版本注入）/ `CFBundleIdentifier` 自动注入不丢。
- **入口**：`AppDelegate.application(_:open:)`（已实测接收 + 单文件权限 true）。覆盖冷启动 / 运行中 / 多文件 / Dock 拖放 / 拖图到窗口。
- **看单图**：复用 `QuickViewerOverlay(images: [URL])`（ContentView 现有 overlay）；外部打开的 URL 集合用独立 `@State`，**不碰** `folderStore.images` / IndexStore，隔离临时态。
- **浏览全部**：复用 `FolderStore.addFolder(from:)`（现有 `NSOpenPanel → saveBookmark → discoverTree → selectFolder` 流程），授权父目录后等同手动添加。

## 关键决策

- **D-OW1 路线 = 看单图为主 + 按需浏览全部**。Why: 沙盒实测证明"全自动浏览整个文件夹"不可能（陌生父目录拒权）；看单图零打扰满足"双击就看"，浏览全部一键升级满足"想看整个文件夹"，授权成本只加在真正需要时。How to apply: 默认进 QuickViewer 看单图；"浏览所在文件夹"是 QV 内的显式入口，非自动触发。
- **D-OW2 `LSHandlerRank = Alternate`（不抢系统默认）**。Why: Glance 是备选看图器，用户主动选才用；抢占系统默认（Owner/Default）会改变用户双击图片的既有习惯，过度侵入。How to apply: 出现在"打开方式"列表但不改默认看图器。
- **D-OW3 浏览全部 = 等同添加文件夹（持久化）**。Why: 复用现有 `addFolder` 心智 + app-scope bookmark 持久化，下次启动还在，跟手动添加的文件夹无差别；符合用户"融入现有浏览"的诉求。How to apply: 授权成功直接调 `addFolder(from:)`，不另造临时态浏览。
- **D-OW4 文档类型 = 手写 Info.plist + `INFOPLIST_FILE` 保留 GENERATE**。Why: `CFBundleDocumentTypes` 是嵌套数组，无 `INFOPLIST_KEY_` 标量等价物，必须手写 plist；保留 GENERATE 让 DisplayName/版本注入/Bundle ID 继续自动合并（已实测不丢）。How to apply: 手写 plist 只含文档类型，其余靠 build settings 注入。

## 范围边界

- **一并支持**（零成本，共用 `application(_:open:)`）：Dock 图标拖放 / 拖图到窗口
- **不做**：编辑 / 另存 / 旋转写回；不改现有"添加文件夹"浏览路径；不抢占系统默认看图器
- **UTI 范围**：spike 用 `public.image` 一把覆盖（jpeg/png/heic/gif/tiff/svg 等均 conform）；正式版是否细化到具体子类型留 plan 评估

## 切片计划（tracer-bullet vertical slice）

- **Slice 1 — 亮起来 + 看单图**：文档类型声明 + 单图/多图打开进 QuickViewer。端到端可 ship（Finder 不再灰 + 打开方式/双击能看图）。**spike 代码转正**：Info.plist + pbxproj + `application(_:open:)` 框架直接复用，把"弹 alert"换成"进 QuickViewer 看图"。
- **Slice 2 — 浏览所在文件夹**：QuickViewer 加"浏览所在文件夹"入口 + 按需 `NSOpenPanel` 授权 → `addFolder(from:)`；父文件夹已授权时直接定位。独立可 ship（在 Slice 1 基础上增量）。

## spike 现状

spike 代码（`Glance/Info.plist` + `pbxproj` 两处 `INFOPLIST_FILE` + `GlanceApp.swift` 的 `application(_:open:)` alert 实测块）当前在 working tree **未 commit**，作为 Slice 1 的骨架待转正。
