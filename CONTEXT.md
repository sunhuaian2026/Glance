# CONTEXT — Glance · 一眼

> 本文件存放项目领域语言（术语表）+ 架构总览。
> **决策**写 `specs/Roadmap.md`「关键架构决策」段（不在此处沉淀）。
> **模块细节**看 `specs/<module>.md`。**进度**看 `specs/Roadmap.md`。**人工测试队列**看 `specs/PENDING-USER-ACTIONS.md`。

---

## 项目一句话

macOS 本地看图 app，SwiftUI 实现，沙盒 + Security Scoped Bookmark，针对单人本地素材浏览场景，深色优先、内容优先、零第三方依赖。

---

## 领域术语表

新术语首次出现先在此登记，再用于代码 / specs / commit message。命名冲突时本表为准。

### 状态与持久化

- **AppState** — 全局 UI 状态（`isFullScreen` / `appearanceMode`）。`@StateObject` 注入根 view。
- **FolderStore** — 文件夹/图片状态管理（`FolderNode` 树、当前图片列表、排序）。`@StateObject` 在 `GlanceApp`。
- **BookmarkManager** — Security Scoped Bookmark 持久化与解析层；处理沙盒文件权限授权与跨 session 恢复。
- **FolderNode** — 文件夹树节点（递归结构 + 展开/折叠态 + badge 数）。
- **Security Scoped Bookmark** — macOS 沙盒下持久化文件访问权限的唯一手段；解析时必须 `startAccessingSecurityScopedResource()` 配对 stop。

### 看图核心

- **Image Preview** — 单击缩略图进入的内嵌预览视图（`ImagePreviewView`）；轻量、跟随全局外观；双击触发 Quick Viewer。
- **Quick Viewer** — 双击进入的全窗口看图覆盖层（`QuickViewerOverlay`）；强制深色、提供完整缩放/导航/Filmstrip/Inspector 入口。
- **ZoomMode** — Quick Viewer 缩放模式枚举（fit / 100% / custom）；驱动 `ZoomScrollView` 行为。
- **Filmstrip** — Quick Viewer 底部缩略图条，横滑切图。
- **Inspector** — 图片信息侧栏（EXIF / 尺寸 / 文件元数据），可在 Quick Viewer 内调出。
- **Prefetch ±1** — 预览/Quick Viewer 当前索引相邻 ±1 图的预加载缓存策略，目的是方向键切换零延迟。

### 外部打开 / 窗口生命周期（OpenWith 方向 2，2026-06-03）

- **External Viewer（ExternalViewerWindowController）** — Finder「打开方式」/ Dock 拖放打开图片时弹出的**独立看图窗**（Preview/Quick Look 式）。纯 AppKit 单例：自建 `NSWindow + NSHostingController(QuickViewerOverlay)`，自任 `NSWindowDelegate`（不接 `WindowAccessor`，避免 delegate 被抢）。方向 2 取代旧"外部打开复用图库主窗 + QV overlay"模型，绕开 warm 崩溃 + 置顶顽疾。纯看图（无找类似/搜索/浏览所在文件夹）。
- **ViewerSession** — 一次"看图"会话：持有本次 urls 的 security-scope token + `terminateOnClose` flag。二次打开时旧 session 退役进 `retiredSessions`（**不立即 end**，避免与旧同步读盘竞态），统一在看图窗 `windowWillClose` 时 end（短期 scope 重叠无害）。
- **terminateOnClose** — `ViewerSession` 标志：看图窗关闭后是否终止整个 app。冷启动 open = `true`（看完即走）；warm（图库在用）= `false`（只关窗）。
- **MainWindowController** — 图库主窗的自建 AppKit 控制器（**Slice 2 引入**）。把图库主窗从 SwiftUI `Window` scene 收回自建，首窗创建权交 AppDelegate，cold/warm 判断用自持状态（禁扫 `NSApp.windows`），是"冷启动只显看图窗、看完即走"的前提。

### UI 系统

- **DesignSystem (DS.*)** — 所有 UI 常量唯一来源（`DS.Spacing` / `DS.Color` / `DS.Anim`）；硬编码颜色 / 间距 / 动画一律拒绝。
- **Traffic Light Hide** — 全屏/沉浸模式下隐藏窗口左上红黄绿按钮的策略。

### 已知陷阱（曾踩过的坑，命名以方便引用）

- **`.id(idx)` 重建陷阱** — SwiftUI 的 `.id(x)` 修饰符会在 `x` 变化时销毁重建整个 subtree，连带销毁 `@StateObject`。任何跨 idx 切换需要持久的状态（cache / prefetch / 长任务）必须由父 view 持有 `@StateObject`、子 view 用 `@ObservedObject`。`ContentView` 对 `ImagePreviewView` 加过 `.id(idx)`，因此 `ImagePreviewViewModel` 由父持有。`QuickViewerOverlay` 没有 `.id`，子内 `@StateObject` OK。

### 跨文件夹聚合（V2 引入）

- **智能文件夹（Smart Folder）** — 基于规则的跨文件夹聚合视图，**永远是 query 结果，不存储成员关系（rule-based ONLY，不允许 manual membership）**。规则 + 索引 → 当前展现。两类来源：**内置**（"全部最近"/"本周新增" 等，由开发者预定义）+ **用户自定义**（M4 起开放规则编辑器）。两者规则语法相同、存储路径相同，只在出处和顺序有差异。
  - **不抢库哲学保护**：smart folder 不引入"只在 V2 里存在的图片组织数据"。用户卸载 V2，磁盘原状，没有"membership"会丢。跟 Eagle / Photos 的 lock-in 路线明确划清界线。
  - 命名约定：UI 用「智能文件夹」（呼应 macOS Finder / Notes 的现成心智模型）；代码用 `SmartFolder`。
- **受管文件夹（Managed Folder）** — 被纳入智能文件夹**扫描范围**的本地文件夹。来源：V1 sidebar 加过的 root folder 自动纳入（半显式默认行为）；扫描**默认全递归**所有子目录。可在 root 或任意子目录右键菜单 toggle "在智能文件夹中隐藏" 进行剪枝（hide 状态可继承：hide root 默认 hide 整棵树，子目录可单独 unhide 取消继承）。**managed 是 smart folder 的输入域**，两个概念解耦：folder 可以同时是 V1 navigation 入口 + smart folder 的扫描源。
- **内容去重（Content Dedup）** — 智能文件夹 grid **同字节图只显示一次**的呈现规则。判定方式：先按 `(size, format)` 粗筛 → 仅对 size 碰撞的子集算 SHA256 内容哈希。留 birth time 较早的副本作为代表项，其他副本以"另在 N 个文件夹中存在"形式在 Inspector 副本段列出。**只影响 smart folder 视觉**，不影响磁盘真相和 V1 navigation——用户从 V1 进具体 folder 仍能看到所有副本。
- **图像指纹（Feature Print）** — 通过 macOS Vision framework 的 `VNFeaturePrintObservation` 抽出的图像视觉特征向量（每张 ~2-4KB），用于"找类似图"通过余弦距离做相似度排序。完全 on-device 推理，零外部费用。**不存语义标签 / 不识别物体 / 不做自然语言搜索**——只回答"这两张图视觉上像不像"。Apple 在不同 macOS 大版本会升级算法（`requestRevision` 字段），新旧版向量不可直接比对，IndexStore 单独追踪 revision，macOS 升级时后台 re-index 该列。RAW / 矢量格式 / 视频不支持，跳过；用户对未支持格式按"找类似"会得到"该格式暂不支持"提示。

---

## 术语字典表（强制规范，2026-06-16 起）

> 规则：能用中文用中文；代码符号（类名/属性/SQL 列名/方法名）保留英文 PascalCase/camelCase 原样；约定俗成的英文术语（macOS 官方文档术语 / 开发方法论术语）保留英文。
> **强制等级**：新写或修改的 `.md` 文档（CONTEXT.md 自身豁免）若出现「弃用别名」列里的词，`scripts/verify.sh` Stage 1 报红阻塞 commit。
> **范围**：本字典只管文档（`.md`）+ commit message。`.swift` 代码符号一律保留英文不受约束。
> **历史文档**：不主动返工，遇到改到时顺手统一。
> **新术语登记流程**：(1) 来本字典补一行（中文规范 / 英文场景 / 弃用别名）+ 上面「领域术语表」段补一句话定义；(2) 不补字典直接用 → verify.sh 拒收；(3) 命名冲突时本字典为准。

### A. 自造简写（弃用）

| 弃用别名 | 改用 |
|---|---|
| `QV` | 「快速看图器」（或代码符号场景下用 `QuickViewer*`） |
| `SF` | 「智能文件夹」（或代码符号场景下用 `SmartFolder`） |
| `IS` | `IndexStore`（写代码名全称） |
| `OW`（裸写） | 「OpenWith」全称；决策 ID 段 `D-OW1..16` 保留 |
| `QVT` | 已并入 `D-QV`（`D-QVT1..7` → `D-QV1..7`） |
| `P1-1` / `P1-2` / `P1-A` / `P2-3` / `P2-5` / `P2-7` / `P1#1`~`P1#5` / `P2#4` / `P2#5` 等 | `codex P1（一句话内容）` 或 `codex P2（一句话内容）`——必须带含义,不准裸编号 |
| `I-1` / `I-2` / `I-3` / `I1` / `I2` | `codex 实施期 issue（一句话内容）` |
| `M-1` | `codex major issue（一句话内容）`（与 milestone 编号 M1/M2/M3/M4/M5 区分,后者保留） |

> codex review 输出的 issue 编号**含义浮在脑子里没写到 .md 里**,后续无法追溯。一律改写成「`codex P1/P2/实施期/major issue（X）`」形式,X 是 1-2 词描述。允许引用但必须带含义。

### B. 同义簇规范

| 概念 | 中文规范 | 弃用别名 | 代码符号（保留） |
|---|---|---|---|
| 快速看图界面 | **快速看图器** | QV / 看图器 / 看图窗 / Quick Viewer / 看图覆盖层 | `QuickViewerOverlay` / `MainQuickViewerWindowController` |
| 重复清理功能 | **重复清理** | 内容去重 / Dedup（正文） | `DedupPass` / `dedup_canonical` |
| 去重动作 | **去重** | content dedup / 重复（单独使用歧义） | — |
| 沙盒 | **沙盒** | Sandbox / App Sandbox（中文场景） | — |
| 文件权限书签 | 首次写全 **Security Scoped Bookmark**，后续 **bookmark** | 书签 / Bookmark（句首大写之外） | `BookmarkManager` |
| 阶段内里程碑内最小独立交付单元 | **任务** | Slice / slice / 切片 / 片 / VS / vertical slice | — |
| 临时结果视图 | **临时结果（视图）** | ephemeral / Ephemeral（正文） | `EphemeralResultView` |
| 全屏 | **全屏** | fullScreen / FullScreen（正文） | `isFullScreen` |
| 图库主窗 | **图库主窗** | 主窗 / 主窗口 / 图库（单独使用） | `MainWindowController` |
| 重复组保留张 | **保留张** | canonical / Canonical / 代表项 | `dedup_canonical` |
| 缩略图 | **缩略图** | thumbnail / Thumbnail（正文） | `ThumbnailCell` |
| 焦点 | **焦点** | focus / Focus（正文） | `isWindowKey` |
| 找相似图（动作） | **找相似图** | 找类似 / find similar | — |
| 相似图（结果集） | **相似图** | 类似图 | — |
| 图像指纹 | **图像指纹** | feature print（正文） | `FeaturePrint*` / `VNFeaturePrintObservation` |

### C. 中英文边界

| 概念 | 中文规范 | 弃用别名 |
|---|---|---|
| 侧边栏 | **侧边栏** | sidebar / Sidebar |
| 工具栏 | **工具栏** | toolbar / Toolbar |
| 缩略图网格 | **缩略图网格** | grid / Grid（单独使用） |
| 内嵌预览 | **内嵌预览** | preview（单独使用避免与 macOS Preview.app 混淆） |
| toast 提示 | **toast 提示** | UI 模式约定俗成保留 toast |
| spike | **spike** | 开发方法论术语保留 |

### D. 三层规划方法论「阶段 → 里程碑 → 任务」

> 顶层规划单位**阶段**(版本号性质) → 内含**里程碑**(独立交付,M 编号) → 内含**任务**(更细分独立交付,字母/数字编号)。
> 实施时的批次/commit 节奏**不算层级**,直接说"分 N 批 ship"。
>
> **强制约束**(写新文档 / 新 plan / 新 spec / 新 design / PR 描述 / commit message 时):
> - ✅ **必须用新名**:阶段 / 里程碑 / 任务
> - ❌ **禁用旧名**:Slice / slice / vertical slice / VS / 片 / 切片 / 阶段拆分
> - 老 plan / 老 spec / commit 历史保留旧名(历史只读,不批量改 — 改了破坏 git blame + commit 引用关系)

#### D.1 阶段定位（项目版本号）

| 代号 | 阶段定位 | 状态 |
|---|---|---|
| **V1** | 单文件夹看图阶段(V1 sidebar 树形浏览 + 缩略图 grid + 快速看图器 + 双击预览 + 排序/筛选/快捷键) | ✅ 已 ship（v1.0.0 release `2026-05-08`）|
| **V2** | 跨文件夹聚合阶段(IndexStore + 智能文件夹 + 相似图查找 + 全局搜索 + 重复清理) | 🔄 进行中(M1-M4 + 独立子系统) |
| **V3** | 待规划 | — |

> 阶段层用代号 V1/V2 即可,**首次出现时一句话定位**即可(本表已登记)。

#### D.2 V2 里程碑（M 编号 = milestone 简写,国际通用）

| 编号 | 里程碑名 | 状态 |
|---|---|---|
| **M1** | V2 第 1 里程碑 · 跨文件夹索引基础(IndexStore + SQLite + FSEvents + DedupPass) | ✅ |
| **M2** | V2 第 2 里程碑 · 相似图查找(VNFeaturePrintObservation + EphemeralResultView) | ✅ |
| **M3** | V2 第 3 里程碑 · 全局搜索 + 筛选 chips | ✅ |
| **M4** | V2 第 4 里程碑 · 重复清理(去重省空间闭环) | 🔄 design 中 |
| **M5+** | 待规划 | — |

> M 是 milestone 国际通用缩写,无歧义保留。**禁用 "milestone X" 中英文混写**,统一 M1/M2/M3/M4 代号。

#### D.3 独立子系统（不属于任何里程碑,生命周期跨多里程碑）

| 子系统名 | 范围 | 状态 |
|---|---|---|
| **快速看图器 toolbar 修复** | regression 修复项,跨 V2 M1-M3 期间发现并修复(原 Slice 1/2/3 改任务 1/2/3) | ✅ Slice 1+2 已 ship,任务 3(边界硬化)= backlog |
| **OpenWith 子系统** | Finder「打开方式」+ Dock 拖放接收图片(独立看图窗,跨 V2 M2-M3)| ✅ 方向 2 Slice 1+2 已 ship(改任务 1/2) |
| **快速看图器看图增强** | 旋转/翻转/删除/复制/Finder 显示(D33-D40,即将启动 design codex review) | 🔄 design 中 |
| **小图全屏放大** | backlog 项,fitScale 小图分支放大算法 | ⏸ |

> 独立子系统**不塞 V2 M 序号**,各自顶层命名;内部按"任务 1/2/3"拆。

#### D.4 决策 ID 命名空间

> 决策（D 编号）走 `specs/Roadmap.md`「关键架构决策」段;独立子系统保留独立命名空间,常规决策并入主 D 序号。

| 命名空间 | 用途 | 现状 | 后续 |
|---|---|---|---|
| `D1` - `D40` | V2 主线决策（含 M1/M2/M3/M4 计划 + 快速看图器看图增强计划） | D1-D32 已用，D33-D40 是看图增强计划占位 | 主序号，新决策默认进这里 |
| `D-OW1..16` | OpenWith 子系统独立命名空间 | 已用 16 个 | **保留**（生命周期跨多 V2 里程碑） |
| `D-QV1..7` | 快速看图器 toolbar 子系统独立命名空间（原 `D-QVT` 改 `D-QV`） | 7 个，旧文档逐步替换 | 子系统决策完结后冻结，不再新增 |

> 别再造新子系统命名空间(除非系统级跨多里程碑)。常规决策一律进主 D 序号。

---

### E. 旧名 → 新名映射对照表

> 看老文档(specs/v2/M1-M3 plan / OpenWith plan / 快速看图器 toolbar plan / Roadmap.md / PENDING)时**心里查表翻译**。老文档**不批量改**(保 git blame 可读)。新文档严格用新名。

| 旧名（老文档常见） | 新名（标准） | 简写 |
|---|---|---|
| Slice A / Slice B / ... / Slice I | V2 M1 任务 A / B / ... / I | M1 任务 A |
| Slice J / Slice K | V2 M2 任务 J / K | M2 任务 J |
| Slice M / Slice N | V2 M3 任务 M / N | M3 任务 M |
| QV toolbar Slice 1 / 2 / 3 | 快速看图器 toolbar 修复 任务 1 / 2 / 3 | 快速看图器修复 任务 1 |
| OpenWith Slice 1 / 2 / 方向 2 Slice 1 / 2 | OpenWith 子系统 任务 1 / 2 | OpenWith 任务 1 |
| Slice K.4 deferred / Slice B-α polish | V2 M2 任务 K 性能验收(deferred)/ V2 M1 任务 B 子项 α polish | M2 任务 K perf |
| Vertical slice / VS | 任务 | — |
| 切片 / 片 | 里程碑(若指阶段内独立交付)/ 任务(若指里程碑内细分) | — |

---

## 架构总览

```
┌────────────────────────────────────────────────┐
│ GlanceApp（注入 BookmarkManager / FolderStore  │
│            / AppState 三个 @StateObject）       │
└────────────────────┬───────────────────────────┘
                     │
              ContentView  (NavigationSplitView)
              ├─ FolderSidebarView   (FolderNode 树 + 拖拽添加)
              ├─ ImageGridView       (缩略图网格 + ThumbnailCell)
              └─ Overlay 层
                  ├─ ImagePreviewView      (单击触发，跟随外观)
                  └─ QuickViewerOverlay    (双击触发，强制深色)
                      ├─ ZoomScrollView    (NSViewRepresentable)
                      ├─ Filmstrip
                      └─ ImageInspectorView (EXIF Form)
```

**层次划分**：
- **状态层**：AppState / FolderStore / BookmarkManager（三个 @StateObject，`GlanceApp` 注入）
- **View 层**：ContentView（split）+ Overlay（Image Preview / Quick Viewer）+ Sidebar / Grid / Inspector
- **桥接层**：`WindowAccessor`（NSViewRepresentable，拿 NSWindow + 装 NSWindowDelegate）/ `ZoomScrollView`（NSViewRepresentable，包 NSScrollView 处理滚轮+双击+拖拽）
- **持久化层**：Security Scoped Bookmark（文件权限）+ UserDefaults（外观模式 / 排序偏好等）

**编译 / 文件系统约定**：
- `Glance/` 目录用 `PBXFileSystemSynchronizedRootGroup`，新建 `.swift` 文件自动加入编译，无需手改 `xcodeproj`。
- 所有编译/运行/验证走命令行（Makefile + `scripts/verify.sh`），GUI Xcode 仅作 pbxproj 损坏救场用。

---

## 不在本文件管的

- **决策**（架构选型、不可逆操作记录、为什么这么做）→ `specs/Roadmap.md`「关键架构决策」段
- **进度**（哪些模块完成、Bug Fix 记录）→ `specs/Roadmap.md`
- **模块接口/实现细节** → `specs/<module>.md`
- **人工测试 backlog** → `specs/PENDING-USER-ACTIONS.md`
- **UI 规范** → `specs/UI.md`

