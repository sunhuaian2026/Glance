# Mac App Store 上架 — Design

**Date**: 2026-06-25
**Status**: brainstorming 落地, 待 codex review + 军哥拍板进 writing-plans
**Scope**: Glance v2.3 已 ship GitHub Release(Developer ID + Notarize + DMG), 此为另一条分发路径 — Mac App Store(Mac App Distribution + .pkg + App Review)

---

## 1. 决策记录(brainstorming 6 大问拍板)

| 编号 | 决策点 | 拍板结果 | 理由 |
|---|---|---|---|
| **D1** | 核心动机 | **更多曝光 + 用户信任度 + 应用更新自动化 + 个人品牌/简历项目**(4 选) | 不为付费收入 / 国际化推广; 主推产品向曝光 + 个人作品集 |
| **D2** | 跟 GitHub Release 关系 | **双轨并存**(GitHub + App Store 都发) | 不区分用户分群, 用户自由选下载源; 接受维护成本翻倍 |
| **D3** | 定价模式 | **完全免费** | 跟 GitHub 一直保持, 抽成对 ¥0, 留 marketing 路径不切断小红书引流 |
| **D4** | 国家区域 | **全球 175 国(默认)** | EU DSA Non-Trader 已申报, app 内 en/zh-Hans i18n 已支持; App Store 算法多区曝光更广 |
| **D5.1** | LSApplicationCategoryType | **Primary: Utilities + Secondary: Photography** | 核心定位"找重复省空间"对应 Utilities 用户本能搜索分类; Photography 二级覆盖看图体验邻居 |
| **D5.2** | 隐私政策 URL | **GitHub Pages** (`https://sunhuaian2026.github.io/Glance/privacy.html`) | 免费 / 持久 / 跟仓库一体改起来直接; 不强求 `glance.app` 域名付费 |
| **D5.3** | 截图策略 | **复用 README 7 张 + 加图文标语包装** | Figma 拼 1-2h, App Store 个人开发者标配, 转化率显著高于裸截图; 不需要重截 app |
| **D5.4** | 审核通过后 release 策略 | **手动 release** | 配合小红书发推 + 双轨宣传协调上架时机, 紧急 bug 可撤回 |
| **D5.5** | 首发版本号 | **v2.3.0 直接首发** | 跟 GitHub v2.3 完全一致同 commit, 双轨同步逻辑简单, 不混淆用户 |

---

## 2. Scope

### 做什么
- 走完 Mac App Store 上架全流程(证书 → pbxproj → App Store Connect 元数据 → 包构建 → 上传 → 审核)
- 跟 GitHub Release 双轨并存, App Store 是新增分发路径
- 首发 v2.3.0(与 GitHub v2.3 同 commit, 同代码)

### 不做什么
- 不停 GitHub Release / 不改仓库 visibility / 不删 v1.0 / v2.3 历史 DMG 下载链
- 不付费 / 不内购 / 不订阅(D3 锁定免费)
- 不做 i18n metadata 翻译(en / zh-Hans 已在 app 内, App Store metadata 用中文为主英文 fallback)
- 不为此购买独立域名 `glance.app`(D5.2)
- 不引入新代码 feature(只做上架, 代码跟 v2.3 GA 完全一致)
- 不重截 app 截图(D5.3 复用 README + 标语包装)

---

## 3. 体系结构

### 3.1 跟 v2.3 GitHub Release 路径差异

| 维度 | v2.3 GitHub Release(现状) | Mac App Store(本设计) |
|---|---|---|
| 签名证书 | `Developer ID Application: Hongjun Sun (8KW8Z92GRA)` | `Mac App Distribution` + `Mac Installer Distribution`(2 张新证书) |
| 包格式 | `.dmg`(create-dmg + 公证 + staple) | `.pkg`(productbuild + Mac Installer Distribution 签) |
| 审核 | Apple Notarization 自动 5-30min | App Review **人工 1-3 天**, 可能拒 |
| 分发 | GitHub Release 公开 | App Store Connect → Mac App Store |
| 元数据 | DMG SHA256 + release notes md | App Store Connect 后台(名称/副标题/关键词/描述/截图/隐私政策 URL/支持 URL/分类/年龄分级) |
| 上传 | `gh release create` 命令行 | `xcrun altool --upload-app` 或 Transporter app |
| 更新机制 | 用户手动下新 DMG | App Store 自动更新 |

### 3.2 双轨同步流程(本设计立)

每次 release(v2.3 / 未来 v2.4...)的标准流程:

```
1. 代码 + verify.sh 三段过                                ┐
2. 同 commit 上跑两条 build:                              │ 共享
   2a. make release       → dist/Glance-X.Y.Z.dmg + 公证   │ 同代码
   2b. make release-appstore → dist/Glance-X.Y.Z.pkg + 签   │ 同 build
3. GitHub Release: tag X.Y + gh release create + DMG     │ 两条独立
4. App Store: altool upload + 等审核 + 手动 release       │
```

关键约束: 同 commit 同 MARKETING_VERSION, 两条 release 互不阻塞。GitHub 可以先发(v2.3 已发), App Store 后追(1-3 天审核期)。

---

## 4. 8 大工作类(完整 to-do)

### 任务 1 — 证书 + App ID 注册
- 1.1 https://developer.apple.com/account/resources/identifiers 注册 App ID `com.sunhongjun.glance` 明示 App Store distribution
- 1.2 创建 `Mac App Distribution` 证书(签 .app)
- 1.3 创建 `Mac Installer Distribution` 证书(签 .pkg)
- 1.4 创建 App Store Provisioning Profile 关联 App ID + Mac App Distribution 证书
- 1.5 全套证书 + profile 装到 Mac mini 登录 keychain, .p12 私钥备份到家里 MacStudio(同 v1.0 流程)

### 任务 2 — pbxproj + entitlements 调整
- 2.1 新增 Release 配置或 scheme 给 App Store target(可能用现 Release + 通过 xcodebuild 参数区分签名 identity, 不一定新建 scheme)
- 2.2 `Glance.entitlements` 审计:
  - App Sandbox ✓(已开)
  - user-selected files readwrite ✓(已开)
  - **审视**是否需要 `com.apple.security.network.client`(我们零网络, 不要)
  - **审视**是否需要 `com.apple.security.files.bookmarks.app-scope`(已开, 用于 Security Scoped Bookmark)
- 2.3 `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities"`(D5.1 Primary)
- 2.4 macOS 部署目标 14.0 ✓(已设)
- 2.5 年龄分级 / 内容评级在 App Store Connect 后台填(4+, 无成人内容)

### 任务 3 — App Store Connect 上架准备
- 3.1 https://appstoreconnect.apple.com 创建新 macOS App, 关联 Bundle ID `com.sunhongjun.glance`(必须任务 1.1 完成)
- 3.2 元数据(中英双语, 中文为主):
  - **名称**: "Glance · 一眼" / "Glance"
  - **副标题**: 30 字内 — "找重复省空间 · 沉浸看图" / "Find duplicates, save space"
  - **关键词**: 100 字符 — 「重复清理,看图,相似图,省空间,本地,沉浸,缩略图,EXIF,Mac看图器,duplicate」
  - **描述**: 4000 字内, 中英双语版, 突出"重复清理 / 找相似图 / 零网络零遥测 / 本地 / 沉浸看图"
  - **支持 URL**: `https://github.com/sunhuaian2026/Glance`(GitHub Issues)
  - **隐私政策 URL**: GitHub Pages(任务 5 建)
- 3.3 截图: 任务 6 准备的 5-10 张 (1280×800 或 2560×1600 Retina)
- 3.4 App 图标: `assets/icon-1024.png` 1024×1024 ✓(已有)
- 3.5 价格: 免费(D3)
- 3.6 国家区域: 全球 175 国 默认全勾(D4)
- 3.7 分类: Primary Utilities + Secondary Photography(D5.1)
- 3.8 年龄分级: 4+

### 任务 4 — release-appstore.sh 包构建脚本
- 4.1 新建 `scripts/release-appstore.sh`(平行于现 `release.sh`), 流程:
  ```
  xcodebuild archive
    CODE_SIGN_IDENTITY="Apple Distribution: Hongjun Sun (8KW8Z92GRA)"
    PROVISIONING_PROFILE_SPECIFIER="..."
    → archive
  productbuild --component dist/export/Glance.app /Applications
    --sign "3rd Party Mac Developer Installer: Hongjun Sun (8KW8Z92GRA)"
    → Glance-X.Y.Z.pkg
  pkgutil --check-signature → 验签
  ```
- 4.2 Makefile 加 `make release-appstore` target
- 4.3 跟现 `make release` 互不影响, 可并行跑或顺序跑

### 任务 5 — GitHub Pages 隐私政策页面
- 5.1 创建 `docs/privacy/index.html` 或 `docs/privacy.md`(GitHub Pages 支持)
- 5.2 在 GitHub repo settings 启 `gh-pages` 或 `/docs/` 作为 Pages source
- 5.3 内容: 中英双语隐私政策文本, 涵盖:
  - 零网络请求 / 零数据上传 / 零遥测(Glance 核心承诺)
  - User-selected folder 通过 Security Scoped Bookmark 仅本机访问
  - 重复清理走 macOS 系统废纸篓, 不直接删文件
  - 联系方式: 邮箱 16414766@qq.com / 小红书 382336617 / GitHub Issues
  - 数据使用 / 修改 / 删除流程(尽管我们零网络, Apple 强制要求声明)
- 5.4 URL: `https://sunhuaian2026.github.io/Glance/privacy.html` 或 `https://sunhuaian2026.github.io/Glance/`
- 5.5 验证 URL 200 不死链

### 任务 6 — 截图准备(图文标语包装)
- 6.1 复用 `assets/screenshots/` 7 张作素材:
  - 01-grid.png / 03-quickviewer.png(v1 基础体验)
  - 05-dedup.png / 06-focus-review.png / 07-search.png(v2.3 主推)
- 6.2 用 Figma / Pixelmator 拼图:
  - 每张顶部加 64-80px 高的 hero 标语区, 蓝紫色调 跟 app 一致
  - 标语方向(hero shot 优先级):
    - **Screenshot 1**(转化率最关键): 重复清理截图 + 标语「跨文件夹找重复 · 省 GB 级硬盘」
    - **Screenshot 2**: 逐组审阅浮层 + 标语「逐组眼审 · 撤销随时可用」
    - **Screenshot 3**: 全局搜索 + 标语「⌘F 全库搜 · 类型/大小/时间筛选」
    - **Screenshot 4**: QuickViewer + 标语「沉浸看图 · 零打扰」
    - **Screenshot 5**: Grid + 标语「本地零网络 · 你的图你的库」
- 6.3 输出 5 张 2560×1600 (Retina) PNG, 存 `assets/appstore-screenshots/01-05.png`
- 6.4 工作量 1-2h, 军哥本机 Figma 拼或找设计师

### 任务 7 — 上传 + 审核
- 7.1 build .pkg(任务 4)
- 7.2 上传方式选其一:
  - `xcrun altool --upload-app --type osx --file Glance-2.3.0.pkg --apiKey ... --apiIssuer ...`(命令行)
  - Transporter.app(GUI 上传)
- 7.3 等 App Store Connect 处理 build(几分钟到 30min)
- 7.4 在 Web 后台关联 build 到 App Store version
- 7.5 提交审核(Submit for Review)
- 7.6 等 Apple 人工审核 1-3 天
- 7.7 审核通过通知 → 邮件 / App Store Connect 通知
- 7.8 在后台手动点「发布」release(D5.4)

### 任务 8 — 双轨上架后
- 8.1 README 顶部下载入口加 App Store badge:
  ```markdown
  [<img src="..." alt="Download on Mac App Store" height="50">](https://apps.apple.com/app/idXXXXXXX) [<img src="..." height="50">](github.com/.../releases/latest)
  ```
- 8.2 小红书发首发推, 双轨入口(App Store 链接 + GitHub Release 链接) 都贴
- 8.3 PENDING-USER-ACTIONS.md 加 App Store 相关人工跟踪项(评分 / 评论 / 拒因复盘)

---

## 5. 审核风险点预判

我们 app 跟 Apple 审核可能撞的点 + 准备应对:

| 风险点 | Apple 审核可能问 | 准备应对 |
|---|---|---|
| **OpenWith Finder「打开方式」+ Dock 拖放** | 是不是劫持文件类型 / 影响其他 app | 解释: 用户主动选择 Glance 作为打开方式, 不强制注册 LSHandlerRank=Default(我们用 Alternate 不抢默认看图器). Apple Photos / Preview 有同款行为 |
| **FSEvents 持续监控用户文件夹** | 是不是后台 indexing 用户文件 | 解释: 沙盒框架内仅监控 user-selected 文件夹(Security Scoped Bookmark 授权范围), 不外传, 全本地 SQLite. 类比 Photos / Finder 自身的索引行为 |
| **SHA256 计算 + 跨文件夹索引(IndexStore)** | 是不是恶意 fingerprint 用户文件 | 解释: 仅在 user-selected 文件夹内做内容哈希用于重复检测, 哈希值不外传不联网, 全本地存 `~/Library/Containers/com.sunhongjun.glance/Application Support/` |
| **「重复清理」批量移废纸篓** | 真删用户文件的安全保障 | 解释: 走 `FileManager.trashItem`(macOS 系统废纸篓, 不 unlink), 单图 5s 撤销 toast + 批量 banner 整批还原. Apple Photos / Finder 同款 |
| **Vision feature print(找相似图)** | 用了哪些 framework / 是否有未声明权限 | 解释: Vision framework 是 Apple 官方, 不需要额外 entitlement, 不联网 |
| **隐私政策 URL** | 必须有, 内容必须真实 | 任务 5 准备 GitHub Pages 中英双语版 |
| **metadata 跟 app 实际功能不符** | 描述吹的 feature app 没实现会拒 | 描述只写已 ship feature(v2.3 7 子系统), 不画饼 |
| **app icon 不规范 / 含其他 trademark** | 拒 | 我们 icon master 是 Claude Design 出眼睛 Cool Violet 方向, 原创 ✓ |
| **app 内有 broken link / 404** | 拒 | review 前过一遍 app 内所有 URL(关于面板 / Inspector / 等) |

**常见拒因 + 我们规避**:
- 沙盒 entitlement 不当 → 已开 App Sandbox 多年, 走 user-selected ✓
- 截图含其他 app trademark → 任务 6 设计时避开
- 收集用户数据但隐私政策未声明 → 我们零数据收集 ✓
- 闪退 / 严重 bug → v2.3 已 5+ 真机验过

**预估首次审核结果**: 通过概率 70-80%, 可能因为"SHA256 + FSEvents 用法非主流"被问问题, 准备好回应文案就能过. 第一次提交常被拒 1-2 次属正常, 改 metadata / 加说明 再提即可.

---

## 6. 时间预估

| 任务 | 估时 | 阻塞类型 |
|---|---|---|
| 1 证书 + App ID | 30min(后台点点 + 等 Apple 颁发) | 等 Apple |
| 2 pbxproj + entitlements | 30min(改 1-2 字段 + verify) | CC 跑 |
| 3 App Store Connect 元数据 | 2-3h(后台填一堆字段 + 中英双语描述 4000 字) | 军哥填(主) |
| 4 release-appstore.sh + Makefile | 1-2h(mirror release.sh 改签名 + productbuild) | CC 写 |
| 5 GitHub Pages 隐私政策 | 1h(写 + 发) | CC 写 |
| 6 截图标语包装 | 1-2h(Figma) | 军哥本机做(主) |
| 7 上传 + 审核 | 上传 30min + **等 Apple 1-3 天** | 等 Apple |
| 8 双轨上架后 | 30min | CC + 军哥 |
| **总** | **CC 工作 ~4-5h + 军哥工作 ~3-5h + Apple 等 1-3 天** | 半天到 5 天 |

---

## 7. 回滚 / 兜底

| 阶段 | 出问题 | 兜底 |
|---|---|---|
| 任务 1 证书 | Apple 后台报错 / 证书装不上 keychain | mirror v1.0 当时步骤, 必要时找开发者支持 |
| 任务 4 build .pkg | productbuild 失败 / 签名错 | 跟 release.sh 共享 archive 逻辑, 调 signing identity 即可 |
| 任务 7 上传 | altool 上传失败 | 改用 Transporter app GUI 上传 |
| 任务 7 审核拒 | 提供拒因 → 改 metadata / 加 entitlement 说明 / 重 build → 重提 | 第一次拒属正常, 改 + 重提 |
| 任务 8 上架后 hotfix | 发现严重 bug | 跟 GitHub Release 同流程: 新 build + 新 version 重新走任务 4-7 |

---

## 8. 不修改范围

- 现 `release.sh` / `make release` GitHub Release 流程**不动**(双轨独立)
- v2.3 GitHub Release(已发, https://github.com/sunhuaian2026/Glance/releases/tag/v2.3) **不动**
- `Glance.app` 内代码**不改**(App Store 用同一份代码, 仅签名 + 包格式差异)
- App 内 UI / feature **不动**(不为 App Store 加特殊功能)

---

## 9. 时间线建议

按军哥实际节奏:

| 第几天 | 工作 | 阻塞 |
|---|---|---|
| Day 1 | 任务 1 证书 + 任务 5 GitHub Pages | 等 Apple 颁发证书(~几分钟) |
| Day 2 | 任务 2 pbxproj + 任务 4 release-appstore.sh | CC 写 |
| Day 3 | 任务 3 App Store Connect 元数据 + 任务 6 截图 | 军哥本机做 |
| Day 4 | 任务 7 上传 + 提交审核 | CC + 军哥 |
| Day 5-7 | 等 Apple 审核 | Apple 审核中, 此期间可继续 dev 新 feature |
| Day 8+ | 审核结果 → 通过手动 release / 拒了 fix 重提 | 军哥 |
| Day 8+ | 任务 8 双轨上架后宣传 | 军哥小红书 |

**Total 1 周内可上架**(顺利的话, 拒了 + 重提需要更长)

---

## 10. 后续 follow-up(本 design 不涵盖)

- App Store 评分 / 评论运营
- 价格策略调整(从免费切付费 / 加内购) — 本 design D3 锁免费, 后续按业务需要再 brainstorming
- 多语言 metadata(英日韩等) — D4 全球但 metadata 中文为主, 海外用户体验后续优化
- 自买域名 `glance.app` — D5.2 暂不付费, 后续看品牌投入再说
- App Store 推荐位 / 编辑荐选 申请
