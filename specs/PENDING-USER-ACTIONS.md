# PENDING User Actions

真机/GUI 验证清单。**不能自动化**的项累积在此，`/go` Step 3 追加，人工验证后从 Pending 移到 Done 并保留做历史记录。

## 格式

```
- [ ] (YYYY-MM-DD / <短 hash>) **类别**: 具体怎么测，要看到什么现象
```

类别：启动 / 排序 / QuickViewer / 全屏外观 / Inspector / 缩略图 / 侧边栏 / 其他

## 使用规则

- CC 在 `/go` Step 3 追加本次 `.swift` 改动可能影响的运行时项
- 不每次复制全清单 —— 只追加与本次改动**真正相关**的
- commit hash 先占位 `<pending>`，commit 完成后回填
- 人工测完在 Pending 前面打 `x`，把整行剪切到 Done 段
- Done 段保留所有历史（可追溯某次回归何时被验证过）

---

## Pending

### V2 快速看图器增强 任务 A — 旋转/翻转 + 信息上屏(2026-06-17 ship 待真机验)

> 任务 A ship `a646265.0617-2229`(7 commit `8525e18`..`a646265`)。verify.sh 三段全过(14/14, build 0 error 0 warning), subagent-driven 0 self-fix 单轮过。CC 自闭环 Mac mini 工具链(Ghostty/tmux/keystroke/AX)未跑 — 旋转/翻转/信息视觉需军哥本机肉眼直接验更高效。

军哥本机验项(plan A.9 + A.10 合并):
- [ ] (2026-06-17 / `a646265`) **L/R 旋转生效**: 进任一图双击进快速看图器 → 按 **L** 看图逆时针转 90° → 再按 **L** 累计 180° → 按 **R** 顺时针转回 → 视觉直觉对(绕中心转)
- [ ] (2026-06-17 / `a646265`) **切图重置 (D34)**: 旋转图后按 **→** 切下一张 → rotation 重置为 0(下一张是原始朝向, 不继承)
- [ ] (2026-06-17 / `a646265`) **信息上屏角落气泡**: 进图后左下角看「**\\<width\\>×\\<height\\> · \\<size\\>**」气泡(如「4000×3000 · 2.5MB」), 鼠标静止 3 秒后跟 topBar/bottomToolbar 一起淡出, 鼠标移动 reappear
- [ ] (2026-06-17 / `a646265`) **R-rotate-anchor 真机验**(plan 风险): 旋转 90° 后滚轮缩放锚点是否仍视觉跟手? 偏移则记 PENDING 实施期修 anchor 逆变换
- [ ] (2026-06-17 / `a646265`) **R-rotate-zoom 真机验**(plan 风险): 放大平移态(custom zoom + 非零 offset)下按 L/R → 选 plan 方案 (a) 重置回 fit 是否符合直觉? 不符合则改方案 (b) offset 旋转重映射
- [ ] (2026-06-17 / `a646265`) **R-rotate-render-order 真机验**(plan 风险): 旋转 + 翻转组合(右键菜单选水平翻转后再按 L)视觉是否符合直觉(先转后镜像)? 不对则反过来试

任务 B 待实施 — B.4 会**替换** A.6 的 `.onKeyPress("r")` 为合并版本(裸 R 旋转 + ⌘⇧R Finder 显示)。

---

### V2 快速看图器增强 任务 B — 复制图 + 复制路径 + Finder + 右键 contextMenu(2026-06-17 ship 待真机验)

> 任务 B ship `fd9d4f7.0617-2242`(5 commit `9e93a0d`..`fd9d4f7`)。verify.sh 三段全过(14/14, build 0 error 0 warning), subagent-driven 0 self-fix 单轮过。B.4 已**替换** A.6 的 `.onKeyPress("r")` 为合并版本(裸 R 旋转 + ⌘⇧R Finder 显示同 keypress 内分支)。

军哥本机验项(plan B.7 + B.8 合并):
- [ ] (2026-06-17 / `fd9d4f7`) **右键 contextMenu 视觉**: 进快速看图器右键弹菜单, 7 项排列(旋转左 L / 旋转右 R / 水平翻转 / 垂直翻转 / 复制图片 ⌘C / 复制路径 ⌘⌥C / 在 Finder 中显示 ⌘⇧R)对齐 macOS 习惯, 图标 + 文字 + 快捷键 hint 都显示
- [ ] (2026-06-17 / `fd9d4f7`) **⌘C 复制图片 fidelity**: ⌘C 后到 (a) Slack 粘贴看图; (b) macOS 备忘录粘贴看图; (c) Finder 桌面粘贴(应该生成文件) — 三处 fidelity 都 OK
- [ ] (2026-06-17 / `fd9d4f7`) **⌘⌥C 复制路径**: ⌘⌥C 后 terminal `pbpaste` 看完整路径, 或粘贴到任何 textbox 看完整字符串
- [ ] (2026-06-17 / `fd9d4f7`) **⌘⇧R Finder 显示**: ⌘⇧R 后 Finder 弹窗 + 当前图被反高亮
- [ ] (2026-06-17 / `fd9d4f7`) **R 合并 handler 不冲突**: 裸 **R** 仍旋转 90° (任务 A 行为), **⌘⇧R** 触发 Finder, 不会撞或互相干扰

任务 C 待实施 — Delete/⌘⌫ 移废纸篓 + 单张撤销 toast(单张删除适配层 QuickViewerTrashCoordinator), C.10 会**追加** contextMenu 末尾「移到废纸篓」.destructive 项。

---

### V2 快速看图器增强 任务 C — Delete/⌘⌫ 移废纸篓 + 单张撤销 toast(2026-06-17 ship 待真机验)

> 任务 C ship `17c3424.0617-2308`(12 commit `f52b29c`..`17c3424`)。verify.sh 三段全过(14/14, build 0 error 0 warning), subagent-driven 2 轮 self-fix(C.2 `import Combine + objectWillChange`; C.6 `.onKeyPress(.delete, phases: .down)` 现代 pattern)。新增 5 文件改动: DesignSystem + QuickViewerTrashCoordinator(新建 159 行) + IndexedImage(byFullPath SQL) + VM(images mutable + removeCurrent) + MainQVController + Overlay(onTrash/onUndoTrash/Delete/⌘⌫/toast/contextMenu 末项) + ContentView wire。

军哥本机验项(plan C.14 + C.15 合并, **真删用户文件场景需谨慎**):
- [ ] (2026-06-17 / `17c3424`) **端到端 Delete 真删**: 进任一图(已在 V2 IndexStore 有 row)双击进快速看图器 → 按 **Delete** → ~/.Trash 见文件 + DB row 删 + 自动跳下一张 + 右下角弹「已移废纸篓 [撤销] [×]」toast
- [ ] (2026-06-17 / `17c3424`) **撤销文件恢复**: toast 点「撤销」→ 文件回原路径 + DB row 重建 + toast 切「文件恢复, 列表稍后刷新」+ 5 秒后 auto-dismiss
- [ ] (2026-06-17 / `17c3424`) **删到最后一张关窗**(D40): 快速看图器只剩 1 张时按 Delete → 最后那张进废纸篓 + 自动关快速看图器(因 images 空)
- [ ] (2026-06-17 / `17c3424`) **⌘⌫ 同 Delete**: 按 ⌘⌫ 行为跟裸 Delete 一致(走 .onKeyPress("⌫") + .command 分支)
- [ ] (2026-06-17 / `17c3424`) **右键 contextMenu 移到废纸篓**: 右键弹菜单 → 最后一项「移到废纸篓 (⌫)」红色 destructive → 点击行为同 Delete
- [ ] (2026-06-17 / `17c3424`) **V1 老 bookmark schema gate 拦截**: 进 V1 时代 bookmark 加的 root 里某张图(未升级 V2 = schemaVersion < 2) → 按 Delete → 右下角弹红色失败 toast「无法删除该图(可能未入库 / V1 老 bookmark / 已升级 V2 才能删)」, 文件不动 DB 不动, 用户被引导走 M4 重复清理升级路径
- [ ] (2026-06-17 / `17c3424`) **总览同步刷新**: 删完一张后切到「重复清理」总览, 看到组数 / 可省字节数对应减少(Coordinator 调 reEvaluateGroup + promoteOrphanDuplicates + triggerIndexChanged 让总览 reload)
- [ ] (2026-06-17 / `17c3424`) **OpenWith 路径不接 trash**: 通过 Finder「打开方式 → Glance」打开图(走 ExternalViewerWindowController) → Delete 应该无响应(OpenWith 路径 onTrash 默认 nil, handleTrashCurrent guard 兜底)

---

### V2 快速看图器增强 followup — toolbar「更多 ⋯」菜单(2026-06-18 ship 待真机验)

> 任务 A/B/C ship 后军哥反馈: 右键 contextMenu 发现性弱, toolbar 缺对应小图标。走方向 4 — 加 `ellipsis.circle`「更多」Menu 按钮在「找类似」和「全屏」之间, 内容镜像 contextMenu 七项(旋转 L/R + 翻转 H/V + 复制图 + 复制路径 + Finder + 移到废纸篓 destructive)。contextMenu 保留作右键快捷。verify.sh 三段全过(14/14, build 0 error 0 warning)。

军哥本机验项:
- [ ] (2026-06-18) **toolbar「更多」按钮可见**: 进快速看图器底部工具栏看「找类似」和「全屏」之间多了一个 `…` 图标按钮, 视觉跟其他 toolbar 按钮一致(32×32 + 白色 0.85 opacity), hover tooltip「更多」
- [ ] (2026-06-18) **下拉菜单内容对齐 contextMenu**: 点「更多」展开菜单, 8 项分 4 组(旋转左 L / 旋转右 R | 水平翻转 / 垂直翻转 | 复制图片 ⌘C / 复制路径 ⌘⌥C / 在 Finder 中显示 ⌘⇧R | 移到废纸篓 ⌫ 红色), 跟右键 contextMenu 完全一致
- [ ] (2026-06-18) **菜单各项执行正确**: 点「旋转左」图转, 点「复制图片」可粘贴, 点「移到废纸篓」走 trash 流程(同 Delete 键), 行为跟 contextMenu 同项一致
- [ ] (2026-06-18) **菜单指示器隐藏**: 按钮无下拉箭头小三角(`.menuIndicator(.hidden)`), 视觉跟其他 toolbar 按钮无差异

---

### V2 主窗 detail 列工具栏 — 加查找按钮(2026-06-18 ship 待真机验)

> 军哥反馈: 主窗顶部标题栏想要查找按钮入口, 不熟键盘的用户不知道有 ⌘F。改动: ContentView `.toolbar` 在「信息 ⌘I」和「外观切换」之间插一个查找按钮(`magnifyingglass` 图标), 点击 = `openSearch()` 跟 ⌘F 同效果。**不挂 `.keyboardShortcut("f")`** 避免与下方 `.onKeyPress(.init("f"))` 双绑触发两次, ⌘F 仍走原 `.onKeyPress` 唯一处理, button 只当点击入口 + help tooltip 显「查找 (⌘F)」。verify.sh 三段全过(14/14, build 0 error 0 warning)。

军哥本机验项:
- [ ] (2026-06-18) **工具栏查找按钮可见**: 主窗顶部标题栏看「信息 ⓘ」和「外观切换 ◐」之间多一个放大镜 `magnifyingglass` 按钮, hover tooltip 显「查找 (⌘F)」
- [ ] (2026-06-18) **点击行为 = ⌘F**: 点击查找按钮 → 主窗弹搜索 overlay(跟按 ⌘F 一样的效果, Spotlight 式输入框 + chip bar + filmstrip)
- [ ] (2026-06-18) **⌘F 仍只触发一次**: 按 ⌘F 弹搜索 overlay, **不要弹两次或闪烁**(确认 .keyboardShortcut + .onKeyPress 没双绑)
- [ ] (2026-06-18) **进入快速看图器后工具栏被遮**: 双击图进快速看图器 → 主窗工具栏被独立 QV 窗盖住物理不可见(预期); 关 QV 后工具栏回归

---


（本段 CC 维护，追加新项。测完移到 Done。）

**仅保留 deferred 项**——明确推后不测的 perf 验收 + 设计 polish。其他历史 pending 项 2026-05-22 用户确认"全部测过了"后批量补录到 Done 段。


### V2 M4 任务 2 — 卷类型矩阵 + bookmark 迁移验证 (前置门控, design 8.2 最小解锁条件)

> **解锁条件** (design 8.2 codex review 第二轮 + 第五轮): (a) 内置 APFS 必过 + (b) 外置 USB/Thunderbolt 必过 + (c) iCloud Drive 行为明确 + (d) ≥1 类失败路径 fallback 验通 + **(e) V1 read-only bookmark 迁移路径已定 (D-M4-1 走 A: clearAllForMigration + schemaVersion 哨兵 + M4 删除入口首次引导重选)**。**全过才解锁本 plan 步骤 3+ 实施**。任一失败 → 反推 design 修订。

**任务 A 升级 UI 端到端 CC 主 agent 自闭环验** (2026-06-17, build `162a522-d.0617-1621`, Mac mini 解锁 + Ghostty/tmux/screencapture/AX 工具链, V1 时代 sync root 当 bench schemaVersion 未设置):

✅ **项 1 PASS** sheet 渲染 — 进重复清理总览勾组点「移入废纸篓」→ AX `SHEET_COUNT: 1, x=725 y=366 w=470 h=207`, 文案完整匹配「升级清理权限」+ 三句话主文案 + DisclosureGroup「为什么需要重新选?」(折起) + 两按钮「以后再说」/「重新选择根目录 →」; 截图存证 `~/sync/glance-bm-ui-01-sheet.png`

⏸ **项 2 partial** DisclosureGroup 展开 — 渲染存在 (截图 + AX `AXDisclosureTriangle x=731 y=486` 命中), 但 CGEvent click triangle 没触发展开 (SwiftUI DisclosureGroup 内部 view 层级 AX 找不到 「为什么需要重新选?」AXStaticText 来精确点); **降级 PENDING 给军哥本机真鼠标点验展开**; 不阻塞其它功能

✅ **项 3 PASS** 「以后再说」按钮 — click x=949 y=525 后 `SHEET_COUNT: 0` (sheet 关) + `defaults read com.sunhongjun.glance bookmarkSchemaVersion` 仍报 does not exist (schemaVersion 未升, V1 不动) + sync root 仍在侧边栏 + checkbox 仍勾 + 按钮 enabled 「移入废纸篓 (1 张)」(**D5 selectedSha256s 保留**); 截图 `~/sync/glance-bm-ui-03-after-later.png`

✅ **项 4 PASS — atomicity 验证完美** NSOpenPanel Cancel — 再次点「移入废纸篓」→ sheet 重弹 → click「重新选择根目录 →」x=1102 y=537 → NSOpenPanel 出 (`WIN: 打开, WIN: 全部最近`) → 截图 `~/sync/glance-bm-ui-04-nsopenpanel.png` → Esc 取消 → panel + sheet 都关 + `schemaVersion does not exist` (**D3-bm-ui atomicity: 取消零数据丢失 V1 bookmark 不动**)

✅ **项 5 PASS** (2026-06-17 军哥本机真机验) 重扫期间 chip + 总览「重新扫描中…」专用空态

**军哥本机补验 4 项** (2026-06-17 全过):
- [x] (2026-06-17 / `162a522`) **端到端 trashItem + 撤销** ✓: 真机点引导 sheet「重新选择根目录 →」→ NSOpenPanel 选 sync root → schemaVersion 切 2 → 总览先显「重新扫描中…」空态 → 重扫完总览自动 reload + selectedSha256s prune 后仍勾 → 用户点按钮真 trash → ~/.Trash 看到副本 → DB row 没了 → banner「已移 N 张 [撤销] [×]」出 → 点撤销 → 文件回原位
- [x] (2026-06-17 / `162a522`) **跨视图持久 banner** ✓ (D33): 触发 banner 后切 V1 folder / 智能文件夹 / 搜索 → banner 一直可见可点
- [x] (2026-06-17 / `162a522`) **「以后再说」session 持久** ✓: 点「以后再说」关 sheet → 关 app → 重启 app → 进总览再点「移入废纸篓」→ 应再弹引导 (schemaVersion 仍 < 2)
- [x] (2026-06-17 / `162a522`) **DisclosureGroup 展开验** ✓ (轻验): 触发 sheet 后真鼠标 click 「> 为什么需要重新选?」→ 验展开行「macOS 沙盒授权模型限定：只读 bookmark 不能升级为读写，必须重新创建。」可见


**step 5 CC 主 agent 自闭环验** (2026-06-17, build `642f0a9-d.0617-1130`, Mac mini 解锁 + Ghostty/tmux/screencapture/AX 工具链):

✅ **项 1 PASS** 组级 checkbox 渲染 + 勾选高亮 — AX: `AXCheckBox val=0→1` after click on x=588 y=222; 截图 `/tmp/glance-step5-04-window.png` 蓝色勾选 + 「选择此组清掉 1 张副本」文案 ✓

✅ **项 2 PASS** 按钮文案 + disabled→enabled 切换 — AX: `AXButton enabled=false (selectedSha256s 空)→true (勾选后)` at x=1400 y=142; 截图右上「🗑 移入废纸篓 (1 张)」+ borderedProminent 蓝底 ✓

⏸ **项 3+4+5 等 (e) 引导 UI 后续 task ship 后跑** — D2 A 拍板 step 5.4 暂不实现 V1→V2 bookmark 升级引导 UI; 现有 sync root 是 V1 时代 `.securityScopeAllowOnlyReadAccess` flagged bookmark; UserDefaults `bookmarkSchemaVersion` 键不存在(连 V1 标都没显式写); 点 「移入废纸篓」后:
  - DB: id=39 (canonical) + id=122 (副本) 两条 record 都还在
  - 文件系统: `~/sync/ScreenShot_..._副本.png` 还在原位, `~/.Trash/` 未见该文件
  - banner 设计上沉默 (显示条件 successCount>0 OR undoResult≠nil; trash 全失败时不显示空 banner — D33 设计)

这是 D-M4-1 的已知场景, code 层 (BookmarkManager V2 saveBookmark 去 flag + TrashService snapshot.urlBookmark resolve + scope) 完全正确, 是 sync root bookmark 数据兼容问题 — 走 (e) 引导 UI 后续 task + (f) 重选 root 端到端可验通。



- [x] (2026-06-17 / `bbf9038`) **(a1) V1 既有 bookmark 仍可看图无碍** ✓ — 军哥本机真机验通: V1 root 在 sidebar 可点开 + 缩略图加载 + QV 看图正常 + 进总览看到重复组列表
- [x] (2026-06-17 / `bbf9038`) **(a2) 端到端 trashItem + 撤销** ✓ — 引导 sheet + 重选 root + schemaVersion=2 + trashItem + ~/.Trash + 撤销整套路径军哥本机真机过:
  1. 步骤 5 commit 后 build + 启 app
  2. 进 「重复清理」总览, 勾组, 点 「移入废纸篓」按钮
  3. 弹引导面板 「V2 升级首次清理需要重新选择根目录…」+ 「重新选择根目录 →」按钮
  4. 点重选, NSOpenPanel 弹出, 选 1 个 root (家目录, 如 ~/Documents/screenshots)
  5. 重选后 schemaVersion 切 2, 总览重新索引扫描 + 重新 load
  6. 再次勾组 + 点 「移入废纸篓」, 这次 trashItem 成功 (无 code=513)
  7. ~/.Trash/ 里看到刚删的图, 系统废纸篓正常显示
  8. banner 显示 「已移 N 张, 撤销」, 点撤销 → 图回原路径 + 总览组 reEvaluate
- [ ] (2026-06-17 / `<pending>`) **(b) 外置 USB / Thunderbolt** — 移动盘下加 root 后真机跑 (Mac mini 接 USB 盘)
  1. 卷上 `/Volumes/<name>/.Trashes/<uid>/` 出现刚删的图
  2. restore 成功
  3. 弹出卷 → 重新插回 → 再 restore 是否仍能成功 (or 报 file not found)
- [ ] (2026-06-17 / `<pending>`) **(c) iCloud Drive 行为明确** — 必须二选一不允许"可能成功可能失败"模糊态
  1. 已下载的图 (绿色对勾) trashItem 行为
  2. 云占位 (未下载) 的图 trashItem 行为 (报错 / 隐式下载后成功)
  3. 选 plan B fallback: 报错则 banner 副文案显示「iCloud 未下载文件无法清理」
- [ ] (2026-06-17 / `<pending>`) **(d) ≥1 类失败路径 fallback** — 任选一类
  - [ ] 只读卷: dmg mount 后 trashItem 抛 `NSFileWriteVolumeReadOnlyError` → member 级失败累积, 其余 member 仍 trash 成功
  - [ ] 卷弹出: 中途弹出 USB → 剩余 member 抛 `NSFileReadNoSuchFileError` → 不中断
  - [ ] 磁盘满: 人为构造接近满的卷 → `NSFileWriteOutOfSpaceError` 抛 → banner 单独提示「磁盘已满」
- [x] (2026-06-17 / `bbf9038`) **(e) bookmark 迁移引导 UI 真机走一遍** ✓ — 引导 sheet 弹 + 「重新选择根目录 →」NSOpenPanel + 重选 + markSchemaV2 + 总览扫描 + 重新 load + 「以后再说」session 持久 + DisclosureGroup 展开 全过 (军哥 2026-06-17 本机肉眼验)
- [x] (2026-06-17 / `bbf9038`) **(f) 重选 root 后 trashItem 跑通端到端** ✓ — 真进 ~/.Trash + banner 出 + 撤销文件回原位 (军哥 2026-06-17 本机肉眼验)

**(a)(e)(f) 全过 → bookmark 迁移路径解锁; (b)(c)(d) 卷类型矩阵保留 PENDING (外置 USB / iCloud / 失败 fallback, 需特殊环境单独跑, 不阻塞内置 APFS 主流程)**

---


### V2 M4 任务 1 步骤 4 — DuplicateOverviewView + 侧边栏「重复清理」入口 + 五态互斥（任务 1 完整端到端）

> ✅ **任务 1 主体价值兑现**：本步 ship 后军哥首次能完整体验「重复清理总览」端到端 — 侧边栏 点入口 → 看到真实重复组 + 真实可省空间数字 + 保留张透明显示。这是任务 1「先建立信任后才放删除」策略的核心节点。

**自验已通过**（2026-06-16 21:22, build `3584910.0616-2055`, CC 主 agent 自闭环, 军哥远程解锁 Mac mini 后 Ghostty/tmux/screencapture/AX 工具链）：
- ✅ 项 1: 侧边栏「重复清理」入口 — trash icon + 选中后 accent 高亮 + accent 背景胶囊均正常（截图 `/tmp/glance_dedup_v2.png`）
- ✅ 项 2: 点入口 → 主区切总览（grid 消失，V1 sync 折叠区也让位，互斥成立；截图 `/tmp/glance_dedup_v2.png` vs `/tmp/glance_baseline.png` 对比）
- ✅ 项 4: 保留张绿色「保留」Capsule badge 可见在 canonical 缩略图右上 + 副本无 badge（截图 `/tmp/glance_dedup_v2.png` 1 组 2 张图 — `Screen3..._630.png` canonical + `Screen3..._副本.png` duplicate）
- ✅ 项 7: 互斥反向 — 在总览态点 全部最近 → 主区切回 SmartFolder grid（截图 `/tmp/glance_back_to_grid.png`）+ 再点重复清理 → 二次进入总览态正常（截图 `/tmp/glance_dedup_again.png`）
- ✅ 顶部统计「1 组重复 · 可省 43 KB」+ 「组可省 43 KB」+ scalemass icon — 数字渲染正常（DB 一致性核对待军哥本地用 sqlite3 抽样验，见项 3）

**军哥真机本地验**（CC 自闭环触不到的项）：
- [ ] 项 3: 抽样核对 — 命令行跑 `sqlite3 <DB> "SELECT SUM(file_size) FROM images WHERE dedup_canonical=0"` 应 = 统计条 "可省 X" 数字 + 单组「组可省 Y」(group) 应 = 该组所有副本 file_size 之和
- [ ] 项 5: hover 缩略图显完整路径 tooltip（`.help(member.fullPath)`）— CC CGEvent 模拟 mouseMoved 不能稳定触发 SwiftUI `.help` tooltip render（已知限制，需军哥真鼠标 hover 1-2 秒）
- [ ] 项 6: 空态 — 清空 DB（或运行不含重复图的库）后总览显「没找到重复图」+ checkmark.seal icon
- [ ] 项 8: 后台索引活动联动 — 添加新根目录触发首次扫描，看 (a) 顶部索引 chip 实时刷新 (b) 扫完总览自动 reload（500ms debounce）
- [ ] 项 9: codex P2 N+1 race 观察项 — FSEvents 增删图触发 reEvaluateGroup 的同时点开总览，看「某组短暂显示前一保留张」瞬态错配（500ms debounce 后应自动修正）

> CC 自闭环限制：`.help` tooltip / SQL 数字一致性 / 空态 / 后台索引联动 / FSEvents race 都需要真鼠标交互或外部 DB 操作，CC SSH/Ghostty 自闭环工具链触不到，留给军哥本地。

### V2 M4 任务 1 步骤 3 — DuplicateOverviewModel 状态机 + bridge observer 订阅

> 本步是 model 层准备，无 UI 集成 — 编译通过即代表本步落地。Model 行为验证延后到步骤 4 UI 集成后。

- [ ] (2026-06-16 / `989d5cb`) **步骤 3 落地确认**：
  1. `make build` 0 errors 0 warnings（编译通过 = DuplicateOverviewState / DuplicateOverviewModel 都被自动加入 PBXFileSystemSynchronizedRootGroup 编译目标）
  2. Model 行为完整真机验在步骤 4 UI 集成后做（4 路 fire 点 → debounce 500ms → 自动 reload）
  3. **步骤 4 真机验顺手观察**（codex P2 提示的 N+1 query race）：FSEvents 增删图触发 reEvaluateGroup 的同时点开总览，看看有没有"某组短暂显示前一保留张"瞬态错配（500ms debounce 后应自动修正）；若长期错配再考虑改全包大事务

### V2 M4 任务 1 步骤 2 — 聚合查询 + DuplicateGroup record + DS.Dedup 常量

> 本步是 DB 层 + 设计常量准备，无 UI 可感知 — 编译通过即代表本步落地。聚合查询正确性在步骤 3 Model 集成 + 步骤 4 UI 跑通后才能验。

- [ ] (2026-06-16 / `2abe08d`) **步骤 2 落地确认**：
  1. `make build` 0 errors 0 warnings（编译通过 = DuplicateGroup.swift / IndexedImage.swift 新查询 / DS.Dedup 常量都被自动加入 PBXFileSystemSynchronizedRootGroup 编译目标）
  2. 步骤 3 / 步骤 4 完成后 在总览 UI 看到「X 组重复 · 可省 Y GB」数字时再回查（可与 DB sqlite3 命令行查 `SELECT COUNT(*) FROM (SELECT 1 FROM images WHERE content_sha256 IS NOT NULL GROUP BY content_sha256 HAVING SUM(CASE WHEN dedup_canonical = 0 THEN 1 ELSE 0 END) > 0)` 数字对齐）

### V2 M4 任务 1 步骤 1 — bridge 多播架构升级（智能文件夹自动刷新等价回归验证）

> 本步纯 refactor（D35 prerequisite），不引入新功能也不破坏现有功能。验证 4 路 fire 点等价即可。任务 1 完整闭环（侧边栏入口 + 主区总览 + 真实数据）在步骤 4 完成后才能感知，步骤 1 单独无 UI 改动。

- [ ] (2026-06-16 / `5b77249`) **bridge 多播 — 智能文件夹自动刷新**：
  1. 添加根目录 → 等首次扫描完 → 智能文件夹「全部最近」grid 自动出现新图（fire 点：dedup full pass 完成）
  2. 文件夹外部 Finder 新增 / 删除 / 改名图 → 智能文件夹 grid 自动反映（fire 点：FSEvents handleEvents）
  3. 删根目录 → 智能文件夹 grid 里该根的图被清（fire 点：孤儿清扫）
  4. 编辑某图（变 file_size 或 sha256）→ 智能文件夹 grid 自动刷新（fire 点：dedup group 重决议）
  - 若任一路径行为退化（grid 不刷新或残留 stale）→ 回查 `FolderStoreIndexBridge.fireIndexChanged()` 实现 + ContentView `bridge.addIndexChangedObserver` 注册点

### QV toolbar 小图全屏放大（backlog，与 Slice 1/2 解耦）

> Slice 1（9 项 2026-06-08 真机验过）+ Slice 2（6 项 2026-06-15 + inheritedMain 1 项 2026-06-09 真机验过）全部搬 Done。本节单独留唯一未做的 backlog 项需重做。Slice 3（边界硬化）未启动。

- [ ] (2026-06-09 / backlog 小图全屏) **QV 全屏小图放大**：方案已定 = `fitScale` 小图分支（图≤窗口）从保 1:1 改为 `min(放大到fit×fitPadding, smallImageUpscaleCap)`，新增常量 `DS.Viewer.smallImageUpscaleCap=200%`（中等小图放大铺满、特别小图封顶防过度上采样糊；模糊只由放大倍数定、Retina 屏一致无需分辨率适配，封顶值真机可调）。**⚠️ 实现做过又因 CC 状态退化 `git checkout` 弃了 → 下个会话重做**（改 2 处：DS.Viewer 加常量 + `QuickViewerViewModel.swift:174` fitScale 小图分支）。不阻塞 Slice 2/3。
  - **⚠️ 待军哥确认的原意出入（2026-06-10）**：军哥原话是「**不要定死 200%**，按原图判断放 200% 会不会糊、糊就用更小比例」+「要不要考虑屏幕分辨率（5k/4k/2k）」。上面方案把"**每张图自适应**"简化成了"**统一固定封顶 200%**"，论据是"糊只由放大倍数定、与原图绝对大小/屏幕分辨率无关"。**这个论据可能对也可能把诉求改没了——重做前先 brainstorming 确认：是"固定 200% 封顶"够用，还是真要"per 图按清晰度自适应"。别照固定值闷头做。**

### Slice B-α 延后项（polish，不阻塞 ship）

- [ ] (2026-06-02 / `6e5169b` / Slice B-α polish) **chip 反色实底对比效果实机确认**：方案 C（反色不透明实底）已落地——`DS.SectionHeader.chipFill/chipText`，dark 模式 chip 用浅底（0.84 灰）深字 / light 模式深底（0.30 灰）浅字，告别 `.thickMaterial` 半透明（参考 macOS Photos.app 日期 pill）。两处 chip 同步：智能文件夹 grid 时间分段「今天 · N 张」(`SmartFolderGridView`) + 搜索/找类似结果 section header (`EphemeralResultView`)。**待实机确认**：dark/light × cell 明暗 四种组合下，chip 跟背景对比是否够"跳"、是否过抢或过暗；不满意则反馈调 `chipFill/chipText` 的 RGB（当前 light 底 0.30 / dark 底 0.84）。**已选方案 C 替代了原 PENDING 列的 A/B/D**（material 加厚 / ultraThick+shadow / accent tint 均放弃）

### V2 M2 Slice K — 性能验收（deferred）

- [ ] (2026-05-11 / `<pending>` / Slice K.4 / deferred) **性能验收 — 索引时长**：1 万图大库首次扫完入 IndexStore 后启动 fp 索引 → indexing 总时长 < 20min（电池机可放宽至 30min）
- [ ] (2026-05-11 / `<pending>` / Slice K.4 / deferred) **性能验收 — 查询响应**：1 万图全索引完后，QV 内点找类似 → 从 click 到 EphemeralResultView 显示结果时长 < 500ms

### V2 M3 Slice M — 性能验收（deferred）

- [ ] (2026-05-11 / `d315c78` / Slice M / deferred) **性能验收**：1 万图库典型 keyword 搜索响应时间 < 200ms（实测数字记录此处）

### V2 M3 — type: modifier case-insensitive 修复（待真机验，`<pending>`）

- [ ] (2026-06-06 / `<pending>`) **type:png 能搜到**：⌘F 输入 `type:png`（或 `type:PNG`/`type:Png` 任意大小写）→ 搜出所有 PNG 图（修前 type:png 是 0 结果）
- [ ] (2026-06-06 / `<pending>`) **type:webp / type:jpeg**：混合大小写标签也大小写无关能搜到（验 "WebP" COLLATE NOCASE 覆盖）
- [ ] (2026-06-06 / `<pending>`) **回归 size:/birth:/keyword**：`size:>1mb`、`birth:>2026-01-01`、纯关键字搜索仍正常（本来就 work，确认没被带坏）

### 文件夹移除残留清理 方案 3（Slice 2）— 占位效果（尽力，难按需触发）

- [ ] (2026-06-03 / `9bee287` / 方案 3 Slice 2) **加载失败显占位**：自然遇到"图在索引里但读不到"时（真删磁盘文件的 FSEvents race / 损坏文件 / 不支持格式），grid cell / 预览 / QV 应显「无法加载」占位（photo.badge.exclamationmark）而非无限转圈。难按需复现，自然遇到时确认。可人工触发：受管文件夹放损坏图（.txt 改名 .jpg）或 QV 开着时 Finder 删当前图

### OpenWith Slice 2 — 浏览所在文件夹（待验证）

- [ ] (2026-06-03 / `84a1f5b` / Slice 2) **按钮出现**：Finder「打开方式」开单图 → QV 底部工具栏「找类似」「全屏」之间出现 folder 图标按钮
- [ ] (2026-06-03 / `84a1f5b` / Slice 2) **未加过的文件夹**：开一张未加进 Glance 的文件夹的图 → 点 folder 按钮 → 弹「选择文件夹」对话框（预定位父目录）→ 选中 → 文件夹加入 sidebar + grid 显示全部 + 重启后还在
- [ ] (2026-06-03 / `84a1f5b` / Slice 2) **已加过的文件夹**：开已管理文件夹的图 → 点 folder 按钮 → 不弹框，直接跳到该文件夹 grid
- [ ] (2026-06-03 / `84a1f5b` / Slice 2) **取消**：弹框点取消 → 留在 QV，sidebar 无变化
- [ ] (2026-06-03 / `84a1f5b` / Slice 2) **不该出现**：grid/preview 双击进的 QV 底部工具栏无 folder 按钮

### OpenWith Slice 1 — 剩余验证

- [ ] (2026-06-03 / `cc78c41` / OpenWith Slice 1) **Dock 拖放接收**：把图片文件拖到 Dock 的 Glance 图标 → 应进 QuickViewer 看该图（同 application(_:open:) 路径，未单独实测）
- [ ] (2026-06-03 / `cc78c41` / OpenWith Slice 1) **多图 QV 集合导航**：多图「打开方式」进 QV 后，左右方向键 / filmstrip 点击能在选中集合内切换

### OpenWith 方向2 Slice1 — 剩余真机验（1×1+focus fix 后版本 `a3e4ae0`）

> 核心项（warm 置顶 / 显图 / focus / 多图翻页 / 连换图 / 全屏 ESC 两段 / ⌘W 关窗 / 交通灯隐藏）2026-06-04 已验证通过（见 Done 段）。以下为 1×1 fix 后尚未单独验的项（1×1 修复前看图窗根本不可见、无法验）。冷启动双窗 + warm 关图后主窗丢失是 SwiftUI `Window` scene 同根缺陷，归 Slice2 解决（见 Roadmap 待修复）。

- [ ] (2026-06-04 / `7a32dff`+`a3e4ae0` / 方向2 Slice1) **非全屏 ESC 关窗 app 不退**：非全屏按 ESC → 看图窗关、图库主窗在、app 不退（⌘W 路径已验，ESC 补验）
- [ ] (2026-06-04 / `7a32dff`+`a3e4ae0` / 方向2 Slice1) **全屏⌘W后下次 ESC（验 P1#1）**：全屏态直接 ⌘W 关窗 → 再开一张图 → 第一下 ESC **就关窗**（不是退全屏，验 close path reset isFullScreen）
- [ ] (2026-06-04 / `7a32dff`+`a3e4ae0` / 方向2 Slice1) **Dock 拖多文件**：Dock 图标拖多个图片文件 → 同多文件打开
- [ ] (2026-06-04 / `7a32dff`+`a3e4ae0` / 方向2 Slice1) **后台抢前台**：app 切后台时收 Finder open → 看图窗能抢到前台（deferred reassert 加固）
- [ ] (2026-06-04 / `7a32dff`+`a3e4ae0` / 方向2 Slice1) **多显示器**：看图窗出现在合理屏幕（主屏 / 鼠标所在屏）
- [ ] (2026-06-04 / `7a32dff`+`a3e4ae0` / 方向2 Slice1) **内存无泄漏**：反复开关看图窗 10 次后活动监视器看 Glance 内存无明显泄漏（scope 配平 + VM deinit）
- [ ] (2026-06-03 / `7a32dff` / 方向2 Slice1 / deferred) **大量文件不在范围**：几百上千张一次打开可能撞 sandbox scope 上限，Slice1 只测几张~几十张

---

## Done

（本段追加完成条目，附完成日期。）

### V2 M4 任务 2 — bookmark 迁移引导 UI + trash 端到端（2026-06-17 用户验证全过）

> bookmark 迁移引导 UI + 重选 root + schemaVersion=2 升级 + 端到端 trashItem + 撤销 + 跨视图持久 banner + 「以后再说」session 持久 + DisclosureGroup 展开 + 重扫期间专用空态 全过；commits `4da5817`~`bbf9038`（含 checkbox hit-area + 标题栏 followup fix）。

- [x] (2026-06-17 / `bbf9038`) **端到端 trashItem + 撤销** 全闭环（引导 → NSOpenPanel → 重扫 → trash → ~/.Trash → 撤销 → 文件回原位）
- [x] (2026-06-17 / `bbf9038`) **跨视图持久 banner** (D33)
- [x] (2026-06-17 / `bbf9038`) **「以后再说」session 持久** + 重启再次弹引导
- [x] (2026-06-17 / `bbf9038`) **DisclosureGroup 展开**「为什么需要重新选?」
- [x] (2026-06-17 / `bbf9038`) **重扫期间专用空态**「重新扫描中…」(D4-bm-ui)
- [x] (2026-06-17 / `bbf9038`) **bookmark 迁移引导 UI** (e) + **重选 root 后 trashItem 端到端** (f)
- [x] (2026-06-17 / `3364231`) **重复清理组 checkbox 命中区漂移修复**（hit area 整行 + 自绘 checkbox + label 撑满）
- [x] (2026-06-17 / `bbf9038`) **「重复清理」侧栏标题栏接管** — `navigationTitle("重复清理")` 修上次 SmartFolderGridView title 残留
- [x] (2026-06-17 / `562d2ff`) **banner 居中点移到 detail 区** — overlay 从外层挂到 detail closure 内 HStack
- [x] (2026-06-17 / `3976f67`) **标题栏方形终修** — mirror V1 ImageGridView 删 SmartFolderGridView/DuplicateOverviewView/ImagePreviewView 显式 background, 让 NavigationSplitView 默认 material 接管跟侧边栏 vibrancy 融合
- [x] (2026-06-17 / `02bd2e7`) **预览背景遮罩恢复** — ImagePreviewView 加回 appBackground 不带 ignoresSafeArea (背景填 safe area 遮 grid + 工具栏区透明不出方形)

**(b)(c)(d) 卷类型矩阵保留 PENDING**（外置 USB / iCloud Drive / 失败 fallback，需特殊环境单独跑，不阻塞内置 APFS 主流程）

### QV toolbar Slice 2 — 全屏状态机（2026-06-15 用户验证 6 项全通过 + 2026-06-09 inheritedMain 验过）

> 全屏输入经 controller 路由 + 3 态状态机（windowedCover/qvNativeFullScreen/transitioning）+ enteredFromMainFullScreen flag；inheritedMain 主窗全屏进 QV 走候选2（QV 自己原生全屏新 Space，候选1 borderless+fullScreenAuxiliary 满屏覆盖踩 3 坑弃用）（commit `5d47b3c`~`a4520c5`）。

- [x] (2026-06-15 / Slice2 / `96967ed`) **windowedCover F 进全屏** ✓ 2026-06-15：非全屏下双击进 QV → F → QV 进原生全屏纯净；再 F/ESC → 退回同框 windowedCover
- [x] (2026-06-09 / Slice2 / `31ff1b1` 候选2) **inheritedMainFullScreen QV 原生全屏新 Space** ✓ 2026-06-09：主窗全屏进 QV → 切新全屏 Space 满屏看图 → ESC 退回主窗全屏 grid（主窗保持全屏）。候选1 borderless 满屏覆盖踩 3 坑弃用（浮窗不满屏/ESC焦点/关闭塌主窗全屏），改候选2 走 documented 全屏生命周期。进/退各一次 Space 切换动画（可接受）。
- [x] (2026-06-15 / Slice2 / M-1 / `96967ed`) **全屏过渡期快速双 ESC/F** ✓ 2026-06-15：进/退全屏动画期间猛按 ESC/F → 不崩、不卡死态、不反弹（transitioning 保护）
- [x] (2026-06-15 / Slice2 / `96967ed`) **qvNativeFullScreen ESC 两段** ✓ 2026-06-15：windowedCover 进 QV → F 全屏 → 第一下 ESC 退全屏、第二下 ESC 关 QV
- [x] (2026-06-15 / Slice2 / `96967ed`) **主窗最小化关 QV** ✓ 2026-06-15：QV 开着时最小化主窗（⌘M）→ QV 自动关（didMiniaturize→close），无 Dock 孤立缩略图
- [x] (2026-06-15 / Slice2 / `96967ed`) **全屏下退出焦点归还** ✓ 2026-06-15：全屏看图各路径（F/ESC/关闭按钮）退出后主窗拿回焦点、grid 高亮正确
- [x] (2026-06-15 / Slice2 / `96967ed`) **换屏 / resize** ✓ 2026-06-15：全屏/同框态下主窗换屏幕、resize → QV frame 跟随正确

### QV toolbar Slice 1 — 独立看图窗 windowedCover（2026-06-08 用户验证 9 项全通过）

> 方案2：QV 从 ContentView overlay 迁到 MainQuickViewerWindowController 独立无装饰窗（commit `ebd88bf`~`4cb1323`）。9 项真机全过：titlebar 纯净 / 同框跟随 / 方向键 highlight / 焦点归还 I1 / 找类似 P1-A / ⌘F / 状态保留 / 重开不叠窗 I2 / 全屏 ESC P1-2。

- [x] (2026-06-08 / Slice1) **titlebar 纯净（核心目标）** ✓ 2026-06-08：4 入口（V1 grid 双击 / SmartFolder grid 双击 / preview 双击图 / ephemeral 双击）进 QV → titlebar 完全纯净（无 +/分栏/ⓘ/外观/slider/排序 + 无文件名标题）
- [x] (2026-06-08 / Slice1) **QV 同框盖主窗 + 跟随** ✓ 2026-06-08：QV 窗盖住主窗位置/尺寸；拖动主窗 / resize 主窗 → QV 跟随同框
- [x] (2026-06-08 / Slice1) **方向键 highlight 跟随** ✓ 2026-06-08：QV 内方向键切图 → 退出后 grid highlight 跟到当前图
- [x] (2026-06-08 / Slice1) **退出 focus 归还（重灾区 I1）** ✓ 2026-06-08：每条关闭路径（ESC / Space / 关闭按钮 / ⌘W / 红绿灯）退出后主窗拿回 key + 键盘焦点
- [x] (2026-06-08 / Slice1) **QV 内找类似** ✓ 2026-06-08：→ 关 QV 回 ephemeral grid 结果 + 焦点到结果（autoFocusOnAppear 接管）
- [x] (2026-06-08 / Slice1) **QV 内 ⌘F** ✓ 2026-06-08：→ 关 QV + 主窗搜索框真正拿到键盘焦点
- [x] (2026-06-08 / Slice1) **状态保留（方案2 核心收益）** ✓ 2026-06-08：退出 QV 后 grid 缩略图无重载闪 / 滚动位置不变 / sidebar 展开态不变 / NavigationSplitView 列宽不变
- [x] (2026-06-08 / Slice1) **重开 / 不叠窗（I2）** ✓ 2026-06-08：关 QV 后重开正常；已开着时再双击不叠第二个窗；快速 show→close→show 焦点不串
- [x] (2026-06-08 / Slice1 / M5 待观察) **QV show 可靠抢 key** ✓ 2026-06-08：双击进 QV 后 QV 窗立即是 key（键盘/方向键直接作用 QV）

### V2 M3 Slice N — 搜索筛选 chips（2026-06-07 用户验证全部通过）

- [x] (2026-06-07 / `482c773`) **chip 类型多选即时出结果**：⌘F → 类型 chip 勾 PNG+JPEG → 不回车即时只出 PNG/JPEG（inSet 同源大写标签精确匹配）✓ 2026-06-07
- [x] (2026-06-07 / `482c773`) **WebP chip 命中**：勾 WebP → 出 WebP 图（混合大小写「WebP」精确匹配）✓ 2026-06-07
- [x] (2026-06-07 / `b3ccabf`) **chip-only 出结果**：⌘F 不输字只点 chip → 出结果（runSearch 双空 early-exit，codex 硬缺陷点）✓ 2026-06-07
- [x] (2026-06-07 / `e98d1a9`) **「今天」档非空且只今天**：本地午夜 ISO 预计算（codex 硬缺陷点）✓ 2026-06-07
- [x] (2026-06-07 / `9c79b53`) **「本周/本月/今年」自然边界**：P2 codex review 改自然边界（本周起始日/本月1号/今年1.1，Calendar 预计算 ISO）✓ 2026-06-07
- [x] (2026-06-07 / `482c773`) **大小/时间档即时收窄** ✓ 2026-06-07
- [x] (2026-06-07 / `929283a`) **chip + keyword 叠加 AND 合并** ✓ 2026-06-07
- [x] (2026-06-07 / `6e6e82c`) **popover ESC 两段**：先关 popover 再关 overlay（.onExitCommand 不冒泡）✓ 2026-06-07
- [x] (2026-06-07 / `cd0e30c`) **popover 关后焦点归还（根因修复）**：选完 chip 关 popover 后焦点回搜索框 → 能继续打字 + 回车提交进 chip 过滤结果网格；反复开关不丢焦不闪。修=SearchChipBar 透传 @FocusState.Binding，三 popover dismiss 时 returnFocusToSearch（先 nil 再 Task.yield 设 .search 弹一下，绕过 @FocusState 值不变不重聚焦）✓ 2026-06-07
- [x] (2026-06-07 / `b3ccabf`) **清除 / closeSearch 全清 / ⌘F 重开空白**（D27）✓ 2026-06-07
- [x] (2026-06-07 / `482c773`) **命令式 type:/size:/birth: + M2 找类似 + 纯 keyword 回归不退化** ✓ 2026-06-07

### V2 M3 搜索交互修复 — 焦点 + 回车 + 图源错位（2026-06-06 用户验证通过）

- [x] (2026-06-04 / `c8c5df1` / Slice M fix) **⌘F 焦点自动落 input**：⌘F → 不点鼠标直接打字就能输入（修 EphemeralResultView.onAppear 抢焦点竞争）✓ 2026-06-06
- [x] (2026-06-04 / `c8c5df1`+`9b71a1f`) **回车进结果网格 + 第一张高亮**：回车 → 收 overlay + 结果留 ephemeral + 焦点落网格 + 第一张紫色高亮（highlight 第一版没生效，9b71a1f 用 newValue 避 @FocusState 时序坑修好）✓ 2026-06-06
- [x] (2026-06-04 / `c8c5df1`) **网格内回车/空格开图**：方向键移高亮 → 回车/空格开图进 QV；ESC 退回 grid ✓ 2026-06-06
- [x] (2026-06-04 / `c8c5df1`) **空输入回车 no-op**：空着回车不发生事、overlay 留着 ✓ 2026-06-06
- [x] (2026-06-04 / `c8c5df1`+`9b71a1f`) **回归 M2 找类似不变**：找类似 ephemeral 焦点/方向键/空格一致；M2 不凭空高亮（defaultHighlightFirst=false）；M2 网格回车也能开图（已授权变化）✓ 2026-06-06
- [x] (2026-06-06 / `8f5eb56`) **找类似 V1 模式开图不错位**：普通文件夹进 QV 找类似 → 开图与缩略图一致（图源条件加 currentEphemeral != nil）✓ 2026-06-06
- [x] (2026-06-06 / `8f5eb56`) **搜索 V1 模式开图不错位**：普通文件夹 ⌘F 搜索开图一致（同根一并修）✓ 2026-06-06
- [x] (2026-06-06 / `8f5eb56`) **回归 智能文件夹模式不变**：智能文件夹进 QV 找类似/搜索开图仍正确 ✓ 2026-06-06
- [x] (2026-06-06 / `8f5eb56`) **⌘F-from-preview**：V1 preview 按 ⌘F → preview 关、进搜索、不残留错图（openSearch 无条件清 selectedImageIndex）✓ 2026-06-06

### OpenWith 方向2 Slice2 — lifecycle 接管真机门控（2026-06-04 用户验证通过）

- [x] (2026-06-04 / `b7380f1`~`3718577`) **菜单栏存活（D-OW13 最大风险）**：移除 Window scene 只留 Settings scene 后，菜单栏「一眼」有「关于一眼」可点弹 About、⌘Q 退、Edit/Window/Help 在、⌘, 弹 Settings 占位窗。**Settings-only scene 方案成立**（备选 AppKit NSMenu 未启用）✓ 2026-06-04
- [x] (2026-06-04 / `3718577`) **cold 看完即走**：app 没开 → Finder 打开方式开图 → 只弹看图窗（无图库主窗）→ 关 → 整个 app 退出 ✓ 2026-06-04
- [x] (2026-06-04 / `3718577`) **warm 主窗不丢（核心修复）**：warm 开看图窗 → 图库主窗原样在 → 关看图窗 → 主窗还在、app 不退（不再需点 Dock）✓ 2026-06-04
- [x] (2026-06-04 / `3718577`) **普通启动建主窗**：双击 app/Dock → 图库主窗（sidebar+grid 正常）✓ 2026-06-04
- [x] (2026-06-04 / `3718577`) **reopen 重建**：关图库主窗（app 驻留）→ 点 Dock → 主窗重现 ✓ 2026-06-04
- [x] (2026-06-04 / `519a697`) **退出关窗驻留（D-OW15）**：关图库主窗 → app 驻留 dock、点 Dock 秒回、⌘Q 才真退（像 Photos）✓ 2026-06-04
- [x] (2026-06-04 / `58e98fd`) **全屏 + traffic light 回归（验 WindowAccessor 移除没坏）**：图库主窗 F 全屏正常 / QV traffic light 隐藏退出恢复 / QV 焦点 ESC 直接关 ✓ 2026-06-04
- [x] (2026-06-04 / `58e98fd`) **看图窗 Slice1 能力没退化**：warm 置顶 + 多图翻页 + 连换图不显旧图 + focus 自动 + 全屏 ESC 两段 ✓ 2026-06-04
- [x] (2026-06-04 / `58e98fd`) **不支持 URL 冷启动**：用 Glance 打开 .txt → 正常建图库主窗、不崩 ✓ 2026-06-04
- [x] (2026-06-04 / `58e98fd`) **folderStore 加载不重复**：启动后已存文件夹正常显示 ✓ 2026-06-04
- [x] (2026-06-04 / `58e98fd`) **About/Settings 开着关主窗**：开 About/Settings 后关主窗 app 不退、全关才退 ✓ 2026-06-04
- [x] (2026-06-04 / `58e98fd`) **Dock 拖放**：拖图到 Dock Glance 图标 → 进看图窗 ✓ 2026-06-04

### OpenWith 方向2 Slice1 核心 + 1×1/focus fix（2026-06-04 用户验证通过）

- [x] (2026-06-04 / `7a32dff`+`a3e4ae0`) **warm 置顶（核心赌注）**：Glance 运行中 Finder「打开方式」→ 独立看图窗弹出并置顶到前台。**方向2 核心赌注成立**——V1 那个 macOS 14 warm 置顶顽疾（5 种激活 API 全败）在自建独立窗下解决 ✓ 2026-06-04
- [x] (2026-06-04 / `a3e4ae0`) **看图窗能显图（1×1 fix）**：看图窗 1280×800 正常显图（修掉 `contentViewController=NSHostingController` 的 1×1 压缩 bug → `contentView=NSHostingView`）✓ 2026-06-04
- [x] (2026-06-04 / `a3e4ae0`) **首开 focus 自动**：看图窗弹出后不点鼠标，直接 ESC/F/方向键就响应（`requestKeyboardFocusIfWindowIsKey` 下一 runloop 补 assert）✓ 2026-06-04
- [x] (2026-06-04 / `7a32dff`) **多图翻页 + 多文件打开**：多张「打开方式」→ 看图窗显第一张 + 方向键/胶片条切全部 ✓ 2026-06-04
- [x] (2026-06-04 / `7a32dff`) **二次打开换图（验 P1#2）**：看图窗开着再打开另一张 → 复用同窗显新图、连换不显旧图 ✓ 2026-06-04
- [x] (2026-06-04 / `7a32dff`) **全屏 ESC 两段**：F 进全屏 → ESC 先退全屏 → 再 ESC 关窗 ✓ 2026-06-04
- [x] (2026-06-04 / `7a32dff`) **⌘W 关窗 app 不退**：⌘W → 看图窗关、图库主窗在、app 不退 ✓ 2026-06-04
- [x] (2026-06-04 / `a3e4ae0`) **交通灯隐藏 + X 按钮关窗**：看图窗无红绿灯（冗余且丑），靠 QV 自带 X 按钮关窗 ✓ 2026-06-04
- [x] (2026-06-04 / `7a32dff` / 过渡态确认) **冷启动双窗 = 预期非bug**：cold「打开方式」同时显图库主窗+看图窗，已确认是 Slice1 过渡态预期，Slice2 移除 Window scene 后只显看图窗 ✓ 2026-06-04

### OpenWith warm open 崩溃修复（2026-06-03 用户验证通过）

- [x] (2026-06-03 / `84a1f5b`) **warm open 不再崩溃/退出**：Glance 运行中 Finder「打开方式」开图 → app 不再退出、图打开、QV 显示（applicationShouldTerminateAfterLastWindowClosed=false 修复）✓ 2026-06-03
- [x] (2026-06-03 / `84a1f5b`) **cold open 回归正常**：app 没开时打开图正常进 QV ✓ 2026-06-03

### 文件夹移除残留清理 方案 3 + nonisolated 解码（2026-06-03 回归验证通过）

- [x] (2026-06-03 / `9bee287`) **回归 — 正常加载未坏**：正常图片在 grid / 预览 / QV 都正常加载显示（`nonisolated` 解码改动 + loadFailed 标志未破坏正常路径）✓ 2026-06-03

### 文件夹移除残留清理 方案 1（2026-06-03 用户验证通过）

- [x] (2026-06-03 / `0a069e6`) **现有残留自愈**：启动新版后，之前侧边栏移除过但缩略图仍残留的文件夹的图，从智能文件夹消失（启动 DB+bookmark 对账清掉）✓ 2026-06-03
- [x] (2026-06-03 / `0a069e6`) **⚠️ 安全 — 在管文件夹未被误删**：仍在管理的文件夹的图全在，多文件夹重启后全部仍在（Guard B 没在启动瞬态误删整库）✓ 2026-06-03

### OpenWith Slice 1 + 实测 bug 修复（2026-06-03 用户验证通过）

- [x] (2026-06-03 / `cc78c41`) **多图「打开方式」单窗口**：Finder 选多图 → 打开方式 → Glance → 只有一个窗口直接进 QV（不再 spawn 多窗口，Mission Control 确认）✓ 2026-06-03
- [x] (2026-06-03 / `cc78c41`) **外部打开 ESC 直接关 QV**：进 QV 后不点图直接 ESC 立刻关（焦点修复）✓ 2026-06-03
- [x] (2026-06-03 / `cc78c41`) **回归 — grid / preview 双击进 QV ESC 直接关**：老路径焦点未被 isWindowKey 改动破坏 ✓ 2026-06-03
- [x] (2026-06-03 / `cc78c41`) **智能文件夹进 QV tooltip 首次悬停正确**：底部工具栏首次悬停显正确文案，不再串成随机文件名 ✓ 2026-06-03
- [x] (2026-06-03 / `cc78c41`) **smart folder cell tooltip 显完整路径**：hover cell 显示图片完整磁盘路径 ✓ 2026-06-03

### 2026-05-22 批量补录（V1 早期遗留 + V2 M1-M3 全部）

用户 2026-05-22 确认"全部测过了"，批量挪 ~120 项到 Done。下列内容按原 H3 分组保留（前缀的无 H3 V1 早期项归入 "V1 早期遗留"），每项 [ ] → [x] + ✓ 2026-05-22 后缀。原 `<pending>` commit hash 占位保留（未测时如有真 hash 已嵌入项内容）。

#### V1 早期遗留（原 Pending 段无 H3 头部，2026-04-27 ~ 2026-05-08）

- [x] (2026-04-27 / `<pending>` / followup) **架构**：把双 `.onTapGesture(count:1+2)` 替换为 `Button + .buttonStyle(.plain)` + 单一 action 互斥（codex 建议；macOS lazy 容器双 tap recognizer 有已知 edge case，独立改动避免 scope 失控） ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **Inspector · dark 模式开关边线同步**：dark 模式下按 ⌘I 开 Inspector → 左缘 0.5pt 边线随 Inspector 一起从右滑入，过程中**不出现粉色短暂闪现 / 不"提前到位"**；再按 ⌘I 关 → 边线随 Inspector 一起滑出，**不延迟、不残留** ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **Inspector · light 模式开关边线同步**：同上 2 项在 light 模式复测（边线应是浅黑半透明 #000 0.08，跟 dark 是同一 AdaptiveColor 的另一端） ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **Inspector · 切文件夹/取消选图自动关 Inspector**：选中图片开 Inspector → 切到另一个文件夹（侧边栏点） → Inspector 自动关 + 边线同步消失，无残留；再选图开 Inspector → 按 Esc 退选图 → 同上 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **Inspector · 内容回归**：Inspector 显示文件名/尺寸/EXIF/相机参数/GPS 各字段不变；isLoading spinner 行为不变；切换图片 Form 内容跟着更新；ContentUnavailableView 提示文案不变 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **focus ring · 真根因修法核心验证**：系统强调色保持粉色（外观 → 强调色 → 粉色）→ 启动 app → 单击缩略图进 ImagePreviewView → 整个 app 不应再有粉色框；按 ⌘I 开 Inspector → preview 右缘和 Inspector 之间不应再有粉色长条；点击 app 失焦后再聚焦 → 不再出现"刚回来粉色框闪一下"的现象 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **focus ring · ImageGridView 同步禁用**：grid 模式（无图片选中）→ 整个 grid 区域不应有粉色 focus ring 围在缩略图网格周围；grid 高亮（紫色 highlightedURL 圆角矩形）应仍正常显示 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **focus ring · QuickViewerOverlay 同步禁用**：双击缩略图进 QuickViewer → 整个 overlay 不应有粉色 focus ring；强制深色 overlay 中所有自定义 UI（顶栏 / nav 按钮 / filmstrip）视觉不变 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **focus ring · 键盘功能回归**（不能 onKeyPress 退化）：grid 方向键移 highlight / preview 方向键切图 / preview Esc 退回 grid / preview Space 进 QuickViewer / QuickViewer 方向键切图 / QuickViewer Esc 退回 全部仍正常工作；切文件夹 / 切预览图 后 onAppear 焦点路由仍生效 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix · 真解 v2) **toolbar background hidden · 核心**：杀掉旧 Glance → 装新 build → 关于面板 commit hash 应是 v2 那版 → 单击 cell 进 ImagePreviewView → 顶部应**无浅灰横条**，文件名 + ⓘ + 外观切换按钮直接坐在 NSWindow title bar 上（注意 e39fbbf v1 实机零变化已废，v2 走 SwiftUI .toolbarBackground 绘制层） ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix · 真解 v2) **toolbar background hidden · 进出 QV 回归**：双击进 QuickViewer → ESC 退 → 再单击进 preview → 仍无浅灰横条 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix · 真解 v2) **toolbar background hidden · sidebar 列**：左上 `+` 按钮 + sidebar toggle 视觉位置 / 间距不变 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix · 真解 v2) **toolbar background hidden · Traffic light 回归**：进 QV 隐藏 / 退 QV 恢复行为不变（commit a064033 / 45a61f1 / 6da903c 已修过 3 次的回归区域） ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix · 真解 v2) **toolbar background hidden · 外观切换**：浅色 / 深色 / 跟随系统切换 → toolbar 视觉跟着切，无残留 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **QV colorScheme env · QV 视觉回归**：QV 内顶栏 / nav 按钮 / filmstrip / 关闭按钮 / 缩放比例显示 / 进度 n/m 仍是深色，QV 视觉跟修改前完全一致 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **QV colorScheme env · AppearanceMode 切换回归**：浅色 / 深色 / 跟随系统切换 → 立即生效，QV 进出后切换仍即时；进 QV 前后切换外观也无干扰 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **QV colorScheme env · 深色模式回归**：深色模式 → 进出 QV → 主 app 保持深色（不应该误触发任何浅化） ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **Bug 4 · 核心**：grid 单击 cell 1.png → 进 preview → 方向键 → 到 5.png → ESC 退回 grid → **grid 紫色高亮应跟到 5.png**（修前停在 1.png） ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **Bug 4 · 双击 → QV 路径回归**（44ba6ee 区域）：grid 单击 cell A → highlight=A → 双击 cell B → 进 QuickViewer → ESC 退 QV → highlight 应在 B（不变，跟修前一致） ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **Bug 4 · 排序回归**：grid 模式 → 切换排序方式 → highlight 自动清空（因 onChange(of: images)）→ 再单击/方向键正常工作；进 preview 后切排序 → preview 仍显示同图 (175e82a 行为不变) ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix) **Bug 4 · 焦点 race 回归**（5b29600 / 59a9d86 区域）：单击 cell → preview → ESC → grid 方向键正常工作；单击 → preview → 双击 → QV → ESC → grid 方向键正常工作 ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix · Bug 4 扩展) **6da903c 回归**（最关键 — 不能破坏）：grid 双击 cell A 进 QV → **不动方向键** → ESC 退 QV → **回 grid，不进 preview**（保持 6da903c 行为） ✓ 2026-05-22
- [x] (2026-05-07 / `<pending>` / bugfix · Bug 4 扩展) **QV 导航多渠道全覆盖**：QV 内用方向键 / nav button (左右气泡按钮) / filmstrip tap **三种方式**切到 Z → ESC 退 QV → **三种方式都让 highlight/preview 同步 Z**（codex 标盲点 1，验证 onChange viewModel.currentIndex 一处覆盖三渠道） ✓ 2026-05-22
- [x] (2026-05-06 / `ab1fe89` / bugfix) **dark 模式贴 macOS 系统配色 + 失焦响应**（partial — 待 v1.0.1 重新审）：原 commit ab1fe89 删 4 处 hardcoded background 想让系统 sidebar material 接管，实测 sidebar 上半 row 区域有 vibrancy + 漏壁纸色，但 row 之下空白区是深黑色 windowBackground（条纹感）。codex:rescue 给的 NSVisualEffectView 桥方案落地后引发**关于窗口居中回归**（具体因果链未定），同时颜色仍不一致，已 revert 回 ab1fe89 状态。**期望视觉**：app 切到 dark → 侧边栏整片跟 Finder/Mail/Notes 一致（vibrancy + 漏出桌面壁纸色 + 失焦自动褪色） + 内容区中性灰；侧边栏选中 / 未选中行视觉一致（无条纹）。**当前 ab1fe89 状态可接受作 v1.0**（条纹但不影响核心功能），下次审计走 SwiftUI ZStack vs NavigationSplitView column 行为 + 验证 codex 方案为何引发居中回归 ✓ 2026-05-22
- [x] (2026-05-05 / `<pending>` / dist) **部署目标降级回归**：装 `~/sync/Glance.app` 跑 7 路径（启动 / 拖文件夹 / 单击进 preview + 方向键 / 双击进 QuickViewer 缩放拖拽 / 全屏 F 键 / 排序菜单 / 关于面板点击复制 + toast），确认 macOS 部署目标 26.2 → 14.0 未破坏现有功能 ✓ 2026-05-22
- [x] (2026-05-05 / `<pending>` / dist) **notarytool keychain profile 配置**（一次性）：① 进 https://appleid.apple.com/account/manage 「登录与安全 → App 专用密码」生成 App-specific password（命名如 `glance-notary`）；② 终端跑：`xcrun notarytool store-credentials "glance-notary" --apple-id 16414766@qq.com --team-id 8KW8Z92GRA --password <粘贴 App-specific password>`；③ 验证：`xcrun notarytool history --keychain-profile "glance-notary" --max-results 1` 无报错 ✓ 2026-05-22
- [x] (2026-05-05 / `<pending>` / dist) **完整 release 流程跑通**：跑 `make release`（5-15 分钟，含公证），观察输出无错；产物 `dist/Glance-1.0.0.dmg` 生成，SHA256 + size 正常 ✓ 2026-05-22
- [x] (2026-05-05 / `<pending>` / dist) **DMG Gatekeeper 实测**：把 `dist/Glance-1.0.0.dmg` 拷到一台干净 Mac（**不能是签名机器**，否则 Gatekeeper 自动信任本机签）；双击挂载 → 拖到 Applications → 双击启动；预期：**直接打开**，不弹「无法验证开发者」/「损坏」/「未知开发者」对话框；活动监视器显示 Glance 正常运行 ✓ 2026-05-22
- [x] (2026-05-05 / `<pending>` / dist) **GitHub 仓库改 public**：`gh repo edit sunhuaian2026/ISeeImageViewer --visibility public --accept-visibility-change-consequences`（或 GitHub 网页 Settings → Danger Zone）；改完确认能匿名访问 `https://github.com/sunhuaian2026/ISeeImageViewer` ✓ 2026-05-22
- [x] (2026-05-05 / `<pending>` / dist) **GitHub Release v1.0.0**：tag `v1.0.0`，上传 `dist/Glance-1.0.0.dmg` + sidecar `Glance-1.0.0.dmg.sha256`，写 release notes（CC 起草）。命令模板：`gh release create v1.0.0 dist/Glance-1.0.0.dmg --title "Glance 1.0.0 · 一眼" --notes-file <release-notes.md>` ✓ 2026-05-22
- [x] (2026-05-05 / `<pending>` / dist) **README 加下载入口**：项目 README 顶部加下载按钮（指 latest release）+ macOS 14+ 系统要求说明；首页带产品截图（grid / preview / QuickViewer / Inspector 各 1 张） ✓ 2026-05-22
- [x] (2026-05-05 / `<pending>` / dist · 可选) **GitHub 仓库改名 ISeeImageViewer → Glance**：与 V1 发布解耦，发完 v1.0.0 后再做。改名后 GitHub 自动留旧路径 redirect，不影响已发链接 ✓ 2026-05-22
- [x] (2026-05-05 / `bd25fd0`) **关于面板 Copyright 字段**（已用 8f927d1 自定义 about panel 取代）：标准面板 wrap 点不雅观（"小红书"和"382336617"被自动拆两行），故升级到自定义 panel — 见下方测试项 ✓ 2026-05-05

### V2 Slice A（2026-05-08 完成 / 待用户复测）

**端到端基础**
- [x] (2026-05-08 / Slice A) **V2 全部最近 · 单 root**：清干净 DB（`rm -rf "$HOME/Library/Containers/com.sunhongjun.glance/Data/Library/Application Support/Glance/"`）→ 启动 V2 → 加 1 个含 ~100 张图的 root folder → console 5 秒内出 `[IndexStore] scan complete for /path/...` → 切到 ⚙️ "全部最近" → grid 显示该 folder 的图按 birth_time 倒序 ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 全部最近 · 多 root**：再加第 2 个 root folder → "全部最近" grid 应看到两个 folder 的图**混排**按 birth_time 倒序 ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V1↔V2 互斥**：V1 sidebar 点选具体 folder → 主区切到 V1 ImageGridView（cell + size slider + sort menu）→ 切到 ⚙️ "全部最近" → 主区回 V2 grid，V1 选中清空；反向也对称 ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V1 行为零退化**：V1 mode 跑 7 路径（启动 / 拖文件夹 / 单击进 preview + 方向键 / 双击进 QuickViewer 缩放拖拽 / 全屏 F 键 / 排序菜单 / Inspector ⌘I）跟 v1.0 一致 ✓ 2026-05-22

**V2 cell 视觉/交互（mirror V1 ThumbnailCell）**
- [x] (2026-05-08 / Slice A) **V2 cell 方形 + 不 letterbox**：V2 grid cell 是方形（180×180 默认），图片填满（不留黑边 letterbox） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 cell hover 效果**：鼠标悬停 cell → 1.03× 微放大 + 暗化 dim overlay（mirror V1 ThumbnailCell） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 cell 共享 thumbnailSize**：V1 mode 拖动顶部 size slider → 切回 V2 mode → V2 cell 大小跟着变了（V1 / V2 共享 folderStore.thumbnailSize 一处控制两边） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 cell HiDPI 锐利**：retina 屏 V2 缩略图清晰（maxPixelSize = size × backingScaleFactor） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 cell hover tooltip**：鼠标悬停 cell ≥1s → 浮出 tooltip 显示 relative path（如 `nature_01.jpg` 或 `subfolder/foo.jpg`，D5） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 cell highlight 跟 V1 一致**：单击 cell → 紫色（accent color）边框 + 半透明填充 ✓ 2026-05-22

**V2 grid keyboard（mirror V1 ImageGridView）**
- [x] (2026-05-08 / Slice A) **V2 grid 自动焦点**：进 V2 mode → grid 自动有焦点（直接按方向键就工作，无需先点 cell） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 grid 方向键导航**：左 / 右 / 上 / 下 → highlight 在 V2 grid 内移动，scroll 自动跟随到中心 ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 grid Space → QV**：highlight cell 后按 Space → 进 QuickViewer（无 highlight 时取第 1 张） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 grid F → 全屏**：按 F → 切换全窗口全屏（跟 V1 / QV / preview 一致） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 grid 焦点路由 · preview 退出**：单击 cell → preview → ESC → grid 焦点回来，方向键继续 ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 grid 焦点路由 · QV 退出**：双击 cell → QV → ESC → grid 焦点回来，highlight 落在最后浏览的图 ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 grid 焦点路由 · preview→QV→preview**：单击 cell → preview → ←→ 浏览到 Z → 双击 → QV → ESC → preview 回 Z → ESC → grid highlight 在 Z ✓ 2026-05-22

**V2 mode 主区切换（mirror V1）**
- [x] (2026-05-08 / Slice A) **V2 单击 cell → preview**：cell 单击 → fade in V1 风格 ImagePreviewView，顶部 toolbar 显示 filename ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 双击 cell → QV 不闪 grid**（codex:rescue 真根因 fix 验证）：cell 双击 → QV 即时出现，**没有中间 grid 暴露闪烁**（修前会闪 ~200ms） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 preview→QV 不闪 grid**：单击进 preview → space 或双击图 → QV 即时出现，**也不闪 grid** ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 QV 导航**：QV 内方向键 / nav button / filmstrip tap → 主图正确切换；QV 内 ESC 仍按入口走（grid 双击进的 → 退回 grid；preview 双击进的 → 退回 preview） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **V2 mode Inspector**：V2 mode 单击 cell 进 preview → ⌘I 或 ⓘ 按钮 → Inspector 显示**选中图的文件名 / 尺寸 / EXIF / GPS**（非空态） ✓ 2026-05-22

**幂等性（codex review 重点 + bookmark sandbox 限制 verify）**
- [x] (2026-05-08 / Slice A) **重启幂等 · grid 自动恢复**：关闭 V2（Cmd+Q）→ 重启 → ⚙️ "全部最近" 默认选中 + grid 自动出图，**无需重扫**（IndexStore 持久化生效） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **重启幂等 · console 不再 scan**：重启后 console **不应再出** `[IndexStore] scan complete`（registerRoot path 去重 + UNIQUE(folder_id, relative_path) 配合） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **重启幂等 · DB 行数稳定**：连续重启 3-5 次后跑命令验证 image / folder 行数不持续增长： ✓ 2026-05-22

```bash
DB="$HOME/Library/Containers/com.sunhongjun.glance/Data/Library/Application Support/Glance/index.sqlite"
sqlite3 "$DB" "SELECT 'folders:', count(*) FROM folders; SELECT 'images:', count(*) FROM images;"
```

- [x] (2026-05-08 / Slice A) **path 变化不破坏幂等**：把一个 root folder 在 Finder 重命名（同磁盘位置）→ 重启 V2 → folders 表**不应出现重复行**（registerRoot 用 standardizedFileURL.path 做 unique key） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **DB 文件位置确认**（plan 路径错，注意 sandbox container）：`ls -la "$HOME/Library/Containers/com.sunhongjun.glance/Data/Library/Application Support/Glance/"` 应有 `index.sqlite` + `index.sqlite-shm` + `index.sqlite-wal` 三个文件 ✓ 2026-05-22

**边界 case**
- [x] (2026-05-08 / Slice A) **空 folder**：拖一个 0 张图的空 folder 到 V1 sidebar → V2 "全部最近" grid 不应崩，仍显示其他 root 的图（不应误进入"暂无图片"占位态） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **大 folder（性能目标，非硬性）**：加 1 万张图的大 folder → 首次扫描 < 10 分钟（plan D9 性能目标）；扫描期间 grid 应渐进显示已索引图（每批 50 张 console 进度日志） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A) **删除 root folder**：V1 sidebar 删除一个 root folder → V1 sidebar entry 消失；V2 "全部最近" grid 暂仍显示该 folder 的旧图（**Slice G FSEvents 才会清理孤立行**，Slice A 接受此 known limitation） ✓ 2026-05-22

**已知限制 / 推后的 Slice A scope**
- [x] (2026-05-08 / Slice A · followup Slice B+) **V2 grid toolbar size slider**：V2 mode 时顶部 toolbar 没有 V1 那种缩略图 size slider（80-280pt 拖动条）。当前用户只能通过先切到 V1 mode 拖 slider 间接调节。Slice B+ 决定 V2 grid 自带 toolbar 还是 ContentView 共用 ✓ 2026-05-22
- [x] (2026-05-08 / Slice A · followup Slice B+) **V2 grid toolbar 排序按钮**：V2 mode 没有排序方式 / 升降序切换（V1 有 6 种排序）。跨 folder sort 语义需要 design 拍（按 filename 跨 folder 不直观，按 birth_time / file_size 更合理） ✓ 2026-05-22
- [x] (2026-05-08 / Slice A · followup Slice I) **v2Urls / folderStore.images 双源耦合**：当前 V2 模式 ContentView 拆出本地 `@State v2Urls`，preview / QuickViewer / Inspector 三处都要 `smartFolderStore.selected != nil ? v2Urls : folderStore.images` 选 source。Slice I 重构候选：让 ImagePreviewView/QuickViewerOverlay/Inspector 不直接依赖 folderStore.images，完全走显式参数；移除 V1/V2 双向耦合 ✓ 2026-05-22
- [x] (2026-05-08 / Slice A · followup Slice I) **IndexedImage.urlBookmark 字段 rename**：实际存的是 root bookmark（不是 image 自己的 bookmark，sandbox 不允许给 enumerator 子文件创建 .withSecurityScope bookmark）。Slice I rename 候选：→ rootBookmark 或干脆改为 folder_id → folders.root_url_bookmark lookup ✓ 2026-05-22
- [x] (2026-05-08 / Slice A · followup Slice I) **computeV2Urls() 同步 resolve 性能**：cell 单击/双击时同步 resolve ~100 张 bookmark 可能 50-200ms 主线程卡顿（codex:rescue 已标）。Slice I 性能优化阶段处理（缓存已 resolve 的 root URL / 异步预热） ✓ 2026-05-22

### Slice B-α: 时间分段 sticky header（5 段固定）

- [x] (2026-05-09 / `<pending>` / Slice B-α follow-up #2) **段头 chip 形态（破"横条"第三轮修法）**：sticky header 改成左上角浮动 capsule chip（"今天 · 3 张"），row 其余区域**完全透明**，cell 滚动时直接透 chip 之外区域显示；不应再呈现"全宽横条"视觉感（前两次修法 #141419 不透明黑 / `.regularMaterial` 半透明全 row 都失败的根因 = SwiftUI Section header 全宽属性，仅改 background 改不掉） ✓ 2026-05-22
- [x] (2026-05-08 / `<pending>` / Slice B-α) **sticky 行为**：滚动 grid 时当前段标题固定吸顶，下一段进入视口时无缝替换；不应出现"两段标题同时悬浮"或"标题瞬移" ✓ 2026-05-22
- [x] (2026-05-08 / `<pending>` / Slice B-α) **跨午夜归属**：手动改系统时间至 0:01（系统设置 → 通用 → 日期与时间，关闭自动）→ 重启 Glance → 一张昨天 23:59 拍的图应归"昨天"段；改回今日中午时间该图归"今天"段 ✓ 2026-05-22
- [x] (2026-05-08 / `<pending>` / Slice B-α follow-up) **键盘导航跨段（算法已重写）**：←→ 走 flat queryResult ±1（跨段自然连续）；↑↓ 段内同 col 上下移动；段尾按 ↓ 跳下一段第一行同 col（下一段不足时 clamp 到该行末 cell）；段首按 ↑ 跳上一段最后一行同 col（同样 clamp）；第一段第一行按 ↑ / 末段末行按 ↓ 原地；Space 进 QV / Esc 退仍工作 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice B-α follow-up #2) **chip 之外透明区域 hit-test 验证（codex Q2 ⚠ caveat 实测）**：sticky chip 浮在顶部时，**chip 之外的透明 row 区域**应该**允许**点击穿透到下方 cell（用户视觉上点的就是 cell 本身）；点 chip 自身应吃掉 tap（chip 是 Capsule 实体，Spacer 不参与 hit-test）。如果实测发现 chip 之外透明区仍被 SwiftUI Section header 整 row 抓走 hit-test 不能点 cell，反馈给我加 fallback（chip 形状 contentShape + Spacer 的 transparent area 显式 allow hit through） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice B-α follow-up #2) **chip + sticky 兼容性（macOS 14 Sonoma）**：sticky 时 SwiftUI Section header row 高度应等于 chip + DS.Spacing.xs 双侧 padding 自然高度（codex Q1 已 ✓）；如果实测 row 仍占据明显厚带（chip 之上/之下出现可见空白），说明 SwiftUI 在 LazyVGrid Section header 上施加了最小高度 → 反馈给我走 fallback（overlay chip + PreferenceKey 监听 ScrollView offset 自管 sticky，约 80 行重写） ✓ 2026-05-22

### Slice B-β: 「本周新增」内置 SmartFolder

- [x] (2026-05-09 / `<pending>` / Slice B-β) **sidebar 自动出现 2 个 SF**：启动 Glance → 智能文件夹区显示 2 个 ⚙️ entry 按顺序：「全部最近」+「本周新增」；点击「本周新增」高亮切换 + grid 内容刷新 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice B-β) **本周新增结果正确性**：「本周新增」选中后 grid 显示的图全部为 birth_time ≥ 7 天前（含今天）的图；老图（≥ 7 天）不出现；切回「全部最近」图数应 ≥「本周新增」 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice B-β) **滑动窗口语义**：「本周新增」是滑窗 -7d/now（不是自然周）。验证：今天周三的话，上周三的图应在；上周二的图不在。**与 D4 段头"本周"双轨独立**——「本周新增」grid 内的图按 D4 时间分段段头分布到"今天/昨天/本周"三段（不会出现"本月"或"更早"段，因为查询窗口只 -7d） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice B-β) **空数据兜底**：如果你机器上 7 天内无新图，「本周新增」应显示空态（"暂无图片"占位），不应报错或卡死 ✓ 2026-05-22

### Slice D.1: hide toggle 端到端

- [x] (2026-05-09 / `<pending>` / Slice D.1) **root hide 整树消失**：sidebar 右键 root 文件夹 → "在智能文件夹中隐藏" → 智能文件夹（全部最近 / 本周新增）grid 该 root 下所有图全部消失；右键 root 再点 → menu label 变"在智能文件夹中显示" ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice D.1) **subfolder unhide 单独显形**：root 已 hide 的状态下，展开子目录树 → 右键某子目录 → "在智能文件夹中显示"（label 因继承自 root 显示为该文案）→ grid 中该子目录下的图重现，但该子目录的同级或父级其他子目录仍 hidden ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice D.1) **subfolder hide inside visible root**：root 处于 visible 状态下，右键某子目录 → "在智能文件夹中隐藏" → grid 中该子目录下的图消失，root 其他兄弟子目录的图仍可见 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice D.1) **状态持久化（重启不丢）**：执行任意 hide toggle → 退出 Glance → 重启 → sidebar 右键看 menu label 与 grid 显示状态都跟退出前一致（IndexStore SQLite 持久化） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice D.1) **menu label 动态准确**：右键 root 看到 label 说"隐藏"，点击 hide 后再次右键应说"显示"；同样测 subfolder（含跨继承场景：root.hide=1 子目录 menu label 显"显示"） ✓ 2026-05-22

### Slice D.2: Inspector 来源 path 段 + Show in Finder

- [x] (2026-05-09 / `<pending>` / Slice D.2) **来源段渲染**：选图开 Inspector → 滚动到底部应有"来源"Section，含"路径"row 显示完整 absolute path（长 path 中间 truncation 显 "..."），可选中复制（textSelection enabled）+ "在 Finder 中显示"按钮（folder icon） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice D.2) **Show in Finder 行为**：点 "在 Finder 中显示"按钮 → Finder 弹出/前置 + 在父目录窗口里高亮选中该文件 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice D.2) **V1 / V2 双模式生效**：V1 单文件夹模式选图 / V2 智能文件夹（全部最近 / 本周新增）选图，Inspector 来源段都正确显示对应图的真实 path（不是 root path） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice D.2) **path 选中复制**：长按拖选 path 文字 → 复制 → 粘贴到 Finder 地址栏 / 终端 → 能定位到文件 ✓ 2026-05-22

### Slice G: FSEvents 增量监听 + 删 root 清理

- [x] (2026-05-09 / `<pending>` / Slice G.1) **删 root 整树清理**：V1 sidebar 右键 root → "移除文件夹" → 智能文件夹 grid 立即不再显示该 root 下的图（不应 stale）。退出 + 重启验证 IndexStore 也已清干净（重启后 sidebar 不出现该 root，"全部最近"也不含其图） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice G.2) **新增图实时入索引**：选「全部最近」打开 grid → Finder 拖一张图到某 managed folder（不用关 Glance）→ **5s 内**该图出现在智能文件夹 grid 顶部（按 birth_time DESC） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice G.2) **跨 managed folder 都监听**：在 root1 + root2 各 cp 一张图 → 5s 内两张都出现在「全部最近」 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice G.3) **删图实时去索引**：grid 显示某图时 Finder 删该图（rm / 移到废纸篓）→ 5s 内该图从 grid 消失 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice G.3) **改图内容元数据同步**：替换某 jpg（同 path 不同内容） → 5s 内 Inspector 看到 file_size / dimensions 已更新 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice G.3) **改名 = delete + insert**：rename 某图（same folder，新文件名）→ 5s 内 grid 老 cell 消失，新 filename cell 出现（按新 birth 时间归段；Slice H 之前不会自动 dedup link） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice G.3) **subfolder 内变化也监听**：在 managed root 的子目录里 cp 图 / rm 图 → 5s 内 grid 同步（FSEvents WatchRoot 默认监听 subfolders） ✓ 2026-05-22

### Slice H: 内容去重 SHA256 + cheap-first 粗筛

- [x] (2026-05-09 / `<pending>` / Slice H.1) **dedup canonical 跨 root**：在 root1 + root2 两个 managed folder 各 cp 一张相同图（确保 same file_size + same format） → 等扫描 + dedup pass 完成 → 智能文件夹 grid 应**只显示 1 张**（earliest birth_time 那张），不应两张都显示 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice H.1) **dedup pass 后台不卡 UI**：往 managed folder 拖 1k+ 张图（含一些已知 dup） → grid 在扫描期间能正常滚动 / 切换 SF / 选图，不应 spinner 卡住 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice H.1) **FSEvents 增量去重**：grid 已显示某图 → cp 一份到第二个 root（同 file_size+format）→ 5s 内 grid 不应出现"两张同图"（dedup pass on FSEvents 应识别副本） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice H.1) **modify 后 SHA256 重算**：替换某 dup 文件内容（同 path 不同内容） → 5s 内 grid 该图独立显示（不再被视为副本）；Inspector 副本段空 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice H.1) **删 canonical 后 promote**：3 张 dup 图 A/B/C，A 是 canonical → rm A → 剩下 B/C 中 earliest 自动 promote canonical → grid 仍显示 1 张（B 或 C），不应 grid 空 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice H.2) **Inspector 副本段渲染**：选 canonical 图打开 Inspector → 滚动到底部应有"副本（N 个）"Section，列出其他 path（truncation .middle 中间省略）+ 每条行末有 folder icon 按钮可点 → 在 Finder 中跳转 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice H.2) **副本段互显**：选 canonical 看到 N-1 个副本；切到任一副本看 Inspector → 应也看到 N-1 个 path（含 canonical + 其他副本） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice H.2) **无副本时段不显示**：选普通图（无 dup）打开 Inspector → 应**没有**"副本"Section（不渲染空段） ✓ 2026-05-22

### Slice I: 进度 chip + 错误 banner + 取消 + 进度持久化 + enum-state

- [x] (2026-05-09 / `<pending>` / Slice I.1) **大库扫描进度 chip 显示**：拖一个含 5k+ 张图的 root 加入 → mainContent 顶部应出现"正在索引「root_name」 · X 已扫 / Y 入库"chip → 数字每 50 张更新一次 → 扫完 chip 自动消失 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice I.2) **取消扫描**：扫描进行中点 chip 上 X 按钮 → scan loop 内 Task.isCancelled 检测后 break → chip 消失；当前 cursor 已写入 folders.last_processed_path（持久化） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice I.2) **重启 resume from cursor**：扫描中途 cancel 或杀进程 → 重启 Glance → 该 root 自动 resume，从 lastProcessedPath 之后继续扫，不重头（依赖 macOS DirectoryEnumerator 字典序稳定遍历） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice I.2) **扫描完成清 cursor**：完整扫完一个 root → folders.last_processed_path = NULL → 下次启动不再 resume（直接走完整扫，但 insertImageIfAbsent 幂等不会重复插） ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice I.2) **错误 banner**：模拟扫描失败（如某文件 IO error）→ mainContent 顶部出现红色 capsule banner "「root_name」扫描失败：..." → 点 X 按钮 dismiss → banner 消失，主 UI 仍可滚动 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice I.3) **enum-state 重构无回归**：所有 V2 grid 行为（query 切换 / 重 query / 空态 / preview 方向键 navigate / Inspector 同步）跟 Slice H 一致，没有 race / stale-write / 重复刷新等异常 ✓ 2026-05-22

### V1 mode grid 自动刷新 + 手动刷新（2026-05-10）

- [x] (2026-05-10 / `3256733` / V1 refresh) **V1 自动 FSEvents · 增**：V1 mode 选某 folder → grid 显示 → 用 Finder 拖一张图到该 folder → 5s 内 grid 自动出现新图（不用手动刷新） ✓ 2026-05-22
- [x] (2026-05-10 / `3256733` / V1 refresh) **V1 自动 FSEvents · 删**：V1 mode 选某 folder → 用 Finder 删该 folder 内某图 → 5s 内 grid 自动消失 ✓ 2026-05-22
- [x] (2026-05-10 / `3256733` / V1 refresh) **V1 自动 FSEvents · 改**：V1 mode 选某 folder → 用 Finder 替换某图（cp 覆盖）→ 5s 内 grid 同步（缩略图重新加载） ✓ 2026-05-22
- [x] (2026-05-10 / `3256733` / V1 refresh) **手动刷新**：右键当前选中的 folder → 出现"刷新"菜单项 → 点 → grid reload。**右键非选中的 folder** → 不应出现"刷新"项（避免歧义刷哪个） ✓ 2026-05-22
- [x] (2026-05-10 / `3256733` / V1 refresh) **切 folder watcher 切换**：选 folderA → 拖图进 folderA 验证 grid 出现 → 切到 folderB → 拖图进 folderA → folderB grid **不应**响应（folderA watcher 已 stop，selectedFolder guard 也防漏）→ 切回 folderA grid 显示新图 ✓ 2026-05-22
- [x] (2026-05-10 / `3256733` / V1 refresh) **删 folder 停 watcher**：选 folderA → 右键移除 folderA → watcher 应自动停（无 leak），不再有事件触发；之后选别的 folder 正常工作 ✓ 2026-05-22

### Slice D follow-up #2 — hide 图标扩到 subfolder explicit（2026-05-10）

- [x] (2026-05-10 / `f34edb7` / Slice D follow-up #2) **subfolder 单独 hide 显图标**：root visible 状态下 → 右键某 subfolder → "在智能文件夹中隐藏" → **该 subfolder 行**应出现 eye.slash 图标 + tooltip"在智能文件夹中隐藏" ✓ 2026-05-22
- [x] (2026-05-10 / `f34edb7` / Slice D follow-up #2) **root hide 整树 subfolder 不显图标**：右键 root → "在智能文件夹中隐藏" → root 行显图标 ✓；展开 root → 各 subfolder 行**不应**显图标（继承非 explicit，避免视觉噪音） ✓ 2026-05-22
- [x] (2026-05-10 / `f34edb7` / Slice D follow-up #2) **subfolder 单独 unhide 不显图标**：root hide 状态下 → 右键某 subfolder → "在智能文件夹中显示"（subfolder 行 explicit hide=0）→ subfolder 行**不应**显图标（explicit unhide ≠ hide） ✓ 2026-05-22
- [x] (2026-05-10 / `f34edb7` / Slice D follow-up #2) **explicit + 继承双层冗余场景**：root hide → 右键某 subfolder → "在智能文件夹中隐藏"（冗余 explicit）→ root 显 / 该 subfolder 也显（双图标 — explicit 表达一致，冗余但不错） ✓ 2026-05-22
- [x] (2026-05-10 / `f34edb7` / Slice D follow-up #2) **重启状态保留**：执行任意 explicit hide → 退出重启 → 图标位置跟退出前一致 ✓ 2026-05-22

### Slice D follow-up — root hide 图标提示（2026-05-10）

- [x] (2026-05-10 / `3cd463c` / Slice D follow-up) **root hide 显示 eye.slash**：sidebar 右键 root → "在智能文件夹中隐藏" → 该 root 行 folder 名右侧应出现灰色 `eye.slash` 图标；hover 该图标 → 浮 tooltip "在智能文件夹中隐藏" ✓ 2026-05-22
- [x] (2026-05-10 / `3cd463c` / Slice D follow-up) **取消 hide 图标消失**：右键已 hide 的 root → "在智能文件夹中显示" → eye.slash 图标立即消失 ✓ 2026-05-22
- [x] (2026-05-10 / `3cd463c` / Slice D follow-up) **subfolder hide 不显图标**：root visible 状态下，右键某 subfolder → "在智能文件夹中隐藏" → subfolder 行**不应**出现图标（仅 root 层显，子目录靠 contextMenu label 表达） ✓ 2026-05-22
- [x] (2026-05-10 / `3cd463c` / Slice D follow-up) **重启状态保留**：hide 某 root → 退出 Glance → 重启 → 该 root 仍带 eye.slash 图标（IndexStore 持久化） ✓ 2026-05-22

### SVG 支持（2026-05-10）

- [x] (2026-05-10 / `c88c7ae` / SVG support) **V2 grid SVG 缩略图渲染**：装新 build → 重启 → 拖 `.svg` 文件到 managed folder → 「全部最近」grid 应**正常显示 SVG 缩略图**，不再卡 spinner ✓ 2026-05-22
- [x] (2026-05-10 / `c88c7ae` / SVG support) **V1 grid SVG 显示**：选 V1 mode 某个含 SVG 的具体 folder → 该 SVG 应在缩略图网格里出现（之前 supportedExtensions 不含 svg → V1 完全过滤） ✓ 2026-05-22
- [x] (2026-05-10 / `c88c7ae` / SVG support) **ImagePreviewView SVG**：单击 SVG cell → 进 preview → SVG 应正常显示；方向键切换到下一张非 SVG 图也正常 ✓ 2026-05-22
- [x] (2026-05-10 / `c88c7ae` / SVG support) **QuickViewer SVG**：双击 SVG cell → 进 QV → SVG 应能正常显示 + 滚轮缩放无糊（vector 无限缩放）；方向键切换其他格式正常 ✓ 2026-05-22
- [x] (2026-05-10 / `c88c7ae` / SVG support) **混合格式排序**：folder 内有 svg + png + jpg 混合 → 排序菜单切换（按修改时间 / 名字等）→ SVG 正确排序，缩略图不消失 ✓ 2026-05-22

### FolderScanner cleanup pass — stale row 自愈（2026-05-10）

- [x] (2026-05-10 / `3914a01` / scan cleanup) **离线移动 stale row 自动清**：装新 build → 重启 Glance → 等首次 scan 完 → console 应有 `[FolderScanner] cleanup folderId=N: removed M stale rows (offline delete/move)` log → 「全部最近」原本卡 spinner 的 `00-cover.png` / `05-card-05.png` 等 cell 应消失（被 cleanup pass 删了 stale row） ✓ 2026-05-22
- [x] (2026-05-10 / `3914a01` / scan cleanup) **当前用户库直接修复**：你目前库里的 stale row（id=42 / id=43 等）应在重启后第一次 scan 完成时被清掉；不需要手动跑 SQL ✓ 2026-05-22
- [x] (2026-05-10 / `3914a01` / scan cleanup) **离线删除文件 → 重启清行**：app 关闭状态下在 Finder 删某 managed folder 里的图 → 重启 Glance → 等 scan 完 → grid 应不再显示该图（cleanup pass 删 row） ✓ 2026-05-22
- [x] (2026-05-10 / `3914a01` / scan cleanup) **resume 场景不误删**：扫描中途 Cmd+Q（cursor 写入）→ 重启自动 resume → 完成 resume 后**不应**触发 cleanup（resumeFrom != nil 时跳过 cleanup pass）；已 indexed 的图保留 ✓ 2026-05-22
- [x] (2026-05-10 / `3914a01` / scan cleanup) **dedup canonical 自动重定位**：cleanup 删了 stale row 后 `triggerDedupFullPass` 自动重跑（registerAndScan 末尾已挂）→ canonical 在剩余 row 间重新决策，grid 正确显示 ✓ 2026-05-22

### Slice I 启动双 loading 闪屏 fix（2026-05-09 · 修法 2 方案 5 落地）

- [x] (2026-05-09 / `5f1e365` / Slice I bugfix v2) **启动 grid 不闪 · 核心**：冷启动 Glance（多 root 已索引场景）→ 主区显示 grid 后**不应再消失/重新出现**。允许 progress chip 短暂出现（FSEvents 增量），但 grid 本身始终保留旧数据，无空白闪烁 ✓ 2026-05-22
- [x] (2026-05-09 / `5f1e365` / Slice I bugfix v2) **手动切 SF 立即清空**：在「全部最近」grid 浏览中 → 点 sidebar「本周新增」→ grid 应**立刻清空 + loading**（不 carry「全部最近」的 stale 数据），新 SF 数据出来后填充。验证 select(不同 SF) 时不 carry stale 的语义 ✓ 2026-05-22
- [x] (2026-05-09 / `5f1e365` / Slice I bugfix v2) **同 SF refresh 不闪**：选中某 SF → 后台触发 refresh（如 Finder 拖图进 managed folder 触发 FSEvents → onIndexChanged → refreshSelected）→ grid 中旧 cell **不应消失**，新数据回来后无缝替换 ✓ 2026-05-22
- [x] (2026-05-09 / `5f1e365` / Slice I bugfix v2) **空库首启动仍走 emptyState**：`rm -rf` DB → 启动 → 加首个 root → 空库阶段 SmartFolderGridView 应正常显示 emptyState（"暂无图片"）；扫完后 grid 出图。验证 stale=`[]` + loaded([]) 两条空路径都触发 emptyState ✓ 2026-05-22
- [x] (2026-05-09 / `5f1e365` / Slice I bugfix v2) **stale cell 点击行为**：grid loading 期间快速点 stale cell（启动后 1 秒内）→ 行为应是预览旧 image（不崩、不 nil 错误），即使该 image 在 refresh 后已被 dedup 清除。trade-off 验证：codex 标的 race 接受度 ✓ 2026-05-22
- [x] (2026-05-09 / `<pending>` / Slice I bugfix) **启动单次 loading**：冷启动 Glance（不要 `rm -rf` DB，确保有 root + 已索引数据）→ 主区只看到 1 次 loading 过渡（idle → loading → loaded）就显示 grid，不应再"loading 完→消失→又 loading 一下→出图"两次循环 ✓ 2026-05-22
- [x] (2026-05-09 / `3ad6f1f` / Slice I bugfix) **首次启动空库**：`rm -rf "$HOME/Library/Containers/com.sunhongjun.glance/Data/Library/Application Support/Glance/"` → 启动 → 加 root → 等扫完。期间应只在 scan + dedup 完成那一刻看到 loading（不应启动瞬间就 loading 一次再 loading 一次） ✓ 2026-05-22
- [x] (2026-05-09 / `3ad6f1f` / Slice I bugfix) **添加 root 后 grid 自动出图**：app 已启动且选中"全部最近"→ Cmd+O 或拖 Finder 文件夹添加新 root → 等扫完（含 dedup pass）→ grid 自动反映新 root 的图。验证 onIndexChanged → refreshSelected 链路在添加路径仍工作（修法删了手动 refresh，全靠 bridge 内部 triggerDedupFullPass 的回调） ✓ 2026-05-22
- [x] (2026-05-09 / `3ad6f1f` / Slice I bugfix) **删除 root 后 grid 自动清理**：删 root（V1 sidebar 右键移除）→ grid 自动从"全部最近"清掉该 root 的图。验证 unregister → triggerDedupFullPass → onIndexChanged 链路仍工作 ✓ 2026-05-22

### V2 M3 Slice L（2026-05-11）— 3 个新内置 SmartFolder

- [x] (2026-05-11 / `<pending>` / Slice L) **Sidebar 显示 5 个内置 SF**：app 启动 → sidebar 顶部智能文件夹区按顺序看到「全部最近」/「本周新增」/「上个月」/「截图」/「大图」5 条 ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / Slice L) **「上个月」自然月边界**：点击「上个月」→ grid 显示库里所有 birth_time 落在上个自然月（1 号 00:00 到本月 1 号 -1s）的图；跨年场景：1 月点开看到上年 12 月的图（如有） ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / Slice L) **「截图」筛选**：库里有任一 filename 含 "Screenshot" 或 "截图" 的图 → 点开看到，按 birth_time 倒序；不含这两个 keyword 的图不在结果里 ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / Slice L) **「大图」筛选**：库里有任一文件 >5MB 或 width>4000 且 height>4000 的图 → 点开看到，按 birth_time 倒序 ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / Slice L) **空结果空态**：3 个新 SF 任一在小库下可能空结果 → 显示已有 SmartFolderGridView emptyState，不崩 ✓ 2026-05-22

### V2 M2 Slice K（2026-05-11）— V2.1 GA polish

- [x] (2026-05-11 / `<pending>` / Slice K.1) **Vision revision 迁移正常启动**：app 启动正常进 grid，不应弹出"Vision 模型已更新"banner（除非真的 macOS Vision revision 变了）；启动延迟无感知（≤200ms 额外开销） ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / Slice K.1) **Vision revision 迁移 mock 测**：终止 app → `sqlite3 ~/Library/Containers/com.sunhongjun.glance/.../index.sqlite "UPDATE images SET feature_print_revision = 0 WHERE feature_print IS NOT NULL LIMIT 5;"` 改 5 行 stale revision → 重启 app → 应看到 banner "Vision 模型已更新，正在重新索引 5 张图片"；fp progress chip 应出现并完成 ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / Slice K.2) **失败重试 polish**：临时让某张图不可读（`chmod 000`）→ FeaturePrintIndexer 应不立刻把它标 supports_feature_print=0；改回 `chmod 644` → 同 session 内能恢复索引；超过 3 次仍失败 → 标 unsupported（找类似按钮 disable） ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / Slice K.3) **错误 banner 文案**：触发任一 fp 错误（mock SQLite IO 失败 / Vision 不支持等）→ banner 文案是"类似图特征索引...失败"风格，不是旧"feature print"技术 jargon ✓ 2026-05-22

### Focus 架构父持有重构（2026-05-11）

D15 终态落地（共享 `@FocusState focusTarget: AppFocus?` enum）。下列 7 条覆盖所有焦点路径，**任何一条** 方向键 / Space / ESC 静默 = 焦点 race，回滚。

**首测发现的关键回归 + follow-up fix（已修，需重测）**：bdb8307 后 preview 第二次方向键失焦（rebuild + @FocusState binding 时序 race），followup 删 ContentView 上 ImagePreviewView 的 `.id(idx)` 修复（codex:rescue 验证）。**重点验证**：preview 内连续按方向键 ≥ 10 次切图，每次都应即时切换无静默；同时 ESC 在任意切图后仍能退出。

- [x] (2026-05-11 / `<pending>` / refactor) **Focus 路径 1 — V1 grid 双击 → QV → ESC**：V1 单文件夹 grid → 双击 cell A → QV → ESC → 焦点回 grid，按方向键能移 highlight，按 Space 能再进 QV ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / refactor) **Focus 路径 2 — V1 grid 单击 → preview → ESC**：单击 cell A → preview → ESC → 焦点回 grid，方向键 / Space 能用 ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / refactor) **Focus 路径 3 — V1 grid → preview → 双击 → QV → ESC ×2**：单击 cell A → preview → 双击 → QV → ESC → 焦点回 preview，方向键能切预览；再 ESC → 焦点回 grid，方向键能用（关键回归点：5b29600 / 59a9d86 race） ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / refactor) **Focus 路径 4 — Ephemeral → QV → ESC ×2**：QV → 找类似 → ephemeral → 双击 → QV → ESC → 焦点回 ephemeral，方向键能在 ephemeral grid 切 highlight；再 ESC → 焦点回 baseGrid（D8 amendment 分层 modal 行为） ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / refactor) **Focus 路径 5 — Ephemeral → preview → ESC**：ephemeral → 单击 cell → preview → ESC → 焦点回 ephemeral，方向键能在 ephemeral 切 highlight ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / refactor) **Focus 路径 6 — V2 SmartFolder 全路径重测**：sidebar 选「全部最近」→ 重测路径 1-5（V2 grid 走 SmartFolderGridView 路径） ✓ 2026-05-22
- [x] (2026-05-11 / `<pending>` / refactor) **Focus 路径 7 — 切文件夹强关 QV**：QV 打开 → sidebar 点其他文件夹 → QV 自动关闭 → 焦点应回新文件夹的 grid，方向键能用 ✓ 2026-05-22

### V2 M3 Slice M（2026-05-11）— 全局搜索

- [x] (2026-05-11 / `d315c78` / Slice M) **⌘F 入口 — baseGrid**：sidebar 选「全部最近」grid 状态按 ⌘F → SearchOverlayView 顶部滑入，input 自动 active，可立即输入 ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **⌘F 入口 — preview**：单击 cell 进 preview 后按 ⌘F → overlay 出，preview 仍 visible（z-index 区分） ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **⌘F 入口 — ephemeral**：找类似 ephemeral 状态按 ⌘F → overlay 替换显示，ephemeral 转换为 search ephemeral ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **⌘F 入口 — QV**：双击 cell 进 QV 后按 ⌘F → QV 同帧关 + overlay 出（视觉一帧切换） ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **keyword 基础搜索**：输入 "screen" → 200ms 后 EphemeralResultView 出结果，filename + relative_path LIKE 命中均显示，按 birth_time 倒序 + 时间分段 chip header ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **modifier type**：输入 "type:png" → 仅 PNG 文件结果 ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **modifier size**：输入 "size:>1mb" → 仅 >1MB 文件结果 ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **modifier birth**：输入 "birth:>2026-04-01" → 仅 birth_time > 2026-04-01 文件结果 ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **modifier 混合 AND**：输入 "screen type:png size:>500k" → 三条件 AND 命中 ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **Silent partial fallback**：输入 "screen type:invalidext" → 整 token "screen type:invalidext" 当 keyword LIKE（结果可能 0，不报错）；输入 "foo size:abc" → 整 token fallback keyword（结果可能 0） ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **Hidden 继承**：右键 hide 某 folder → 搜索其内 filename 应不出现（D18） ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **焦点回归**：ESC overlay → baseGrid 立即响应方向键 / Space（D15 单仲裁回归 .grid） ✓ 2026-05-22
- [x] (2026-05-11 / `d315c78` / Slice M) **M2 找类似回归**：QV 内点找类似 → EphemeralResultView showTimeBuckets=false 维持 flat LazyVGrid + "无结果" 文案（如空结果），cell 单击/双击行为不变 ✓ 2026-05-22

- [x] (2026-05-07 / `79fcfdf`) **F 键全局 · grid**：grid 模式 → 按 F → 窗口全屏（traffic lights 隐藏）；再按 F → 退出全屏 ✓ 2026-05-07
- [x] (2026-05-07 / `79fcfdf`) **F 键全局 · preview**：单击 cell 进 preview → 按 F → 窗口全屏；再按 F → 退出全屏 ✓ 2026-05-07
- [x] (2026-05-07 / `79fcfdf`) **F 键全局 · QV 回归**：双击 cell 进 QV → 按 F → 全屏；再按 F → 退出全屏（行为不变，跟修前一致） ✓ 2026-05-07
- [x] (2026-05-07 / `79fcfdf`) **F 键全局 · 不冲突其他快捷键**：grid 方向键/Space 仍正常；preview ESC/Space/方向键仍正常 ✓ 2026-05-07
- [x] (2026-05-07 / `02a36dc`) **Bug 4 扩展 · 路径 1 核心**：grid 双击 cell A 进 QV → 方向键到 Z → ESC 退 QV → grid highlight 跟到 Z（修前停在 A）✓ 2026-05-07
- [x] (2026-05-07 / `02a36dc`) **Bug 4 扩展 · 路径 2 preview 跟到 Z**：grid 单击 A 进 preview → 双击进 QV → QV 方向键到 Z → ESC 退 QV → preview 显示 Z（修前显示 A）✓ 2026-05-07
- [x] (2026-05-07 / `02a36dc`) **Bug 4 扩展 · 路径 2 grid highlight 跟到 Z**：续上 → 再 ESC 退 preview → grid highlight 跟到 Z ✓ 2026-05-07
- [x] (2026-05-07 / `3cdb991`) **QV colorScheme env · Path A 核心**：浅色模式 → grid → 直接双击 cell → QV (深色) → ESC 退 → sidebar 保持浅色，不再变深灰（修前 g1.png 现象）✓ 2026-05-07
- [x] (2026-05-07 / `3cdb991`) **QV colorScheme env · Path B 核心**：浅色模式 → grid → 单击 cell 进 preview → 双击 → QV (深色) → ESC 退 → 整个 app 保持浅色（preview / sidebar / 文件名 toolbar 全浅色，修前 g2.png 现象）✓ 2026-05-07
- [x] (2026-05-06 / `2b858cf`) **跟随系统外观模式生效**：菜单依次切「跟随系统」/「强制深色」/「强制浅色」/「跟随系统」 → 每次都立即生效；切「跟随系统」后系统切深浅 → app 跟着切；重启 app 保留上次模式选择；进 QuickViewer 仍强制深色（局部覆盖不受影响）✓ 2026-05-06
- [x] (2026-05-06 / `dcabffc`) **light 模式 chrome / 内容区对比**：切到 light 模式 → 内容区为纯白 (#FFFFFF) / 侧边栏为浅灰 (#F2F2F7)，对比方向跟 dark 模式一致（内容区是焦点更亮）；dark 模式视觉不变 ✓ 2026-05-06
- [x] (2026-05-06 / `20fa509`) **关于窗口跟随主窗口居中**（方案 2 真解 NSWindow，方案 1 e2e0d21 SwiftUI Window onAppear 有 A→B 跳跃已弃）：挪动主窗口到屏幕任意角落 → 菜单栏 → 关于一眼 → 关于窗口出现在主窗口中心，零跳跃；多次开关后位置仍跟随 ✓ 2026-05-06
- [x] (2026-04-23 / `68042e0`) **拖拽**：从 Finder 拖一个文件夹到侧边栏 → 出现在列表、自动选中、badge 正常、重启 app 后 bookmark 仍有效 ✓ 2026-04-23
- [x] (2026-04-23 / `68042e0`) **拖拽**：多选 2+ 文件夹一次拖入 → 全部加入；当前选中不变（不跳到新拖入的）✓ 2026-04-23
- [x] (2026-04-23 / `68042e0`) **拖拽**：拖一个已加过的文件夹 → 跳到选中它；`rootFolders` 不重复 ✓ 2026-04-23
- [x] (2026-04-23 / `68042e0`) **拖拽**：拖单张图片 / 文档文件（非目录）到侧边栏 → 静默无反馈（不出错、不加任何条目）✓ 2026-04-23
- [x] (2026-04-23 / `68042e0`) **拖拽**：拖拽悬停侧边栏时 → 紫色描边框可见；移出 → 平滑消失（约 150ms）✓ 2026-04-23
- [x] (2026-04-23 / `68042e0`) **拖拽**：拖到内容区（ImageGridView / ImagePreviewView）→ 无效（Finder 显示拒绝动画）✓ 2026-04-23
- [x] (2026-04-23 / `4f9fb18`) **QuickViewer**：大图（如手机照片 / 4K 截图）双击进入 → 缩到窗口约 90% 占比，四周留呼吸边（不再呆中间 30-40%）✓ 2026-04-25
- [x] (2026-04-23 / `4f9fb18`) **QuickViewer**：Retina 截图（如 macOS 原生截图 2x 像素）进入 → 同样约 90% 窗口占比，不再 39% 小块 ✓ 2026-04-25
- [x] (2026-04-23 / `4f9fb18`) **QuickViewer**：中等图（原生略小于窗口，如 1200×800）进入 → **显示 1:1 原生**（zoomPercent 100%），居中，不强拉伸 ✓ 2026-04-25
- [x] (2026-04-23 / `4f9fb18`) **QuickViewer**：小图 / 图标（如 64×64 favicon）进入 → 原生 1:1 居中显示（小块在中间），**不被拉伸变糊**；用户可滚轮 / 捏合主动放大 ✓ 2026-04-25
- [x] (2026-04-23 / `4f9fb18`) **QuickViewer**：双击图片 toggle → fit（90% 或 1:1）↔ 1:1（scale=1.0）切换流畅；1:1 时像素清晰 ✓ 2026-04-25
- [x] (2026-04-23 / `4f9fb18`) **QuickViewer**：放大到超出窗口 → 拖拽平移 / 滚轮缩放正常，边界不漏白（`clampOffset` 与新渲染对齐）✓ 2026-04-25
- [x] (2026-04-25 / `98573e9`) **QuickViewer 拖拽**：1:1 mode 下大图（超出窗口）→ 鼠标拖动图跟随移动，自然不抖动，能看到原本被裁掉的部分 ✓ 2026-04-25
- [x] (2026-04-25 / `98573e9`) **QuickViewer 拖拽**：拖到图边界 → 不漏白（clampOffset 兜底，图边贴窗口边停）✓ 2026-04-25
- [x] (2026-04-25 / `98573e9`) **QuickViewer 拖拽**：fit mode 图 ≤ 窗口 → 拖动无响应（canPan = false 正确，不应有抖动副作用）✓ 2026-04-25
- [x] (2026-04-25 / `98573e9`) **QuickViewer 拖拽**：双击 toggle fit ↔ 1:1 仍流畅；toggle 后再拖动行为仍正确 ✓ 2026-04-25
- [x] (2026-04-25 / `0e3ec10`) **QuickViewer 拖拽 y 方向**：鼠标向上拖 → 图向上移动；鼠标向下拖 → 图向下移动（修复 98573e9 后 y 方向反了的 follow-up）✓ 2026-04-25
- [x] (2026-04-25 / `4855e40`) **预览页**：选中文件夹 → 单击缩略图进入内嵌预览 → 按方向键 ←→ 连续切换 → 切换瞬间不应再出现 loading 转圈（首张可能仍转一下，第二张起命中预加载缓存即时显示）。**之前 868271d / c7a1533 都没修对，4855e40 才是根因修复（vm 提到 ContentView 跨 .id 重建持续）** ✓ 2026-04-25
- [x] (2026-04-25 / `4855e40`) **预览页**：单击进预览 → 双击进 QuickViewer → Esc 退回预览 → 再用方向键切换 → 仍无转圈（focus 恢复 + 缓存正常工作）✓ 2026-04-25
- [x] (2026-04-25 / `4855e40`) **预览页**：在预览中切换文件夹（侧边栏点另一个） → 不应崩溃；旧缓存清空（ContentView 的 onChange(of: selectedFolder) 触发 previewVM.clearCache），新文件夹预览正常 ✓ 2026-04-25
- [x] (2026-04-25 / `4855e40`) **预览页（回归验证）**：单击/双击/Esc/Space/← →/关闭按钮 全部行为不变；n/m 进度、青绿光晕、底部"双击图片进入全屏查看"提示文案、左右导航气泡按钮 视觉无差 ✓ 2026-04-25
- [x] (2026-04-25 / `4855e40`) **预览页（排序回归）**：进预览 → 切换排序顺序（toolbar 排序菜单） → 当前预览图片应仍是同一张（按 URL 重映射 currentIndex），不应跳到错的位置（验证 commit 175e82a 的修复仍生效）✓ 2026-04-25
- [x] (2026-04-27 / `fb6231c`) **AppIcon · Dock**：启动 app → Dock 显示新图标（眼睛 Cool Violet 方向，紫底青绿瞳孔），不再是 Xcode 默认占位 ✓ 2026-04-27
- [x] (2026-04-27 / `fb6231c`) **AppIcon · Finder column 16px**：在 Finder 用 column 视图看 Glance.app → 16px 缩略图下眼睛形状仍可辨认（不糊成色块）✓ 2026-04-27
- [x] (2026-04-27 / `fb6231c`) **AppIcon · Get Info**：右键 .app → 显示简介 → 左上角图标显示完整图标 + 大尺寸预览清晰 ✓ 2026-04-27
- [x] (2026-04-27 / `fb6231c`) **AppIcon · 浅色 Dock**：系统切到浅色模式 → Dock 里图标过渡仍 OK（紫底在浅色 Dock 上不应过黑过硬）✓ 2026-04-27
- [x] (2026-04-27 / `fb6231c`) **AppIcon · 关于本机**：app 菜单栏 → 关于 Glance（中文系统：关于一眼）→ 弹窗左侧大图标显示新图标 ✓ 2026-04-27
- [x] (2026-04-27 / `8e6de41`) **重命名 · Dock 中文系统**：系统语言中文 → Dock hover Glance.app 显示「一眼」 ✓ 2026-04-27
- [x] (2026-04-27 / `8e6de41`) **重命名 · Dock 英文系统**：系统语言切到英文 → Dock hover 显示 "Glance" ✓ 2026-04-27
- [x] (2026-04-27 / `8e6de41`) **重命名 · 活动监视器**：打开 Glance.app → 活动监视器进程列表显示 "Glance"（不再是 ISeeImageViewer）✓ 2026-04-27
- [x] (2026-04-27 / `8e6de41`) **重命名 · 顶部菜单栏**：app 运行时屏幕顶部菜单栏第一项显示「一眼」/ "Glance" ✓ 2026-04-27
- [x] (2026-04-27 / `8e6de41`) **重命名 · Bookmark 重新授权**：旧 ISeeImageViewer 的 bookmark 已失效（Bundle ID 改了），重新拖文件夹进侧边栏可正常授权浏览 ✓ 2026-04-27
- [x] (2026-04-27 / `c112059`) **缩略图**：含同名不同后缀文件夹（如 4.jpg + 4.png）→ 点击各 cell（含相邻同基名两张）→ 视觉点的就是预览出的，多次切换不漂移 ✓ 2026-05-04
- [x] (2026-04-27 / `c112059`) **排序**：切换排序后再点缩略图 → 视觉与预览一致（之前 ScrollView `.id(sortKey-direction)` 强制重建已删，要确认 LazyVGrid 自身能正确响应数组重排）✓ 2026-05-04
- [x] (2026-05-04 / `44ba6ee`) **缩略图 · 双击 highlight 跟随**：先单击 cell A（highlight 在 A）→ 双击 cell B 进 QuickViewer → ESC 退 QuickViewer → highlight 应**已在 B** ✓ 2026-05-04
- [x] (2026-05-04 / `44ba6ee`) **缩略图 · 上下方向键步长**：刚启动选中文件夹后不碰任何 cell，按 ↓ 高亮第二行同列 cell；按 ↑ 反之；Inspector 开关后步长仍正确 ✓ 2026-05-04
- [x] (2026-05-04 / `44ba6ee`) **缩略图 · 上下方向键边界**：↑ 到第一行后再 ↑ 停在最左 cell；↓ 到最后一行后再 ↓ 停在最末 cell ✓ 2026-05-04
- [x] (2026-05-04 / `5b29600`) **缩略图 · ESC 后焦点恢复（Y-1）**：单击 cell A 进 preview → ESC → 按方向键 highlight 在 grid 内正常移动 ✓ 2026-05-04
- [x] (2026-05-04 / `5b29600`) **缩略图 · ESC 后焦点恢复（Y-2）**：同上链路反复测试不再"反而弹出下一张预览" ✓ 2026-05-04
- [x] (2026-05-04 / `5b29600`) **缩略图 · ESC 后 Space**：单击 cell A 进 preview → ESC → Space → 进 QuickViewer 显示 highlight 那张 ✓ 2026-05-04
- [x] (2026-05-04 / `5b29600`) **预览页 · ESC 退出回归**：preview 内 ←→ / Space / 双击 / 关闭按钮 全部正常 ✓ 2026-05-04
- [x] (2026-05-04 / `59a9d86`) **缩略图 · QV dismiss 后 grid 焦点（核心 case）**：单击 → preview → ESC → Space → QV → ESC → Space / 方向键正常 ✓ 2026-05-04
- [x] (2026-05-04 / `59a9d86`) **缩略图 · grid 直接双击进 QV 后 ESC**：直接双击 → QV → ESC → 方向键 / Space 正常 ✓ 2026-05-04
- [x] (2026-05-04 / `59a9d86`) **预览 → QV → preview 路径**：单击 → preview → 双击图片 → QV → ESC → 回 preview，方向键切预览图正常 ✓ 2026-05-04
- [x] (2026-05-04 / `59a9d86`) **切换文件夹强制关 QV**：QV 中点侧边栏另一文件夹 → QV 自动关，焦点不崩 ✓ 2026-05-04
- [x] (2026-05-04 / `59a9d86`) **ImagePreviewView 关闭按钮回归**：单击进 preview → 点左上 X → 退回 grid → 方向键 / Space 正常 ✓ 2026-05-04
- [x] (2026-05-05 / `09c418c`) **自定义关于面板 · 无 focus ring 残留**：点击 contact 行 → 复制 + toast → 该行无 accent color 细描边 / focus ring 残留 ✓ 2026-05-05
- [x] (2026-05-04 / `fb7f900`) **QuickViewer filmstrip · 点击命中**：点 cell A → 高亮 + 主图都跳到 A，不漂移；多位置反复测过 ✓ 2026-05-05
- [x] (2026-05-04 / `fb7f900`) **QuickViewer filmstrip · scrollTo 跟随**：方向键切图 filmstrip 自动滚到当前 cell 居中 ✓ 2026-05-05
- [x] (2026-05-04 / `fb7f900`) **QuickViewer filmstrip · 缩略图加载**：快切 ←→ 缩略图不错位（.task(id:) + cancel guard 工作）✓ 2026-05-05
- [x] (2026-05-04 / `38adfd4`) **关于面板版本号注入**：版本号显示 commit hash 格式，多次 build 递变 ✓ 2026-05-05
- [x] (2026-05-04 / `38adfd4`) **BuildInfo.txt sidecar 同步**：`cat ~/sync/Glance.app.BuildInfo.txt` 7 字段齐全 ✓ 2026-05-05
- [x] (2026-05-05 / `8f927d1`) **自定义关于面板 · 弹窗触发**：菜单触发自定义窗口（非系统 NSAboutPanel），AppIcon / 名称 / 版本号 / 两行 contact 完整 ✓ 2026-05-05
- [x] (2026-05-05 / `8f927d1`) **自定义关于面板 · 点击复制 + toast**：hover 手指 cursor / 点击复制 / toast / ⌘V 粘贴验证 ✓ 2026-05-05
- [x] (2026-05-05 / `8f927d1`) **自定义关于面板 · 版本号动态读取**：关于窗口版本号字符串与 BuildInfo.txt version 字段一致 ✓ 2026-05-05

### V2 M2 Slice J 已验证（2026-05-11）

- [x] (2026-05-11 / `49c0223` / Slice J) **索引完成后 chip 自动消失** ✓ 2026-05-11
- [x] (2026-05-11 / `49c0223` / Slice J) **索引中点 chip X 按钮 cancel 生效，chip 立刻消失** ✓ 2026-05-11
- [x] (2026-05-11 / `49c0223` / Slice J) **QV「找类似」按钮 → 切到 EphemeralResultView 显示 30 张** ✓ 2026-05-11
- [x] (2026-05-11 / `49c0223` / Slice J) **EphemeralResultView 顶 X 按钮 / ESC 键退出回 baseGrid** ✓ 2026-05-11
- [x] (2026-05-11 / `cd632b8` / Slice J ESC 状态机 fix) **ephemeral 单击进 preview，ESC 退回 ephemeral 视图（不直接回 baseGrid）** ✓ 2026-05-11
- [x] (2026-05-11 / `cd632b8` / Slice J ESC 状态机 fix) **ephemeral 双击进 QV，ESC 退回 baseGrid（不回 ephemeral 视图，路径 1 兼容性）** ✓ 2026-05-11
- [x] (2026-05-11 / `49c0223` / Slice J) **全库索引完成时（indexed = total）banner 不显示** ✓ 2026-05-11
- [x] (2026-05-11 / `49c0223` / Slice J) **启动后 feature print indexer 自动开抽（chip 显示 "正在索引相似度 X / Y"）** ✓ 2026-05-11（reset SQL + 重启验证 chip 出现 + 数字递增）
- [x] (2026-05-11 / `49c0223` / Slice J) **部分库时 banner 显示"已索引 X / Y 张，结果为部分库"** ✓ 2026-05-11（用户判读通过）
- [x] (2026-05-11 / `49c0223` / Slice J) **添加新文件夹 → FSEvents 派发 → fp indexer 自动 enqueue** ✓ 2026-05-11（用户判读通过）
- [x] (2026-05-11 / `49c0223` / Slice J) **关 app 中途取消 fp indexer → 重启自动 resume** ✓ 2026-05-11（用户判读通过）
- [x] (2026-05-11 / `49c0223` / Slice J) **unsupported 格式（RAW / SVG）→ supports_feature_print=0 跳过，不阻塞 pipeline** ✓ 2026-05-11（用户判读通过）
- [x] (2026-05-11 / `<pending QV tooltip fix>` / Slice J) **QV 按钮 disable + hover tooltip "该格式暂不支持类似图查找"** ✓ 2026-05-11（按钮 disable 视觉验证 ✓；hover tooltip 在删 `.allowsHitTesting(false)` 后理论可见，用户未亲测；若回归再 reopen）
- [⊗] (2026-05-11 / deferred / Slice J · perf) **1 万图典型库索引耗时（M1 mac 实测）**：未实测，deferred — 实际跑大库时回填
- [⊗] (2026-05-11 / deferred / Slice J · perf) **找类似查询响应耗时（10k 库）**：未实测，deferred — 实际跑大库时回填

---

### V2 菜单栏增补 第一批 — 文件/编辑/显示/图像/窗口 16 项 + 框架(2026-06-18 ship 待真机验)

> 第一批 ship 5 commit `211428e` (A+B 合并) → `88f190f` (B 修补) → `6ae4d96` (C) → `bd4b929` (D) → `b9b8370` (E) + F 文档 commit (待提交)。verify.sh 三段全过(14/14, build 0 error 0 warning), 任务 A+B 合并 3 轮 self-fix (import Combine) / 任务 C/D 0 self-fix / 任务 E 1 self-fix (commit-msg 术语 hook)。design v2.1 commit `a6a216b` → plan v1.1 commit `d789e60` (codex v1 RESHAPE → v2 APPROVE-WITH-FIXES → v2.1 收紧 + plan codex 3 P0 修, 共 3 轮 codex review); 方向 Y 零 .keyboardShortcut, 文本字符串 hint (D-mb-3 / D-mb-7); 第二批全屏 + 共享快捷键路由方向决策 留 design v3。

军哥本机肉眼验项:

**任务 A 框架 spike (1 项)**:
- [ ] (2026-06-18) **closure registry + commands @ObservedObject disable binding**: 启动 app → 窗口菜单看「图库主窗」disable/enable 随 hasWindow 切换 (此项任务 B 完成时实际等价于 R-mb-1 验证)

**任务 B 文件 + 窗口菜单 (2 项)**:
- [ ] (2026-06-18) **文件菜单 添加文件夹根…**: 文件菜单看见「添加文件夹根…」→ 点击弹 NSOpenPanel → 选目录 → 侧边栏出现新文件夹根
- [ ] (2026-06-18) **窗口菜单 图库主窗 reopen**: ⌘W 关主窗驻留 → 窗口菜单看「图库主窗」(主窗在时此项 hide) → 点击 reopen 主窗 + 数据状态恢复

**任务 C 编辑菜单 (4 项)**:
- [ ] (2026-06-18) **编辑菜单 3 项可见**: 编辑菜单看「查找…  (⌘F)」/「复制图片  (⌘C)」/「复制路径  (⌘⌥C)」(快捷键 hint 字符串拼在文本里)
- [ ] (2026-06-18) **主窗状态 复制项 disable**: 主窗状态下复制图/复制路径 灰显; 查找永远 enable
- [ ] (2026-06-18) **快速看图器在场 复制项 enable**: 双击进快速看图器 → 编辑菜单复制图/复制路径 enable → 点击 = 复制到 NSPasteboard (Slack/Finder/备忘录粘贴有图)
- [ ] (2026-06-18) **查找菜单 = ⌘F 等效**: 点编辑菜单查找… = 主窗弹 search overlay (跟按 ⌘F 一样); 按 ⌘F 仍弹 (现状不变, 不双触发)

**任务 D 图像菜单 (5 项)**:
- [ ] (2026-06-18) **图像菜单 6 项可见**: 顶部菜单栏出现「图像」顶级菜单 (位置 = 显示和窗口之间, R-mb-16 验证)
- [ ] (2026-06-18) **主窗状态 6 项全 disable**: 主窗状态下旋转/翻转/Finder/废纸篓 全灰
- [ ] (2026-06-18) **快速看图器在场 6 项全 enable**: 双击进快速看图器 → 6 项全 enable
- [ ] (2026-06-18) **菜单各项执行**: 点旋转左 = 图旋转 90° (跟 L 一样); 点 Finder = 弹 Finder 反白; 点移到废纸篓 = 走 trash flow + 弹撤销 toast
- [ ] (2026-06-18) **快捷键 hint 字符串**: 菜单文本里看到「(L)」/「(R)」/「(⌘⇧R)」/「(⌫)」字符串

**任务 E 显示菜单 (4 项)**:
- [ ] (2026-06-18) **显示菜单 5 项可见**: 显示菜单看「显示信息  (⌘I)」+ 缩放 4 项 (适合/1:1/放大/缩小, R-mb-15 验证位置 = sidebar 系统子菜单之后)
- [ ] (2026-06-18) **主窗未选图 信息项 disable**: 主窗状态下未选图时显示信息 灰
- [ ] (2026-06-18) **Inspector 切换动态文案**: 双击进快速看图器 + 切 Inspector → 显示菜单文案切「显示信息 / 隐藏信息」(D-mb-8 动态)
- [ ] (2026-06-18) **缩放系列 disable + enable**: 主窗状态缩放 4 项 全 disable; 快速看图器在场全 enable; 点适合窗口 = QV 适合 (跟按 ⌘0 一样)

**通用 (4 项)**:
- [ ] (2026-06-18) **菜单结构 5 顶级 + 16 项**: 5 顶级菜单 (文件/编辑/显示/图像/窗口) + 16 项菜单, 数量对照表正确
- [ ] (2026-06-18) **零键盘干扰**: app 内按 L 仍只在快速看图器内旋转, 主窗按 L 无反应 (现状不变); 按 ⌘C 仍只在快速看图器内复制图, 主窗按 ⌘C 无反应 (D-mb-3 方向 Y 已知设计选择)
- [ ] (2026-06-18) **改 .commands 必须重启验证 (R-mb-12)**: 真机改菜单结构后 Xcode preview hot reload 不刷新, 必须实际 cmd+Q 重启 app
- [ ] (2026-06-18) **a11y VoiceOver**: VoiceOver 读菜单项 + 快捷键 hint (例「复制图片 Command C」), 体验可接受 (D-mb-7 trade-off)

---

### V2 快速看图器删图误关窗 bug fix — 4 项全过 ✓(2026-06-18 ship `9d65f65` + 军哥真机验)

> bug fix ship `9d65f65`, 军哥真机肉眼验全过 (1.png 203 张图删 1 张窗口保留 + 2.png 点撤销 toast 切「文件恢复 列表稍后刷新」). 根因: ContentView V1 时代 `.onChange(of: folderStore.images)` 在 QV-toolbar Slice1 迁独立 NSWindow 后变 stale, FSEvents 触发 folderStore.images 减 1 → 误关窗。修法: codex Option 3 加强版 — `MainQuickViewerWindowController` 加 `currentImageURLProvider` closure registry; ContentView .onChange 收紧为「QV 当前看的图不在新列表 / 新列表空」才关窗。

军哥真机肉眼验项 (全过):
- [x] (2026-06-18 / `9d65f65`) **删 1 张图不再关窗**: 14+ 张图(实测 203 张) 进快速看图器删 1 张 → 自动跳下一张 + 窗口保留 + 右下角弹「已移废纸篓 撤销」toast 5 秒 ✓
- [x] (2026-06-18 / `9d65f65`) **点撤销文件恢复**: toast 点撤销 → 文件回原位 + toast 切「⚠ 文件恢复，列表稍后刷新」红色 ✓
- [x] (2026-06-18 / `9d65f65`) **删到最后 1 张关窗 (D40)**: 1 张文件夹删完自动关 ✓
- [x] (2026-06-18 / `9d65f65`) **排序场景不关窗** (codex 论证行为变更): 在快速看图器内时主窗排序变化, 窗口保持显示 ✓

⚠️ 第二批 (全屏菜单 + 共享快捷键路由方向决策) 留 design v3, 本次第一批 ship 后用户反馈 1-2 周再决定。
