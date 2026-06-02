---
description: 任务收尾 5 步 — verify 三段 / 文档同步 / PENDING / commit+push / 汇报
---

任务收尾必跑。5 步依次执行，不得跳步、不得草率。

## Scope 例外（先判断）

**0 个 `.swift` 变化**（纯文档 / specs / scripts / .githooks / Makefile 改动）→ **跳 Step 1**，commit message 末尾加 `[docs-only]` 标签，直接进 Step 2-5。

pre-push hook 本身已对 docs-only 短路跳过 codex，`[docs-only]` 是给未来 reviewer 看的语义标签。

---

## Step 1: 三段式 verify（stop on red）

```bash
./scripts/verify.sh
```

三段成本递增：
- **Stage 1 静态规则**（毫秒）：grep/awk 扫 `.swift` + 文档同步 + git hygiene
- **Stage 2 编译**（30-60s）：`xcodebuild build -quiet`，0 error 才过；warning 非阻塞但必须修
- **Stage 3 单测**（暂 skip，项目无 XCTest target）

**红 → 修代码 → 重跑，最多 5 轮**。

每轮必须实际修代码，不允许改 `verify.sh` / 改规则 / 加 exception 来绕过。规则是死的，违反就是违反了。

5 轮仍红 → 停下，向用户说明：
- 哪一段卡住
- 每轮做了什么修复
- 为什么没修掉
- 你的判断：是规则需要调整，还是需要用户介入

**Warning 观察口子**：Stage 2 成功但有 warning → 不 FAIL 但必须在 Step 5 汇报里列出并说明"下次修掉"或"这次一并修了"。全局规则"没有引入新 warning"是强制的。

## Step 2: 文档同步

对照本次 `.swift` diff，按 `CLAUDE.md` 的「⚠️ 文档同步强制规则」检查：

| 改动类型 | 必改文档 |
|---|---|
| Bug fix | `specs/Roadmap.md` Bug Fix 记录加行（commit hash 可先占位 `<pending>`） |
| 新/删/移 `.swift` 文件 | `CLAUDE.md` 文件结构更新 |
| 完成模块或子功能 | `specs/<module>.md` 当前进度更新 |
| 模块进入已完成 | `specs/Roadmap.md` 已完成表格加行 |
| 架构/交互逻辑变化 | `specs/Roadmap.md` 关键架构决策更新 |

需要更新的文档一起 staged 进同一个 commit。pre-push hook 的文档同步 P1 规则会在 push 时独立校验 —— 这是第二道防线。

## Step 3: PENDING 维护（先 review 老项，再追加新项）

### Step 3.a: Review 老 pending 项（防止 Pending 段无限膨胀 stale）

读 `specs/PENDING-USER-ACTIONS.md` Pending 段，按 H3 分组扫一遍。**对每个 ≥ 3 天前的 H3 段**：

- AskUserQuestion 或直接问："`<H3 标题>` 段 N 项，测过没？"
- 用户答**测过** → 整段挪 Done 段顶部新 `### 2026-MM-DD 批量补录` 子段（或 mirror 现有"V2 M2 Slice J 已验证（2026-05-11）"pattern 单独建段），每项 `[ ]` → `[x]` + 行末加 ` ✓ <YYYY-MM-DD>`
- 用户答**没测** → 整段留 Pending 不动
- 用户答**部分测** → 让用户点名哪些，逐项处理

**不假设用户记得，必须主动问**——这是流程纪律。2026-05-22 发现累积 ~170 项 stale 全压在 Pending 段，根因就是 CC 从来不主动问，全靠用户记忆维护。

**跳过条件**：
- 标 `/ deferred` 或 `Deferred` 的项不问（明确推后不测的 perf 验收 / 设计 polish，无验证义务）
- < 3 天前刚追加的项不问（用户还没来得及测）

### Step 3.b: 追加本次新项

不能自动验证的项**追加**到对应 H3 段（按 Slice / 模块归类；本次改动不属于既有 H3 就新建一个）。格式：

```markdown
- [ ] (YYYY-MM-DD / <短 hash>) **类别**: 具体怎么测，要看到什么现象
```

类别：启动 / 排序 / QuickViewer / 全屏外观 / Inspector / 缩略图 / 侧边栏 / 其他。

判断原则：**本次 `.swift` 改动可能影响的运行时行为 → 追加**；无关的不加。比如只改了 `ImageGridView` 的排序 bug，就只追加"排序交互"类别相关项，不追加 Inspector / QuickViewer 的。

commit hash 在 Step 4 commit 完成后回填到这里（先 `<pending>`，commit 后 edit 改成真的 hash）。

## Step 4: commit + push + post-commit sync

- `git add` **逐文件明确**（绝不 `git add -A` / `git add .`，避免带 `.DS_Store` / `xcuserstate` / 其他无关变更进 commit）
- commit message 简洁有信息量，docs-only 改动末尾加 `[docs-only]`
- `git push origin main` → 触发 `.githooks/pre-push`（codex 再 review 一次，独立 gate）
- hook 阻了 `[P1]` → 修 → 从 Step 1 重来（不要用 `--no-verify` 绕过，除非真的误报且你能写清误报理由）

### Post-commit sync（有 `.swift` 改动时强制，docs-only 跳过）

push 成功后**再跑一次** `./scripts/verify.sh` 让 `~/sync/Glance.app.BuildInfo.txt` 反映新 HEAD：

```bash
./scripts/verify.sh
```

**为什么必须**：Step 1 verify 是在 commit **之前**跑的（working tree 含改动但 HEAD 还是旧 commit），那次 sync 出去的 `BuildInfo.commit` 是**旧 commit + dirty=yes -d 标记**；Step 4 commit 后 HEAD 变成新 commit 但 `~/sync/` 没刷新，用户从关于面板看到的 commit hash 跟你汇报的 HEAD 对不上 → 用户以为没装新版（2026-05-07 toolbar fix 真实踩过这坑：HEAD `e39fbbf` 但 `~/sync/` BuildInfo 是 `086ade2-d`）。

**Scope**：
- 有 `.swift` 改动 → **必须** post-commit sync（不然 BuildInfo 元数据骗人）
- 纯 docs-only 改动 → 可跳（`.app` 二进制本来没变，BuildInfo 字段不刷新无害）

## Step 5: 一段话汇报

格式：

```
## /go 完成

- **编译**: ✓ BUILD SUCCEEDED — 0 errors, 0 code warnings；./build/Glance.app mtime <HH:MM>（HEAD commit time <HH:MM>，用户本地脚本可拉取）
- **~/sync/ 同步**: BuildInfo.commit = `<HEAD short hash>`（dirty: no）— 必须跟 HEAD 完全一致，不一致说明 Step 4 post-commit sync 漏跑（docs-only 跳过此行）
- **verify**: N 轮 self-fix（第 1 轮挂了 X，修 Y；第 2 轮 …）；最终 K passed / 0 failed
- **文档同步**: Roadmap Bug Fix 加 M 行 / CLAUDE.md 文件结构更新 / specs/<x>.md 当前进度前进到 …
- **PENDING 加 J 项**: <类别>（具体测什么）× J
- **commits**: <hash1> <标题>; <hash2> <标题>
- **pre-push hook**: CLEAN / 或 [P2] 警告（列出）
- **warning 观察**: Stage 2 build 有 N 条新 warning，已修 / 保留到下次（原因）
```

**工作流**：CC 在**开发机**写代码 + `./scripts/verify.sh` 跑 Stage 2 编译到 `./build/Glance.app`；用户在**本地机**通过脚本直接拉取 `./build/` 下的二进制到本地测试。CC 的责任终点 = `./build/.app` 必须是当前 HEAD 的产物，**不必**教用户怎么 open / Cmd+Q / make run —— 那是用户本地自动化的事。

**编译行是硬约束**：交付前必须显眼独立展示 `BUILD SUCCEEDED + 0 errors/warnings + ./build/.app mtime`，**禁止**仅用 verify 的 `11 passed / 0 failed` 数字替代。mtime 必须用 `stat -f %Sm -t %H:%M build/Glance.app/Contents/MacOS/Glance` 取**实时值**，证明二进制与当前 HEAD 一致，不是几小时前残留。

编译失败或有 warnings 时，编译行改成具体信息（错误数/前几条错误路径+行号），而不是跳过这一行。

纯 docs-only 改动（0 .swift 变化）无需编译，编译行写 `[docs-only] 跳过`，让用户一眼看到没编译是合理的。

汇报务必真实 —— self-fix 几轮就写几轮，PENDING 加几项就写几项，编译过就过、挂就挂，二进制时间戳就是实际读到的值，不虚报。
