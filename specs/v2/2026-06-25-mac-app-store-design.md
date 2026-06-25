# Mac App Store 上架 — Design v2

**Date**: 2026-06-25 (v1 初稿) + 2026-06-25 v2 (codex review 折入 4 P0 + 6 P1 + 3 P2)
**Status**: codex review v1 已折入, 待军哥拍板进 writing-plans
**Scope**: Glance v2.3 已 ship GitHub Release(Developer ID + Notarize + DMG), 此为另一条分发路径 — Mac App Store(Mac App Distribution + .pkg + App Review)

---

## 1. 决策记录(brainstorming 11 大问拍板)

| 编号 | 决策点 | 拍板结果 | 理由 |
|---|---|---|---|
| **D1** | 核心动机 | **更多曝光 + 用户信任度 + 应用更新自动化 + 个人品牌/简历项目**(4 选) | 不为付费收入 / 国际化推广; 主推产品向曝光 + 个人作品集 |
| **D2** | 跟 GitHub Release 关系 | **双轨并存**(GitHub + App Store 都发) | 不区分用户分群, 用户自由选下载源; 接受维护成本翻倍 |
| **D3** | 定价模式 | **完全免费** | 跟 GitHub 一直保持, 抽成对 ¥0, 留 marketing 路径不切断小红书引流 |
| **D4** | 国家区域 | **全球 175 国(默认)** | EU DSA Non-Trader 已申报, app 内 en/zh-Hans i18n 已支持; App Store 算法多区曝光更广 |
| **D5.1** | LSApplicationCategoryType | **Primary: Utilities + Secondary: Photography** | 核心定位"找重复省空间"对应 Utilities 用户本能搜索分类; Photography 二级覆盖看图体验邻居 |
| **D5.2** | 隐私政策 URL | **GitHub Pages** (`https://sunhuaian2026.github.io/Glance/privacy.html`) | 免费 / 持久 / 跟仓库一体改起来直接; 不强求 `glance.app` 域名付费 |
| **D5.3** | 截图策略 | **复用 README 7 张 + 加图文标语包装**(注意 P2-3 真实性约束, 用 App Store build 抓最终) | Figma 拼 1-2h, App Store 个人开发者标配; 不需要重截 app 但**必须用 App Store build 抓** |
| **D5.4** | 审核通过后 release 策略 | **手动 release** | 配合小红书发推 + 双轨宣传协调上架时机, 紧急 bug 可撤回 |
| **D5.5** | 首发版本号 | **v2.3.0 直接首发** | 跟 GitHub v2.3 完全一致同 commit, 双轨同步逻辑简单, 不混淆用户 |
| **D5.6** | 同 Bundle ID 双渠道数据共享(P0-4 codex 新决策点) | **同 Bundle ID `com.sunhongjun.glance` + 共享 sandbox container** | 跟 D2 双轨"用户自由选"哲学一致, 老 GitHub 用户切到 App Store 版**无缝继承所有 root + 索引数据**; 双装一台机为边缘场景不为它牺牲主流体验 |
| **D5.7** | 上传凭据(P1-1 codex 反馈) | **App Store Connect API Key / JWT** (不用 App-Specific Password) | App Store 上传走现代凭据路径, 公证仍可继续用 keychain-profile / App-Specific Password 不冲突 |

---

## 2. Scope

### 做什么
- 走完 Mac App Store 上架全流程(证书 → Privacy Manifest → pbxproj → App Store Connect 元数据 → exportArchive → 上传 → 审核)
- 跟 GitHub Release 双轨并存, App Store 是新增分发路径
- 首发 v2.3.0(与 GitHub v2.3 同 commit, 同代码)

### 不做什么
- 不停 GitHub Release / 不改仓库 visibility / 不删 v1.0 / v2.3 历史 DMG 下载链
- 不付费 / 不内购 / 不订阅(D3 锁定免费)
- 不做 i18n metadata 翻译(en / zh-Hans 已在 app 内, App Store metadata 用中文为主英文 fallback)
- 不为此购买独立域名 `glance.app`(D5.2)
- 不引入新代码 feature(只做上架, 代码跟 v2.3 GA 完全一致)
- 不重截 app 截图素材(D5.3, 但用 App Store build 抓避免 metadata mismatch)
- **不试 IAP / 订阅 / 任何收费机制**(D3 锁定, 改 IAP 会引入 App Review 重审 + 权利变更 + Family Sharing + 税务连带工作, 远期看)

---

## 3. 体系结构

### 3.1 跟 v2.3 GitHub Release 路径差异

| 维度 | v2.3 GitHub Release(现状) | Mac App Store(本设计) |
|---|---|---|
| 签名证书 | `Developer ID Application: Hongjun Sun (8KW8Z92GRA)` | `Apple Distribution`(签 .app, 推荐 Apple Distribution 统一证书) + `Mac Installer Distribution` 不需要(走 xcodebuild -exportArchive 自动签 .pkg) |
| Archive | `xcodebuild archive` (Developer ID 签 in-archive) | **独立 archive** `xcodebuild archive` (Apple Distribution 签 in-archive) — **必须分开 archive, 不可共享**(P0-3) |
| 包格式 + 导出 | `create-dmg` 后 stapler | **xcodebuild -exportArchive** 用 `ExportOptions-AppStore.plist` 自动出 `.pkg` (Apple 推荐路径) (P0-1) |
| 审核 | Apple Notarization 自动 5-30min | App Review **人工 1-3 天**(中位 ~24-48h), 可能拒, **首次预计 2-3 周日历**(P1-6) |
| 分发 | GitHub Release 公开 | App Store Connect → Mac App Store |
| 元数据 | DMG SHA256 + release notes md | App Store Connect 后台(名称/副标题/关键词/描述/截图/隐私政策 URL/支持 URL/分类/年龄分级/Privacy Nutrition Labels) |
| 上传 | `gh release create` 命令行 | **`xcrun altool --upload-app --apiKey ... --apiIssuer ...`**(API Key/JWT, P1-1) 或 Transporter app |
| 更新机制 | 用户手动下新 DMG | App Store 自动更新 |
| 数据容器 | `~/Library/Containers/com.sunhongjun.glance/` | **同**(D5.6 共享, 用户切版本数据无缝继承) |

### 3.2 双轨同步流程(本设计立, P0-3 折入)

每次 release(v2.3 / 未来 v2.4...)的标准流程, **必须两次独立 archive**:

```
1. 代码 + verify.sh 三段过                                                        ┐
2. 两条独立 archive(必须分开跑, 签名 bake 进 archive 不可共享):                    │ 同代码同 commit
   2a. ./scripts/release.sh           → dist/Glance.xcarchive (Developer ID)      │
        ↓ exportArchive (developer-id.plist)                                      │ 两条独立 archive
        ↓ create-dmg + notarize + staple                                          │
        → dist/Glance-X.Y.Z.dmg                                                    │
   2b. ./scripts/release-appstore.sh  → dist/Glance-AppStore.xcarchive (Apple Distribution)
        ↓ exportArchive (app-store.plist)                                         │
        → dist/Glance-X.Y.Z.pkg (自动签 + 自动包装 Apple 推荐路径, P0-1)            │
3. GitHub Release: tag X.Y + gh release create + DMG                              │ 两条独立发布
4. App Store: altool upload (API Key) + 等审核 + 手动 release                      │
```

关键约束:
- 同 commit / 同 MARKETING_VERSION / 同 entitlements / 同代码 → 两次 archive
- archive 路径分开: `dist/Glance.xcarchive` (Developer ID) vs `dist/Glance-AppStore.xcarchive` (Apple Distribution)
- 两条 release 互不阻塞, GitHub 先发 / App Store 后追, 审核期 1-3 天差距可接受

---

## 4. 9 大工作任务

### 任务 1 — 证书 + App ID 注册
- 1.1 https://developer.apple.com/account/resources/identifiers 注册 App ID `com.sunhongjun.glance` 明示 App Store distribution
- 1.2 创建 `Apple Distribution` 证书 (Apple 推荐统一证书, 同时支持 iOS / macOS App Store + Ad Hoc)
- 1.3 不需要 `Mac Installer Distribution` 证书 — Apple 推荐 `xcodebuild -exportArchive` 走 App Store ExportOptions 自动签 .pkg, 内部用 Apple Distribution 证书的 installer counterpart
- 1.4 创建 App Store Provisioning Profile 关联 App ID + Apple Distribution 证书
- 1.5 创建 **App Store Connect API Key**(D5.7, P1-1):
  - 在 https://appstoreconnect.apple.com/access/api 创建 Team Key, 权限 "App Manager"
  - 下载 `AuthKey_<KEY_ID>.p8` 保存到 `~/.appstoreconnect/private_keys/` (本地 keychain 兼容)
  - 记下 Key ID + Issuer ID(后续 altool 用)
- 1.6 全套证书 + profile + API key 装到 Mac mini 登录 keychain, .p12 + .p8 备份到家里 MacStudio + 冷备份(同 v1.0 流程)

### 任务 2 — pbxproj + entitlements + Privacy Manifest 审计
- 2.1 **新 build scheme**(P0-3): 新建 `Glance AppStore` scheme 用 Apple Distribution 签名 (不复用 Release scheme 避免签名互相干扰)
- 2.2 Entitlements 审计 (P1-2):
  - `Glance.entitlements` 当前 3 个键(`com.apple.security.app-sandbox=YES` / `com.apple.security.files.user-selected.read-write=YES` / `com.apple.security.files.bookmarks.app-scope=YES`) — App Store 接受 ✓
  - **审视**新增 `Glance-AppStore.entitlements`(可单独文件分轨, 或 if 共用 Release entitlements 不需要)
  - **不要**: `com.apple.security.network.client` (我们零网络) / JIT / `com.apple.security.cs.allow-*`(危险权利) — App Review 看到会问理由
- 2.3 `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities"` (D5.1 Primary)
- 2.4 macOS 部署目标 14.0 ✓(已设)
- 2.5 **Hardened Runtime 审计**(P1-2): App Store 不强制 Hardened Runtime(跟 Developer ID 不同), 但建议保持开启跟 Developer ID 行为一致. App Store profile 要求跟 entitlements 严格匹配.
- 2.6 年龄分级 / 内容评级在 App Store Connect 后台填(4+, 无成人内容)
- **2.7 Privacy Manifest 审计 + 加 `PrivacyInfo.xcprivacy`** (P0-2 codex 重磅, **强制**, Apple 2024-05-01 起):
  - 创建 `Glance/PrivacyInfo.xcprivacy` 文件 (.xcprivacy = plist 结构)
  - 声明 required-reason API + 选定 reason category, 我们用的 API + 推断 category:
    - `FileManager.trashItem(at:resultingItemURL:)` + `FileManager.contentsOfDirectory(at:)` → `NSPrivacyAccessedAPICategoryDiskSpace` (用户文件操作) (具体 Apple 文档实施时核对)
    - **FSEvents**(`FSEventStreamCreate`) → 实测不在 required-reason 列表(沙盒 user-selected 范围内监控), 但保险起见标注 "用户选择文件夹的变化监控"
    - **SQLite** 直接 `sqlite3` C API → 不在 required-reason 列表
    - Security Scoped Bookmark → `NSPrivacyAccessedAPICategoryUserDefaults` (`bookmarkData`) 实际不算, sandbox 自家文件不算
    - `URLResourceValues`(`.fileCreationDate` / `.contentModificationDate` / `.fileSizeKey`) → `NSPrivacyAccessedAPICategoryFileTimestamp` ✓ (我们用了, 必须声明 reason: `0A2A.1` "用户选择文件夹内文件元数据展示")
    - `CryptoKit` SHA256 → 不在 required-reason 列表
  - 声明 `NSPrivacyCollectedDataTypes` 数据收集类型 → **空数组**(我们零数据收集) ✓
  - 声明 `NSPrivacyTracking` = `false` (零跟踪) ✓
  - 声明 `NSPrivacyTrackingDomains` = `[]` (零跟踪域名) ✓
  - **影响**: archive 时 Privacy Manifest 自动嵌入 .app, App Store 上传时 Apple 校验, 不符直接拒

### 任务 3 — App Store Connect 元数据 + Privacy Nutrition Labels
- 3.1 https://appstoreconnect.apple.com 创建新 macOS App, 关联 Bundle ID `com.sunhongjun.glance`(必须任务 1.1 完成)
- 3.2 元数据(中英双语, 中文为主):
  - **名称**: "Glance · 一眼" / "Glance"
  - **副标题**: 30 字内 — "找重复省空间 · 沉浸看图" / "Find duplicates, save space"
  - **关键词**: 100 字符 — 「重复清理,看图,相似图,省空间,本地,沉浸,缩略图,EXIF,Mac看图器,duplicate」
  - **描述**: 4000 字内, 中英双语版, 突出"重复清理 / 找相似图 / 零网络零遥测 / 本地 / 沉浸看图"
  - **支持 URL**: `https://github.com/sunhuaian2026/Glance`(GitHub Issues)
  - **隐私政策 URL**: GitHub Pages(任务 5 建)
- 3.3 截图: 任务 6 准备的 5-10 张(2880×1800 主流 Retina, 或 2560×1600)
  - **P2-3 约束**: 截图必须用 **App Store build 抓**(同 commit 但 Apple Distribution 签名 + Privacy Manifest 嵌入版本), 避免 GitHub Developer ID 版的 metadata mismatch 拒因
- 3.4 App 图标: `assets/icon-1024.png` 1024×1024 ✓(已有)
- 3.5 价格: 免费(D3)
- 3.6 国家区域: 全球 175 国 默认全勾(D4)
- 3.7 分类: Primary Utilities + Secondary Photography(D5.1)
- 3.8 年龄分级: 4+
- **3.9 Privacy Nutrition Labels**(Apple 后台必填, 跟 Privacy Manifest 互补):
  - 数据类型 = 不收集任何数据(All sections empty / "App 不会收集数据")
  - 跟踪 = 否
  - 链接到用户 = 否
  - 这跟 2.7 Privacy Manifest 内容呼应, 后台填表跟 Manifest 不一致会拒

### 任务 4 — `scripts/release-appstore.sh` 包构建脚本(P0-1 改架构)
- 4.1 新建 `scripts/release-appstore.sh`, **走 Apple 推荐路径**:
  ```bash
  # 1. Archive (Apple Distribution 签 in-archive, 独立 archive 路径)
  xcodebuild archive \
    -project Glance.xcodeproj \
    -scheme "Glance AppStore" \
    -configuration Release \
    -archivePath dist/Glance-AppStore.xcarchive \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=8KW8Z92GRA \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    PROVISIONING_PROFILE_SPECIFIER="<App Store Glance Profile>" \
    CURRENT_PROJECT_VERSION="${BUILD_VERSION}" \
    -quiet

  # 2. exportArchive 用 App Store ExportOptions, **自动**签 .pkg
  xcodebuild -exportArchive \
    -archivePath dist/Glance-AppStore.xcarchive \
    -exportPath dist/export-appstore \
    -exportOptionsPlist scripts/ExportOptions-AppStore.plist \
    -quiet
  # → dist/export-appstore/Glance.pkg
  ```
- 4.2 新建 `scripts/ExportOptions-AppStore.plist`:
  ```xml
  <plist><dict>
    <key>method</key><string>app-store</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Apple Distribution</string>
    <key>provisioningProfiles</key><dict>
      <key>com.sunhongjun.glance</key>
      <string><App Store Glance Profile></string>
    </dict>
    <key>uploadSymbols</key><false/>
    <key>compileBitcode</key><false/>
  </dict></plist>
  ```
- 4.3 验证 .pkg:
  ```bash
  pkgutil --check-signature dist/export-appstore/Glance.pkg
  ```
- 4.4 Makefile 加 `make release-appstore` target
- 4.5 跟现 `make release` 互不影响, 可并行跑或顺序跑(2 次独立 archive, 跟 GitHub Developer ID 路径不冲突)
- 4.6 build time 预估: 双轨 archive 约翻倍(每条 ~30s archive, 总 ~1min)

### 任务 5 — GitHub Pages 隐私政策页面(P1-5 强化)
- 5.1 创建 `docs/privacy/index.html` 或 `docs/privacy.md`(GitHub Pages 支持)
- 5.2 在 GitHub repo settings 启 `gh-pages` 或 `/docs/` 作为 Pages source
- 5.3 内容: 中英双语隐私政策文本, 涵盖:
  - **零网络请求 / 零数据上传 / 零遥测**(Glance 核心承诺)
  - **本地文件索引明示**(P1-5): 缩略图 / SHA256 内容指纹 / Vision feature print(图像哈希) / SQLite 索引数据 **全部存设备本地** `~/Library/Containers/com.sunhongjun.glance/Application Support/`, **不上传任何服务器**
  - User-selected folder 通过 Security Scoped Bookmark 仅本机访问
  - 重复清理走 macOS 系统废纸篓, 不直接删文件
  - 联系方式: 邮箱 16414766@qq.com / 小红书 382336617 / GitHub Issues
  - 数据使用 / 修改 / 删除流程(零网络仍要按 GDPR / CCPA / PIPL 框架声明)
- 5.4 URL: `https://sunhuaian2026.github.io/Glance/privacy.html` 或 `https://sunhuaian2026.github.io/Glance/`
- 5.5 验证 URL 200 不死链

### 任务 6 — 截图准备(图文标语包装 + P2-3 真实性约束)
- 6.1 复用 `assets/screenshots/` 7 张作素材(README v1+v2.3 各 4 + 3)
- 6.2 **重要(P2-3)**: 重截 5 张用 **App Store build**(任务 4 产出的 .pkg 解包安装 + 抓), **不要直接复用 GitHub Developer ID build 截图** — 避免 metadata mismatch 拒因. UI 视觉两 build 应该 100% 一致(同代码), 但 Apple 严格审核可能比对建议
- 6.3 用 Figma / Pixelmator 拼图, 每张顶部加 64-80px hero 标语区, 蓝紫色调跟 app 一致
- 6.4 标语方向(hero shot 优先级):
  - **Screenshot 1**(转化率最关键): 重复清理截图 + 标语「跨文件夹找重复 · 省 GB 级硬盘」
  - **Screenshot 2**: 逐组审阅浮层 + 标语「逐组眼审 · 撤销随时可用」
  - **Screenshot 3**: 全局搜索 + 标语「⌘F 全库搜 · 类型/大小/时间筛选」
  - **Screenshot 4**: QuickViewer + 标语「沉浸看图 · 零打扰」
  - **Screenshot 5**: Grid + 标语「本地零网络 · 你的图你的库」
- 6.5 输出 5 张 2880×1800 (Retina 主流) 或 2560×1600 PNG, 存 `assets/appstore-screenshots/01-05.png`
- 6.6 工作量 2-3h, 军哥本机 Figma 拼或找设计师

### 任务 7 — TestFlight 预审 + 上传 + 审核
- **7.0 TestFlight 内测预 step**(P2-1, 可选但推荐):
  - 在 App Store Connect 后台用 TestFlight 把 build 推给自己 + 1-2 个朋友试装
  - 验证 App Store profile 签名 / Privacy Manifest / 沙盒 / 首启行为(P1-3 审核员空态)
  - **优势**: 拦截签名/manifest/沙盒错误(免去正式 review 拒因), 1-2 天内能拿到结果
  - **劣势**: 多 1 步, 不强制
- 7.1 build .pkg(任务 4)
- 7.2 上传(D5.7, P1-1 现代凭据):
  ```bash
  xcrun altool --upload-app \
    --type macos \
    --file dist/export-appstore/Glance.pkg \
    --apiKey <KEY_ID> \
    --apiIssuer <ISSUER_ID>
  ```
  或用 Transporter.app GUI 上传(API Key/JWT 用法相同, 仅 UI 差异)
- 7.3 等 App Store Connect 处理 build(几分钟到 30min)
- 7.4 在 Web 后台关联 build 到 App Store version
- **7.5 准备审核备注文案**(P1-3): 在 App Store Connect "App Review Notes" 段写明:
  - "首次启动 app 是空的, 需要用户通过侧边栏左上角 + 按钮添加文件夹根目录"
  - "测试账号 + 测试图库"(如审核员需要重现)
  - "重复清理需要至少 2+ 张相同图(SHA256 一致)才有数据"
  - 中英文版备注降低拒因
- 7.6 提交审核(Submit for Review)
- 7.7 等 Apple 人工审核 1-3 天(P1-6 实际首次 2-3 周日历, 含 1-2 次拒因+改+重提)
- 7.8 审核通过通知 → 邮件 / App Store Connect 通知
- 7.9 在后台手动点「发布」release(D5.4)

### 任务 8 — 双轨上架后 + D5.6 双装兜底(P0-4 折入)
- 8.1 README 顶部下载入口加 App Store badge:
  ```markdown
  [<img src="..." alt="Download on Mac App Store" height="50">](https://apps.apple.com/app/idXXXXXXX) [<img src="..." height="50">](github.com/.../releases/latest)
  ```
- 8.2 小红书发首发推, 双轨入口(App Store 链接 + GitHub Release 链接) 都贴
- 8.3 PENDING-USER-ACTIONS.md 加 App Store 相关人工跟踪项(评分 / 评论 / 拒因复盘)
- **8.4 D5.6 双装兜底文档**(P0-4 codex):
  - **同 Bundle ID 共享 sandbox container**: 老 GitHub 用户在装 App Store 版后, 直接打开 App Store 版即可继承所有 root + 索引数据(SQLite DB + bookmark 都在 `~/Library/Containers/com.sunhongjun.glance/`)
  - **双装一台机风险声明**: 用户**不应同时安装 GitHub Developer ID 版 + App Store 版**, 因为同 sandbox container 共享数据可能出现 schema 冲突 / 版本号比对异常 / FSEvents 重复触发. README + App Store 描述强烈建议二选一
  - **App Store 版升级路径**: App Store 自动更新接管, 用户卸 GitHub 版后纯走 App Store 版即可
  - **GitHub 版用户的迁移说明**: README 加 "已装 GitHub 版?" 子段 - 双装共存只在二选一前提下数据可继承, 建议卸 GitHub 版完成迁移

### 任务 9 — Roadmap + CONTEXT 同步
- 9.1 specs/Roadmap.md 加 V2.3 App Store 上架记录 (commit / 日期 / Submission ID)
- 9.2 CONTEXT.md 术语字典加"App Store 上架"作为独立子系统(跟 OpenWith / 快速看图器 toolbar 修复 等并列, 不塞 M 序号)

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
| **审核员空态可复现性**(P1-3 codex 加) | 审核员首启 app 没有任何文件夹, 功能看起来空白 + 截图满状态 → 触发 4.0 设计或 metadata-mismatch 拒因 | 任务 7.5 准备审核备注 + App Store Connect "App Review Notes" 段中英双语写明首启操作流程, 提供测试图库截图 |
| **FSEvents 在 App Store sandbox 行为差异**(P1-4 codex 加) | 沙盒外路径访问 / 已删除 root / 过期 bookmark 处理是否 leaky | 任务 7.0 TestFlight 走查 App Store sandbox profile 行为, 验证一致性 |
| **Privacy Manifest 不符**(P0-2 codex 加) | 声明的 required-reason API 跟实际 binary 用的不一致 | 任务 2.7 严格审计 + 用 Xcode 16 build 检验自动报警 |

**常见拒因 + 我们规避**:
- 沙盒 entitlement 不当 → 已开 App Sandbox 多年, 走 user-selected ✓
- 截图含其他 app trademark → 任务 6 设计时避开
- 收集用户数据但隐私政策未声明 → 我们零数据收集 ✓
- 闪退 / 严重 bug → v2.3 已 5+ 真机验过
- **Privacy Manifest 缺失 / 不符** → 任务 2.7 ✓
- **Privacy Nutrition Labels 跟 Manifest 不一致** → 任务 3.9 ✓

**预估首次审核结果**(P1-6 修正): 通过概率 60-70%, 可能因为"SHA256 + FSEvents 用法非主流" / "Privacy Manifest 边界" / "审核员空态体验" 被问问题或拒. 第一次提交常被拒 1-2 次属正常, 改 metadata / 加说明 / fix manifest 再提即可. **日历时间预估 2-3 周**(含 1-2 次拒因+改+重提 cycle).

---

## 6. 时间预估(P1-6 修正)

| 任务 | 估时 | 阻塞类型 |
|---|---|---|
| 1 证书 + App ID + API Key | 1h(后台点点 + 等 Apple 颁发 + API Key 配置) | 等 Apple |
| 2 pbxproj + entitlements + Privacy Manifest 审计 | 1-2h(新 scheme + 加 PrivacyInfo.xcprivacy + 多轮校对) | CC 跑 |
| 3 App Store Connect 元数据 + Nutrition Labels | 3-4h(后台填一堆字段 + 中英双语描述 4000 字 + 隐私标签呼应 Manifest) | 军哥填(主) |
| 4 release-appstore.sh + ExportOptions plist + Makefile | 2-3h(mirror release.sh 改架构, exportArchive 路径 + manual signing 详细) | CC 写 |
| 5 GitHub Pages 隐私政策(中英双语) | 2h(零网络承诺 + 本地索引明示 + GDPR/PIPL 框架声明) | CC 写 |
| 6 截图标语包装(用 App Store build 抓) | 2-3h(Figma) | 军哥本机做(主) |
| 7.0 TestFlight 内测预 step(可选) | 上传 30min + 内测 1-2 天 | 等 Apple |
| 7.1-7.9 正式上传 + 审核 | 上传 30min + **等 Apple 审核 1-3 天**(中位 ~24-48h, 首次 +可能 1-2 次拒因 reset) | 等 Apple |
| 8 双轨上架后 + 双装兜底文档 | 1h | CC + 军哥 |
| 9 Roadmap + CONTEXT 同步 | 30min | CC |
| **总** | **CC 工作 ~7-9h + 军哥工作 ~5-7h + Apple 等 2-3 周**(P1-6 修正, 含 1-2 次拒因) | 2-3 周日历 |

---

## 7. 回滚 / 兜底

| 阶段 | 出问题 | 兜底 |
|---|---|---|
| 任务 1 证书 | Apple 后台报错 / 证书装不上 keychain | mirror v1.0 当时步骤, 必要时找开发者支持 |
| 任务 1.5 API Key | Key 失效 / 权限不足 | 后台重新生成 Key, 装新 .p8 文件 |
| 任务 2.7 Privacy Manifest | required-reason API 漏报 / category 选错 | Xcode 16 build 时自动 warning, 按提示 fix; 重 archive |
| 任务 4 build .pkg | exportArchive 失败 / 签名错 / profile mismatch | 调 signing identity + provisioning profile 名字; 重 archive |
| 任务 7 上传 | altool API key 上传失败 | 改用 Transporter app GUI 上传; 或回退到 App-Specific Password 一次性绕过 |
| 任务 7.0 TestFlight | 内测发现签名/manifest 问题 | 不强制, 但发现问题立刻 fix 重 build 重传, 比正式 review 拒了再 fix 快 |
| 任务 7.7 审核拒 | 提供拒因 → 改 metadata / 加 entitlement 说明 / 重 build → 重提 | 第一次拒属正常(60-70% 通过率), 改 + 重提 |
| 任务 8 上架后 hotfix | 发现严重 bug | 跟 GitHub Release 同流程: 新 build + 新 version 重新走任务 4-7 |
| 任务 8.4 双装冲突 | 用户同时装 GitHub + App Store 版数据冲突 | README + App Store 描述强烈建议二选一; 收到用户反馈帮助卸老版 |

---

## 8. 不修改范围

- 现 `release.sh` / `make release` GitHub Release 流程**不动**(双轨独立, 唯独可能调 ExportOptions.plist comment 注释一致性)
- v2.3 GitHub Release(已发, https://github.com/sunhuaian2026/Glance/releases/tag/v2.3) **不动**
- `Glance.app` 内代码**不改**(App Store 用同一份代码, 仅签名 + 包格式差异)
- App 内 UI / feature **不动**(不为 App Store 加特殊功能)
- 现 `Glance.entitlements` **不动**(沙盒 entitlements 跟 App Store 兼容); 必要时新增 `Glance-AppStore.entitlements` 分轨
- **Bundle ID `com.sunhongjun.glance` 不变**(D5.6 同 ID 共享 sandbox container, 老用户数据无缝继承)

---

## 9. 时间线建议(P1-6 修正, 2-3 周日历)

按军哥实际节奏:

| 第几天 | 工作 | 阻塞 |
|---|---|---|
| Day 1 | 任务 1 证书 + App ID + API Key + 任务 5 GitHub Pages | 等 Apple 颁发证书(~几分钟) |
| Day 2-3 | 任务 2 pbxproj + Privacy Manifest 审计 + 任务 4 release-appstore.sh | CC 写 |
| Day 4-5 | 任务 3 App Store Connect 元数据 + Privacy Nutrition Labels + 任务 6 截图 | 军哥本机做 |
| Day 6 | 任务 7.0 TestFlight 内测 + 任务 7.1-7.5 上传 + 准备审核备注 | CC + 军哥 |
| Day 7 | 提交审核 | 等 Apple |
| Day 8-10 | 等 Apple 首次审核 | Apple 审核中, 此期间可继续 dev 新 feature |
| Day 10-12 | 第一次拒因 → 改 metadata/manifest/截图 → 重提 | 军哥 + CC |
| Day 13-15 | 第二次审核, 期望通过 | 等 Apple |
| Day 15+ | 任务 8 + 9 上架后宣传 + 文档同步 | 军哥小红书 |

**Total 2-3 周内可上架**(含 1-2 次拒因+改+重提 cycle, P1-6 修正)

---

## 10. 后续 follow-up(本 design 不涵盖)

- App Store 评分 / 评论运营
- **价格策略调整(从免费切付费 / 加 IAP)**(P2-2 警示): 本 design D3 锁免费, 后续若转付费会引入 **App Review 重审 + 权利变更 + Family Sharing + 税务 + 产品定位** 连带工作, **不是小改动**, 需要独立 brainstorming + plan
- 多语言 metadata(英日韩等) — D4 全球但 metadata 中文为主, 海外用户体验后续优化
- 自买域名 `glance.app` — D5.2 暂不付费, 后续看品牌投入再说
- App Store 推荐位 / 编辑荐选 申请
- Privacy Manifest 年度核查 — Apple 每年可能更新 required-reason 列表, 提交新版前重审

---

## 11. codex review v1 P0/P1/P2 折入对照表

| codex 等级 | 问题 | 本 v2 落地 |
|---|---|---|
| **P0-1** | build pipeline 错(productbuild 路径) | Section 3.1 + Task 4 改 `xcodebuild -exportArchive` + 加 `ExportOptions-AppStore.plist` |
| **P0-2** | Privacy Manifest 漏 | 新增 Task 2.7 + Task 5 强化本地索引明示 + Task 3.9 Nutrition Labels |
| **P0-3** | 双渠道签名隔离模糊 | Section 3.2 改"两次独立 archive" + Task 2.1 新 build scheme |
| **P0-4** | 同 Bundle ID 双渠道数据共享决策 | 新增 D5.6 拍板 = 同 ID 共享 + 新增 Task 8.4 双装兜底文档 |
| **P1-1** | 上传凭据应 API Key/JWT | 新增 D5.7 + Task 1.5 创建 API Key + Task 7.2 用 altool --apiKey |
| **P1-2** | Hardened Runtime / profile 权利匹配 | Task 2.5 审计 + 不强制开 / Task 2.2 entitlements 审计 + 新增 Glance-AppStore.entitlements 分轨 |
| **P1-3** | 审核员空态可复现性 | Task 7.5 准备审核备注 + 风险点段加新条 |
| **P1-4** | FSEvents 沙盒走查 | Task 7.0 TestFlight + 风险点段加新条 |
| **P1-5** | 隐私政策本地文件强化 | Task 5.3 加"本地索引明示"中英双语 |
| **P1-6** | 时间预估 1 周 → 2-3 周 | Section 6 + 9 改 2-3 周日历 + 含 1-2 次拒因 cycle |
| **P2-1** | TestFlight 预留 | Task 7.0 加 TestFlight 内测可选 step |
| **P2-2** | IAP 远期警示 | Section 2 Scope 写明 + Section 10 follow-up 强化 |
| **P2-3** | 截图真实性约束 | Task 3.3 + Task 6.2 必须用 App Store build 抓 |
