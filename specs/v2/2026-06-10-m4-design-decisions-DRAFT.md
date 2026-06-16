# M4 设计决策种子（DRAFT — 待新会话补全为正式 design）

> ⚠️ 本文件是 brainstorming 中途产物。2026-06-10 brainstorming 会话后期工具输出出现
> 不一致（疑似 context 退化，同型 incident 2026-06-09），主动停手避免脑补 API。
> **5 个核心决策 + 底层 findings 已与军哥拍板/会话早期干净 grep 确认，可靠。**
> 新会话第一步：干净 Read 相关代码 → 把本文件补全为正式 `2026-06-10-m4-design.md`
> → codex review → writing-plans。

## M4 总目标

找重复图片 → 清理省硬盘空间闭环（项目核心命脉）。第一刀只切**完全相同去重**（SHA256 字节级）。
视觉相似（Vision）放后续任务。

## 已拍板的 5 个核心决策

1. **保留策略 = 自动保留 canonical + 整组勾选**
   - 每组自动保留 `dedup_canonical=1`（earliest birth_time + 最小 id tie-break），用户只整组勾选「这组要清理」。
   - 不给逐张改保留的能力。理由：完全相同 = 像素无差别，删哪张画质都一样。
   - 设计约束：总览必须**透明显示保留的是哪张**（即便不让改，用户看得到）。

2. **入口形态 = 侧边栏 一等公民入口 + 主区总览（复用 ephemeral layer）**
   - 侧边栏 智能文件夹区加「重复清理」项，点击主区域换成总览视图。
   - 复用 ContentView 现有 modal layer / ephemeral 挂载模式（M2 相似图 / M3 搜索同模式）。
   - 总览不是 SmartFolder query，是 dedup 聚合，需独立的 list item + 独立总览 view。

3. **删除确认 = 一键移废纸篓 + 可撤销 toast**
   - 点「移入废纸篓」直接执行 + 顶部 toast「已移 N 张到废纸篓 [撤销]」。
   - 不弹确认框。理由：废纸篓本身可逆 + toast 撤销 = 双保险，符合「省空间要爽快」初心。
   - 撤销 = FileManager 从废纸篓复原。

4. **数据来源 = 信任后台索引，直读现成**
   - 总览直读 DB 现成 dedup 结果，秒开。后台正在索引则显示进度 chip。
   - 不加「重新扫描」按钮。理由：DedupPass 已自动维护（FolderScanner 后 + FSEvents 增量）。

5. **拆 = 拆两个任务（风险前置）**
   - **任务 1（只读总览）**：侧边栏 入口 + 主区总览（重复组 + 可省空间数字），只读不删。
     独立价值：第一次量化「我有 X 组重复·可省 Y GB」（初心 awareness）+ 军哥真机先验证
     dedup 结果准不准（建立信任）再放开删除。
   - **任务 2（删除闭环）**：勾选 + 移废纸篓 + 可撤销 toast + 删后 DB 更新/总览刷新。

## 底层 findings（会话早期干净 grep / Read 确认，可靠）

**M4 能复用的现成底层**：
- `DedupPass.runFullPass(store:)` — 全库 SHA256 去重决议，已在 `FolderStoreIndexBridge.swift:190`
  自动跑。落 DB：`dedup_canonical=1` 保留 / `=0` 重复副本 / NULL 视作 canonical。
- `DedupPass.reEvaluateGroup(store:fileSize:format:)` — 单组重决议（删除后剩余组要调它）。
- per-图查询已有并被 Inspector 用（被动用法）：
  - `IndexStore.fetchDuplicates(imageId:sha256:) -> [(id, fullPath)]`
  - `IndexStore.fetchDuplicatesByFullPath(_:) -> [(id, fullPath)]`（ContentView.swift:193 用）
- dedup CRUD（IndexedImage.swift）：`setDedupCanonical` / `fetchCandidateGroups` /
  `fetchImagesInGroup` / `promoteOrphanDuplicates`。
- DB 删除：`deleteImage(folderId:relativePath:)` / `deleteImages(folderId:relativePaths:) -> Int`
  ——⚠️**只删 DB 索引行，不碰真实文件**。
- security scope 模式：`DedupPass.computeSha` 展示了 resolve root bookmark +
  `startAccessingSecurityScopedResource` 拼 child URL 的写法（移废纸篓复用此模式）。

**M4 缺的三块（要新建）**：
1. **全库聚合查询**：现有都是 per-图，没有「列出所有重复组 + 每组省多少空间」的聚合 SQL。
   设计草案（待 writing-plans 精化 + 验证列名）：
   ```sql
   SELECT content_sha256, COUNT(*) AS cnt, MIN(file_size) AS size,
          SUM(CASE WHEN dedup_canonical = 0 THEN file_size ELSE 0 END) AS saveable
   FROM images
   WHERE content_sha256 IS NOT NULL
   GROUP BY content_sha256
   HAVING cnt > 1
   ```
2. **真实删除能力**：现在全项目无任何碰真实文件的代码（只 `DesignSystem.swift:252`
   `trash` 图标常量）。要新加 `FileManager.trashItem` + 跨 root security scope + 删后清 DB row。
3. **总览 UI**：侧边栏 入口项 + 主区总览视图（勾选 + 空间统计 + 移废纸篓按钮 + toast），零起点。
   交互和 EphemeralResultView（看图 grid）差别大，可能新建专门 view 但沿用 ephemeral 挂载模式。

**images 表关键列**（IndexStoreSchema.swift 确认）：
`id` / `url_bookmark BLOB`（root bookmark）/ `birth_time REAL` / `file_size INTEGER` /
`relative_path TEXT` / `folder_id INTEGER` / `content_sha256 TEXT?` / `dedup_canonical INTEGER?`。

**dedup「完全相同」口径**：candidate group 先按 `(file_size, format)` 撞 → 再 SHA256 字节级验证。
只清字节级完全相同的拷贝（同一文件副本），跨格式/转码的不算 → 符合「第一刀最安全」。

## 待办（新会话）

1. 干净 Read：`ContentView.swift`（ephemeral layer 挂载点 + currentEphemeral 状态）、
   `EphemeralResultView.swift`（接口，判断复用还是新建）、`SmartFolderListView.swift` 全文
   （入口加法）、`FolderStoreIndexBridge.swift:190` 上下文。
2. 把本文件补全为正式 `specs/v2/2026-06-10-m4-design.md`（brainstorming skill 产出格式）。
3. codex review design（军哥规则：spec/plan 定稿先过 codex 再交用户拍板）。
4. writing-plans → 任务 1 / 任务 2 task 拆分（逐符号 reality check）。
5. 实施 → 真机验。
