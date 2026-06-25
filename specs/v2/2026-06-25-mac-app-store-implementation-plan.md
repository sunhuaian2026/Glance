# Mac App Store 上架 Implementation Plan

**Date**: 2026-06-25
**Status**: draft, awaiting codex review + 军哥拍板
**Design 来源**: `specs/v2/2026-06-25-mac-app-store-design.md` (v3, codex round 2 折入完成, 7c3926e)
**Scope**: v2.3 已 ship GitHub Release(Developer ID + Notarize + DMG)路径, 此 plan 落实另一条分发路径 — Mac App Store(Apple Distribution + .pkg + App Review), 双轨并存, 首发 v2.3.0 跟 GitHub v2.3 同 commit。

---

## 0. 全局约束

- **代码同一份**: App Store 用跟 GitHub v2.3 完全一致的代码, 不引入新 feature, 仅签名 + 包格式 + Privacy Manifest 差异
- **Bundle ID 不变**: `com.sunhongjun.glance` (D5.6 共享 sandbox container)
- **Team ID**: `8KW8Z92GRA`
- **MARKETING_VERSION**: `2.3.0` (跟 GitHub v2.3 同)
- **macOS 部署目标**: 14.0 (已设, 不变)
- **不动现有 release.sh / make release / GitHub Release v2.3 / Glance.entitlements**(必要时新增 `Glance-AppStore.entitlements` 分轨, 详见任务 2)
- **不付费 / 不内购 / 不订阅** (D3)
- **术语**: 走 CONTEXT.md 术语字典(快速看图器 / 重复清理 / 缩略图 / 侧边栏 等中文规范)。本 plan 称工作单元为「任务」, 不用 `Slice` / `VS` / `切片`(禁用词全包 inline backtick 免触 verify.sh 字典 enforcement)

---

## 1. 任务一览

| 任务 | 顶层目标 | 估时 | 阻塞类型 | 端到端验证锚点 |
|---|---|---|---|---|
| 任务 1 | Apple Developer 证书 + App ID + App Store Connect API Key | 1h | 等 Apple | `security find-identity` 列出 Apple Distribution + `xcrun altool --list-providers --apiKey ...` 成功 |
| 任务 2 | pbxproj 加 `Release-AppStore` build configuration + Privacy Manifest + entitlements 审计 | 1.5-2h | CC | `xcodebuild -showBuildSettings -configuration Release-AppStore` 看到正确签名 + Xcode 16 build 看 Privacy Manifest 嵌入无 warning |
| 任务 3 | App Store Connect 后台元数据 + Privacy Nutrition Labels | 3-4h | 军哥填(主) | App Store Connect "App Information" + "Pricing" + "Privacy" 全绿状态 |
| 任务 4 | `scripts/release-appstore.sh` + `ExportOptions-AppStore.plist` + Makefile target | 2-3h | CC | `make release-appstore` 跑通出 `dist/export-appstore/Glance.pkg` + `pkgutil --check-signature` 通过 |
| 任务 5 | GitHub Pages 隐私政策(中英双语) | 2h | CC | `curl -I https://sunhuaian2026.github.io/Glance/privacy.html` 返回 200 |
| 任务 6 | 截图准备(7 张, App Store build 抓 + Figma 标语包装) | 2-3h | 军哥本机做(主) | `assets/appstore-screenshots/` 7 张 2880×1800 PNG 齐 |
| 任务 7 | TestFlight 内测预 step + altool 上传 + 准备审核备注 + 提交审核 | 上传 30min + 等 Apple 2-3 周 | 等 Apple | App Store Connect "App Review" 状态翻 In Review → Pending Developer Release |
| 任务 8 | 双轨上架后 + 双装兜底(D5.6 降级 dialog 落代码) + README badge | 1.5h | CC + 军哥 | 旧版 binary 打开新 schema DB 弹明确 error dialog 不允许 silent corruption |
| 任务 9 | Roadmap + CONTEXT 同步 + PENDING-USER-ACTIONS 加项 | 30min | CC | `./scripts/verify.sh` Stage 1 通过 + commit 推 |

**总工时**: CC ~7-9h + 军哥 ~5-7h + Apple 等审核 2-3 周日历(含 1-2 次拒因 cycle)

---

## 任务 1 — Apple Developer 证书 + App ID + ASC API Key

### 验证锚点(任务完成时)
- `security find-identity -v -p codesigning` 列出 `Apple Distribution: Hongjun Sun (8KW8Z92GRA)`
- `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` 存在
- `xcrun altool --list-providers --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>` 输出 team `8KW8Z92GRA`
- App Store Provisioning Profile 装到 keychain + `~/Library/MobileDevice/Provisioning Profiles/` 出现 `<profile-uuid>.provisionprofile`

### 步骤

| 步骤 | 动作 | 落点 | 备注 |
|---|---|---|---|
| 1.1 | https://developer.apple.com/account/resources/identifiers — 确认 App ID `com.sunhongjun.glance` 已开 App Store distribution(若 v1.0 当时只开 Developer ID, 此处加勾) | Apple 后台 | 现 Bundle ID 已用于 Developer ID, 仅需扩 capability, 不改 ID |
| 1.2 | 创建 `Apple Distribution` 证书(Apple 推荐统一证书, 同时支持 macOS App Store + Ad Hoc); 下载 .cer 双击装 login keychain | Apple 后台 + Mac mini keychain | **不需要 `Mac Installer Distribution` 证书** — xcodebuild -exportArchive 走 ExportOptions-AppStore.plist 自动用 Apple Distribution 的 installer counterpart |
| 1.3 | 创建 macOS App Store Provisioning Profile, 关联 App ID `com.sunhongjun.glance` + Apple Distribution 证书; 下载 .provisionprofile 双击装 | Apple 后台 + Mac mini keychain + `~/Library/MobileDevice/Provisioning Profiles/` | 记下 profile 名(任务 2/4 用) |
| 1.4 | https://appstoreconnect.apple.com/access/api — 创建 Team Key, 权限 **App Manager** | ASC 后台 | App Manager 足够 upload + 改 metadata, 不给 Admin 减少权限暴露 |
| 1.5 | 下载 `AuthKey_<KEY_ID>.p8`, 保存到 `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`(altool 默认查找路径) | Mac mini 本地 | 这文件**仅下载一次**, 不可二次下载; 备份到家里 MacStudio + 冷备份 |
| 1.6 | 记下 `Key ID` + `Issuer ID`(任务 4 + 7 用 altool 时传) | ASC 后台 | 写到密码管理器, 不写仓库 |
| 1.7 | 备份: `.cer` / `.p12`(导出 Apple Distribution 私钥) / `.p8` 全套到家里 MacStudio + 冷备份(mirror v1.0 流程) | 本地 | 私钥丢了 = 重申证书 |
| 1.8 | 验证: `security find-identity -v -p codesigning \| grep "Apple Distribution"` 出一行; `xcrun altool --list-providers --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>` 出 team 8KW8Z92GRA | Mac mini | 任一失败 stop, 重看上面步骤 |

### 凭据体系独立性说明(防混淆, 折入 design 的 codex P2(round 2, API Key 跟 keychain-profile 不冲突))
- `release.sh` 用 `NOTARY_PROFILE=glance-notary` keychain profile(App-Specific Password) → Developer ID notarize
- 本任务的 ASC API Key(`.p8` + JWT) → App Store 上传
- **两套凭据独立, 同 keychain 共存不互扰**

### 回滚
- API Key 失效 → 后台撤销旧 Key + 重生新 Key + 重装 `.p8`
- 证书装 keychain 失败 → Apple Developer 后台 revoke + 重申, 通常 5min 内拿到

---

## 任务 2 — pbxproj `Release-AppStore` configuration + Privacy Manifest + entitlements 审计

### 验证锚点
- `xcodebuild -list -project Glance.xcodeproj` 列出 `Release-AppStore` 配置 + `Glance AppStore` scheme
- `xcodebuild -showBuildSettings -project Glance.xcodeproj -configuration Release-AppStore -scheme "Glance AppStore" \| grep -E "CODE_SIGN_IDENTITY|PROVISIONING_PROFILE_SPECIFIER|CODE_SIGN_ENTITLEMENTS"` 输出 Apple Distribution + App Store profile + Glance-AppStore.entitlements
- `Glance/PrivacyInfo.xcprivacy` 存在, plist 合法(`plutil -lint Glance/PrivacyInfo.xcprivacy` 通过)
- Xcode 16 build `Release-AppStore` configuration 不报 Privacy Manifest 相关 warning

### 步骤

#### 2.1 新建 `Release-AppStore` build configuration(codex round 2 P0-6: 仅新 scheme 不够防签名互扰)

| 步骤 | 文件 | 改动 |
|---|---|---|
| 2.1.a | `Glance.xcodeproj/project.pbxproj` | 在 `XCConfigurationList`(project + target 两处)的 `buildConfigurations` 段加 `Release-AppStore` 配置, 基于现有 `Release` 拷贝, 覆盖以下 build settings: |
| 2.1.b | (同上) | `CODE_SIGN_IDENTITY = "Apple Distribution"` |
| 2.1.c | (同上) | `PROVISIONING_PROFILE_SPECIFIER = "<App Store Glance Profile>"`(任务 1.3 创建的 profile 名) |
| 2.1.d | (同上) | `CODE_SIGN_ENTITLEMENTS = Glance/Glance-AppStore.entitlements`(2.4 创建) |
| 2.1.e | (同上) | `CODE_SIGN_STYLE = Manual` |
| 2.1.f | (同上) | 保留 `ENABLE_HARDENED_RUNTIME = YES`(跟 Release 行为一致, codex P1(round 1, Hardened Runtime / profile 权利匹配) 不强制但建议) |
| 2.1.g.0 | **先决**: 现仓库**无 shared scheme**(只有 user 态 `xcuserdata/.../xcschememanagement.plist`, codex review plan 抓到的真问题: P1(shared-scheme-source-missing)) | 必须先 Xcode GUI 打开 → Product → Scheme → Manage Schemes → 勾选 `Glance` 的 "Shared" 列 → 提交 `Glance.xcodeproj/xcshareddata/xcschemes/Glance.xcscheme`(新建文件 commit 入仓), 再做 2.1.g.1 |
| 2.1.g.1 | `Glance.xcodeproj/xcshareddata/xcschemes/Glance AppStore.xcscheme` (新建) | 在 2.1.g.0 后, 拷贝 `Glance.xcscheme` 重命名为 `Glance AppStore.xcscheme`, 把 Archive action 的 `buildConfiguration` 改 `Release-AppStore`; 共享 scheme |
| 2.1.h | 终端 | `xcodebuild -list` 验证 `Release-AppStore` + `Glance AppStore` 都出现 |
| 2.1.i | 终端 | `xcodebuild -showBuildSettings -configuration Release-AppStore -scheme "Glance AppStore" 2>&1 \| grep -E "CODE_SIGN_IDENTITY \= \|PROVISIONING_PROFILE_SPECIFIER \= \|CODE_SIGN_ENTITLEMENTS \= "` 输出 3 行匹配预期 |

**实施纪律**: pbxproj 手编是高危操作(格式严格). 实施时**先备份** `cp Glance.xcodeproj/project.pbxproj Glance.xcodeproj/project.pbxproj.bak` → 改 → `plutil -lint Glance.xcodeproj/project.pbxproj` 验证合法 → 再 `xcodebuild -list` 验证 → 不行立即 `cp project.pbxproj.bak project.pbxproj` 还原。若 pbxproj 损坏无法救场, GUI Xcode → Editor → Add Configuration → Duplicate Release 配 = pbxproj 救场 fallback。

#### 2.2 entitlements 审计 + 新增 `Glance-AppStore.entitlements`(分轨, codex round 1 P1(Hardened Runtime / profile 权利匹配) + codex plan review P1(pbxproj-entitlement-source-split))

**codex plan review P1(pbxproj-entitlement-source-split) 修正**: 现 pbxproj **没有 `CODE_SIGN_ENTITLEMENTS` 字段引用 `Glance.entitlements` 文件**, 沙盒权利由 build settings 自动生成(`SystemCapabilities` 段, `project.pbxproj:269/302`). 直接给 Release-AppStore 配置加 `CODE_SIGN_ENTITLEMENTS = Glance/Glance-AppStore.entitlements` 后, 双轨权利来源不对称(Release 走 auto-generated, Release-AppStore 走 file), 易漏配 + 难维护。**修正**: 2.2 步骤新增前置项 2.2.0, 先把现有 Debug + Release 两 configuration 也改为显式引用 `Glance.entitlements` 文件, 让两轨权利来源对称都从 file 走。

| 步骤 | 文件 | 改动 |
|---|---|---|
| 2.2.0 | `Glance.xcodeproj/project.pbxproj` (Debug + Release 两 configuration, **本步骤为 codex P1 修正前置项**) | 加 `CODE_SIGN_ENTITLEMENTS = Glance/Glance.entitlements;` 到两配置 build settings; 跑 `make build` 验证沙盒能力没变化(关于面板 / 文件选择行为一致), 确认 explicit 引用跟 auto-generated 等价 |
| 2.2.a | 终端 | `diff Glance/Glance.entitlements <(echo expected)` — 确认现有 3 键: `com.apple.security.app-sandbox=true` / `com.apple.security.files.user-selected.read-write=true` / `com.apple.security.files.bookmarks.app-scope=true`(已验) |
| 2.2.b | `Glance/Glance-AppStore.entitlements`(新建) | 拷贝 `Glance.entitlements` 同样 3 键, 内容**完全一致**(我们功能跟 Developer ID 路径 100% 一样) |
| 2.2.c | 验证 | `plutil -lint Glance/Glance-AppStore.entitlements` 通过 |
| 2.2.d | **必须不加**: `com.apple.security.network.client`(零网络) / JIT / `cs.allow-*` 危险权利 — App Review 看到会问 | — | — |

**理由**: 单独文件分轨好处 = release.sh 路径不改任何 entitlement; 未来 App Store 若需加权利不污染 Developer ID 路径。坏处 = 两文件需同步维护, 但内容一致 + verify.sh 加一行 diff 检查即可。

#### 2.3 LSApplicationCategoryType(D5.1)

| 步骤 | 文件 | 改动 |
|---|---|---|
| 2.3.a | `Glance.xcodeproj/project.pbxproj` (project + target 两处 build settings, **所有 Configuration** Debug/Release/Release-AppStore) | 加 `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities"`(D5.1 Primary; Secondary "Photography" 在 ASC 后台填) |
| 2.3.b | 验证 | `xcodebuild -showBuildSettings \| grep LSApplicationCategoryType` 出现 `public.app-category.utilities` |

#### 2.4 Privacy Manifest 新建 `Glance/PrivacyInfo.xcprivacy`(codex P0-2 round 1 + P0-5 round 2 强制)

**实施前必做**: Read Apple 官方页面 "Describing use of required reason API" 逐字核对所有 reason code; 下面是**初步推断**, 具体 code 以 Apple doc 实施时为准。

| 步骤 | 文件 | 改动 |
|---|---|---|
| 2.4.a | `Glance/PrivacyInfo.xcprivacy`(新建) | plist 结构, root 4 个键: `NSPrivacyAccessedAPITypes` / `NSPrivacyCollectedDataTypes` / `NSPrivacyTracking` / `NSPrivacyTrackingDomains` |
| 2.4.b | `NSPrivacyAccessedAPITypes` (array of dict) | 必含 2 个 dict 条目: |
| 2.4.c | 条目 1 — `UserDefaults` | `NSPrivacyAccessedAPIType = NSPrivacyAccessedAPICategoryUserDefaults` + `NSPrivacyAccessedAPITypeReasons = [<reason code>]` (推断 `CA92.1` 或 `1C8F.1`, Apple doc 核对). Reality check: BookmarkManager `bookmarkSchemaVersion`(line 12) + `defaultsKey` bookmarks dict(line 52) / FolderStore `sortKey/sortDirection`(line 68-69) + `thumbnailSize`(line 83) / AppState `appearanceMode`(line 53) — 大量用必须声明 |
| 2.4.d | 条目 2 — `FileTimestamp` | `NSPrivacyAccessedAPIType = NSPrivacyAccessedAPICategoryFileTimestamp` + reason code 推断 `0A2A.1`(Apple doc 实施核, **0A2A.1 可能非确认值**, codex round 2 抓 reason code 需实测确认). Reality check: FolderStore line 369/371/397/399 用 `.contentModificationDateKey`; line 376/378/404/406 用 `.fileSizeKey`; ImageInspectorViewModel line 63/69/74 同 |
| 2.4.e | 不声明项(已 codex round 2 修正 DiskSpace 错映射) | `CryptoKit SHA256`(ContentHasher.swift 第 21 行) / `Vision feature print` / `FSEvents` / `SQLite C API` / `FileManager.trashItem` / `FileManager.contentsOfDirectory` / `Security Scoped Bookmark` — 实测不在 Apple required-reason 列表 |
| 2.4.f | `NSPrivacyCollectedDataTypes = []` | 空数组 — Glance 零数据收集 |
| 2.4.g | `NSPrivacyTracking = false` | 零跟踪 |
| 2.4.h | `NSPrivacyTrackingDomains = []` | 零跟踪域名 |
| 2.4.i | pbxproj | 把 `PrivacyInfo.xcprivacy` 加进 target 的 Copy Bundle Resources(PBXFileSystemSynchronizedRootGroup 应自动加入, 验证 `xcodebuild build -configuration Release-AppStore` 后 `find ~/Library/Developer/Xcode/DerivedData -name PrivacyInfo.xcprivacy \| grep Glance.app/Contents/Resources` 出文件) |
| 2.4.j | `plutil -lint Glance/PrivacyInfo.xcprivacy` 通过 | — |

**Privacy Manifest 影响**: archive 时自动嵌入 .app/Contents/Resources/PrivacyInfo.xcprivacy, App Store 上传时 Apple 校验, 不符直接拒。

#### 2.5 Hardened Runtime 审计(codex round 1 P1(Hardened Runtime / profile 权利匹配))
- **保持开启**: `ENABLE_HARDENED_RUNTIME = YES` 在 Release-AppStore 配置同步 Release(2.1.f 已加)
- App Store 不强制 Hardened Runtime, 但 Developer ID 路径开了, App Store 也开保持行为一致, 同时让代码 path 唯一(不需要为 `#if APPSTORE` 分轨)

#### 2.6 验证(任务 2 完成判定)

| 步骤 | 命令 | 期望 |
|---|---|---|
| 2.6.a | `xcodebuild -list -project Glance.xcodeproj` | 列出 `Release-AppStore` + `Glance AppStore` |
| 2.6.b | `xcodebuild -showBuildSettings -configuration Release-AppStore -scheme "Glance AppStore" 2>&1 \| grep -E "CODE_SIGN_IDENTITY \= Apple Distribution\|PROVISIONING_PROFILE_SPECIFIER \= \|CODE_SIGN_ENTITLEMENTS \= "` | 3 行匹配预期值 |
| 2.6.c | `plutil -lint Glance/PrivacyInfo.xcprivacy Glance/Glance-AppStore.entitlements` | 两文件 OK |
| 2.6.d | `xcodebuild build -configuration Release-AppStore -scheme "Glance AppStore" -quiet`(干 build 不 archive) | 0 error 0 warning |
| 2.6.e | `find ~/Library/Developer/Xcode/DerivedData -name "PrivacyInfo.xcprivacy" -path "*Glance.app/*"` | 1 个文件 |

### 回滚
- pbxproj 改坏 → `cp project.pbxproj.bak project.pbxproj` 还原, 重做
- Privacy Manifest reason code 写错 → Xcode 16 build 时 warn / Apple 校验拒因 → 按提示 fix 重 archive

---

## 任务 3 — App Store Connect 后台元数据 + Privacy Nutrition Labels

### 验证锚点
- App Store Connect 后台 "App Information" / "Pricing and Availability" / "App Privacy" / "Version Information"(v2.3.0) 四块全绿(状态 "Ready to Submit")
- 截图 5-7 张上传(任务 6 产出)
- Bundle ID 关联到 `com.sunhongjun.glance`
- 隐私政策 URL 填到 GitHub Pages(任务 5 产出)

### 步骤

#### 3.1 创建 App Store Connect App
| 步骤 | 落点 | 改动 |
|---|---|---|
| 3.1.a | https://appstoreconnect.apple.com → My Apps → + → 新 macOS App | — |
| 3.1.b | Platform: macOS / Name: `Glance · 一眼` / Primary Language: 简体中文 / Bundle ID: `com.sunhongjun.glance`(从下拉选, 任务 1.1 已注册) / SKU: `glance-v2-3`(内部用, 不可见) | — |
| 3.1.c | User Access: Full Access(独立开发者默认) | — |

#### 3.2 元数据(中英双语, 中文为主)

| 字段 | 中文 | 英文 |
|---|---|---|
| **名称**(30 字) | `Glance · 一眼` | `Glance` |
| **副标题**(30 字) | `找重复省空间 · 沉浸看图` | `Find duplicates, save space` |
| **关键词**(100 字符) | `重复清理,看图,相似图,省空间,本地,沉浸,缩略图,EXIF,Mac看图器,duplicate` | (中文版重用, 多区不强求 i18n) |
| **描述**(4000 字) | 突出"重复清理 / 找相似图 / 零网络零遥测 / 本地 / 沉浸看图"(实施时写 800-1500 字, 中英双语版各 1 份, 参考 README) | — |
| **支持 URL** | `https://github.com/sunhuaian2026/Glance` (GitHub Issues) | 同 |
| **隐私政策 URL** | `https://sunhuaian2026.github.io/Glance/privacy.html` (任务 5 建) | 同 |
| **营销 URL** | 空(可选) | 同 |

#### 3.3 App 图标 / 价格 / 区域 / 分类 / 年龄

| 字段 | 值 |
|---|---|
| App 图标 | `assets/icon-1024.png` 1024×1024 PNG ✓(已有, reality check 通过) |
| 价格 | 免费(D3) |
| 国家区域 | 全球 175 国 默认全勾(D4) — EU DSA Non-Trader 已申报 |
| Primary 分类 | `Utilities` (D5.1) |
| Secondary 分类 | `Photography` (D5.1) |
| 年龄分级 | 4+ (无成人内容) — 后台答 12 个问题全 No / Never |

#### 3.4 截图上传(任务 6 准备完)

| 步骤 | 改动 |
|---|---|
| 3.4.a | 上传 5-7 张 2880×1800 PNG 到 macOS App Preview & Screenshots 段 |
| 3.4.b | **codex round 1 P2(截图真实性约束)**: 截图必须**用 App Store build 抓**(任务 4 产出的 .pkg 解包安装版, **不是**复用 GitHub Developer ID build), 避免 metadata mismatch 拒因 |

#### 3.5 Privacy Nutrition Labels(App Store Connect "App Privacy" 段, 跟 Privacy Manifest 互补必填)

| 段 | 选项 |
|---|---|
| 数据收集 | "App 不会收集数据"(Does not collect data) — All sections empty |
| 跟踪 | 否 |
| 链接到用户 | 否 |
| 数据用途 | 不适用(零数据) |

**呼应任务 2.4 Privacy Manifest 内容**, 后台填表跟 Manifest 不一致会被 App Review 抓。

#### 3.6 验证

| 步骤 | 命令/动作 | 期望 |
|---|---|---|
| 3.6.a | App Store Connect → App Information | "Ready to Submit" 状态绿 |
| 3.6.b | App Privacy | "Manage" 不再红, 所有 "Get Started" 跑完 |
| 3.6.c | Pricing | Free + 175 国全勾 |
| 3.6.d | macOS Version Information v2.3.0 | Build 等任务 7 上传后再关联 |

### 回滚
- 后台填错 → 直接改, ASC 后台允许 submit 前任意编辑
- Bundle ID 选错(选了别人的) → App 删了重建(不可逆但成本低)

---

## 任务 4 — `scripts/release-appstore.sh` + `ExportOptions-AppStore.plist` + Makefile target

### 验证锚点
- `make release-appstore` 跑通(SKIP_NOTARIZE 不需要, App Store 路径无 notarize)
- `dist/export-appstore/Glance.pkg` 存在
- `pkgutil --check-signature dist/export-appstore/Glance.pkg` 输出 "signed by Apple submission services / Software Signing"
- `dist/Glance-AppStore.xcarchive` 跟 `dist/Glance.xcarchive` 共存不冲突
- `xattr -l dist/export-appstore/Glance.pkg \| grep -v -E "^\s*$"` 不含 `com.apple.quarantine`

### 步骤

#### 4.1 新建 `scripts/ExportOptions-AppStore.plist`(codex round 2 P1(ExportOptions plist 字段不全)补字段)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>8KW8Z92GRA</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Apple Distribution</string>
    <key>installerSigningCertificate</key>
    <string>3rd Party Mac Developer Installer</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.sunhongjun.glance</key>
        <string><App Store Glance Profile></string>
    </dict>
    <key>uploadSymbols</key>
    <false/>
    <key>compileBitcode</key>
    <false/>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
```

**实施前必做**(codex round 2 P1(ExportOptions plist 字段不全) + codex plan review P1(export-method-deprecated)):
- 上面 `method=app-store-connect` 已经是当前 Xcode 接受的值(codex plan review 实测 `xcodebuild -help` 输出 `app-store-connect` 为当前值, `app-store` 已 deprecated)
- profile name `<App Store Glance Profile>` 替换为任务 1.3 创建的真实 profile 名
- 实施时 `xcodebuild -help \| grep -A5 exportOptionsPlist` 复核当前 Xcode 仍接受 `app-store-connect`(防 Xcode 后续版本再变); 如果当前 Xcode 报 `app-store-connect` 也 deprecated 了, 以实测为准

#### 4.2 新建 `scripts/release-appstore.sh`

mirror `scripts/release.sh` 结构, 关键差异:

```bash
#!/bin/bash
# release-appstore.sh — Glance Mac App Store 上架打包流程
#
# 流程: xcodebuild archive (Release-AppStore + Apple Distribution signed)
#   → exportArchive → dist/export-appstore/Glance.pkg
#
# Usage: ./scripts/release-appstore.sh
#
# 环境变量:
#   ASC_API_KEY_ID      App Store Connect API Key ID(任务 1.4)
#   ASC_API_ISSUER_ID   App Store Connect Issuer ID(任务 1.6)
#                       — 这两个上传时(任务 7)用, 本脚本不直接用, 仅 export 不上传
#
# 注意: 跟 release.sh 独立, 两次 archive 互不冲突(独立 archive 路径 + 独立
#       build configuration)

set -euo pipefail

# ============== 配置 ==============
PROJECT="Glance.xcodeproj"
SCHEME="Glance AppStore"
CONFIGURATION="Release-AppStore"
TEAM_ID="8KW8Z92GRA"
BUNDLE_ID="com.sunhongjun.glance"
SIGN_IDENTITY="Apple Distribution"

# 跟 release.sh 同 marketing version + build version 注入逻辑
MARKETING_VERSION="2.3.0"
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
DIRTY=""
if ! git diff --quiet HEAD -- Glance/ Makefile scripts/ 2>/dev/null; then
    DIRTY="-d"
fi
STAMP=$(date +%m%d-%H%M)
BUILD_VERSION="${COMMIT}${DIRTY}.${STAMP}"

COPYRIGHT="© 2026 孙红军 · 16414766@qq.com · 小红书 382336617"

# 路径(跟 release.sh 完全独立, 不互覆盖)
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
ARCHIVE_PATH="${DIST_DIR}/Glance-AppStore.xcarchive"
EXPORT_PATH="${DIST_DIR}/export-appstore"
PKG_PATH="${EXPORT_PATH}/Glance.pkg"
EXPORT_OPTIONS="${ROOT_DIR}/scripts/ExportOptions-AppStore.plist"

cd "${ROOT_DIR}"

# ============== Pre-flight checks ==============
echo "==> Pre-flight checks"

if ! security find-identity -v -p codesigning | grep -q "${SIGN_IDENTITY}: Hongjun Sun (${TEAM_ID})"; then
    echo "❌ Apple Distribution identity 没装到 login keychain"
    echo "   期望: \"${SIGN_IDENTITY}: Hongjun Sun (${TEAM_ID})\""
    echo "   去 Apple Developer 创建/下载 .cer + 私钥(.p12)装到登录 keychain"
    exit 1
fi
echo "  ✓ Apple Distribution identity OK"

if [[ ! -f "${EXPORT_OPTIONS}" ]]; then
    echo "❌ ExportOptions-AppStore.plist 不存在: ${EXPORT_OPTIONS}"
    exit 1
fi
echo "  ✓ ExportOptions-AppStore.plist OK"

# ============== Clean ==============
echo ""
echo "==> Clean previous AppStore artifacts"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"
mkdir -p "${DIST_DIR}"

# ============== Step 0: Pre-archive quarantine xattr 清理(codex round 2 P0-7) ==============
# Apple 2025-02-18 起 TestFlight/App Store 提交不能带 com.apple.quarantine xattr
echo ""
echo "==> Step 0/4: Pre-archive — 清 quarantine xattr"
xattr -dr com.apple.quarantine . 2>/dev/null || true
xattr -dr com.apple.quarantine dist/ 2>/dev/null || true
echo "  ✓ quarantine xattr cleared"

# ============== Step 1: Archive (Apple Distribution + Release-AppStore configuration) ==============
echo ""
echo "==> Step 1/4: xcodebuild archive (Release-AppStore + Apple Distribution)"
echo "    Marketing: ${MARKETING_VERSION} | Build: ${BUILD_VERSION}"

xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
    ENABLE_HARDENED_RUNTIME=YES \
    CURRENT_PROJECT_VERSION="${BUILD_VERSION}" \
    INFOPLIST_KEY_NSHumanReadableCopyright="${COPYRIGHT}" \
    -quiet

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
    echo "❌ Archive 失败: ${ARCHIVE_PATH} 不存在"
    exit 1
fi
echo "  ✓ Archive: ${ARCHIVE_PATH}"

# ============== Step 2: Export Archive → .pkg ==============
echo ""
echo "==> Step 2/4: exportArchive (Apple 推荐路径, 自动签 .pkg)"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -quiet

if [[ ! -f "${PKG_PATH}" ]]; then
    echo "❌ .pkg 不存在: ${PKG_PATH}"
    exit 1
fi
echo "  ✓ .pkg: ${PKG_PATH}"

# ============== Step 3: Post-export quarantine xattr 验证(codex round 2 P0-7) ==============
echo ""
echo "==> Step 3/4: Post-export — 验证 quarantine xattr 干净"
if xattr -l "${PKG_PATH}" 2>/dev/null | grep -q quarantine; then
    echo "❌ Glance.pkg 仍含 com.apple.quarantine xattr, Apple 会拒"
    exit 1
fi
echo "  ✓ quarantine xattr 干净"

# ============== Step 4: pkgutil 签名校验 ==============
echo ""
echo "==> Step 4/4: pkgutil --check-signature"
pkgutil --check-signature "${PKG_PATH}" 2>&1 | head -20

# ============== Summary ==============
PKG_SIZE=$(du -h "${PKG_PATH}" | awk '{print $1}')
echo ""
echo "================================================================"
echo "✅ App Store .pkg 包构建完成"
echo ""
echo "  .pkg:          ${PKG_PATH}"
echo "  Size:          ${PKG_SIZE}"
echo "  Marketing:     ${MARKETING_VERSION}"
echo "  Build:         ${BUILD_VERSION}"
echo ""
echo "  下一步: 任务 7 走 altool/Transporter 上传到 App Store Connect"
echo "  上传命令(任务 7):"
echo "    xcrun altool --upload-app --type macos \\"
echo "      --file ${PKG_PATH} \\"
echo "      --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
echo "================================================================"
```

#### 4.3 Makefile 加 target

```makefile
# Mac App Store 上架打包: xcodebuild archive (Release-AppStore + Apple Distribution)
#   → exportArchive → dist/export-appstore/Glance.pkg
release-appstore:
	@chmod +x scripts/release-appstore.sh 2>/dev/null || true
	@./scripts/release-appstore.sh
```

加到 `.PHONY` 行末尾: `.PHONY: build run clean hooks-install hooks-uninstall verify verify-codex release release-dry release-appstore`

#### 4.4 验证

| 步骤 | 命令 | 期望 |
|---|---|---|
| 4.4.a | `chmod +x scripts/release-appstore.sh` | — |
| 4.4.b | `make release-appstore` | 4 步全过, exit 0 |
| 4.4.c | `ls -la dist/Glance-AppStore.xcarchive/Products/Applications/Glance.app/Contents/MacOS/Glance` | binary 存在 |
| 4.4.d | `codesign -dvvv dist/Glance-AppStore.xcarchive/Products/Applications/Glance.app 2>&1 \| grep -E "Authority\|TeamIdentifier"` | Authority 包含 `Apple Distribution`, TeamIdentifier=8KW8Z92GRA |
| 4.4.e | `find dist/Glance-AppStore.xcarchive -name "PrivacyInfo.xcprivacy"` | 1 个文件(嵌入到 .app) |
| 4.4.f | `pkgutil --check-signature dist/export-appstore/Glance.pkg` | "signed by Apple submission services" 或 "Software Signing"(Apple 签 installer cert) |
| 4.4.g | `make release-dry` 跟 `make release-appstore` 顺序跑 + 互不污染验证 | 两次 archive 独立 path, GitHub Developer ID 路径不报错 |

### 回滚
- exportArchive 失败 / signing 错 → 校 profile name + signing identity + provisioning profile UUID match Bundle ID
- pkgutil 报 .pkg unsigned → ExportOptions-AppStore.plist 的 `installerSigningCertificate` 字段错 / Apple Distribution profile 不含 Installer counterpart, 重看 Apple Developer 后台

---

## 任务 5 — GitHub Pages 隐私政策(中英双语)

### 验证锚点
- `curl -I https://sunhuaian2026.github.io/Glance/privacy.html` 返回 `HTTP/2 200`
- 浏览器打开页面渲染正常, 中英双语段都在
- GitHub Pages settings 显示 "Your site is live at https://sunhuaian2026.github.io/Glance/"
- 任务 3.2 元数据"隐私政策 URL"填的就是这个 URL

### 步骤

#### 5.1 新建 `docs/privacy.html`(GitHub Pages 默认从 `/docs/` 或 `gh-pages` branch 提供)

| 步骤 | 文件 | 改动 |
|---|---|---|
| 5.1.a | 终端 | `mkdir -p docs` (验证: 现项目 `docs/` 已存, 含 `archive/` `release-notes/`, 不冲突) |
| 5.1.b | `docs/privacy.html`(新建) | 写 HTML 单页, 中英双语两段, 覆盖以下 7 个段(下面 5.2 详) |
| 5.1.c | 验证本地 | `open docs/privacy.html` 浏览器渲染正常 |

#### 5.2 privacy.html 内容(中英双语, 各 7 段)

实施时写完整 HTML, 中英双语 7 段如下:

1. **承诺** — 零网络请求 / 零数据上传 / 零遥测(Glance 核心承诺)
2. **本地索引明示**(codex round 1 P1(隐私政策本地文件强化)) — 缩略图 / SHA256 内容指纹 / Vision 图像指纹 / SQLite 索引 **全部存设备本地** `~/Library/Containers/com.sunhongjun.glance/Application Support/`, **不上传任何服务器**
3. **用户授权** — 通过 `Security Scoped Bookmark` 机制仅本机访问, 用户主动选择文件夹
4. **删除安全** — 重复清理走 macOS 系统废纸篓(`FileManager.trashItem`), 不直接 unlink 文件
5. **联系方式** — 邮箱 `16414766@qq.com` / 小红书 `382336617` / GitHub Issues
6. **法律框架** — 零数据收集前提下按 GDPR / CCPA / PIPL 框架声明"用户数据访问 / 修改 / 删除流程"(实际全本地, 用户自己卸 app + 清 sandbox container 即可)
7. **更新日期** — `Last updated: 2026-06-XX`

#### 5.3 启 GitHub Pages

| 步骤 | 落点 | 改动 |
|---|---|---|
| 5.3.a | GitHub 仓库 → Settings → Pages → Source | `Deploy from a branch` → Branch `main` / Folder `/docs` |
| 5.3.b | 等 GitHub 部署(2-5min) | — |
| 5.3.c | 验证 URL | `curl -I https://sunhuaian2026.github.io/Glance/privacy.html` → `HTTP/2 200` |

**注意**: 仓库当前 visibility = public(v1.0 ship 时切的, project memory 已记)。Pages 默认对公开仓库免费。

#### 5.4 验证
- 6 段法律必须内容齐
- URL 200 不死链
- 中英两语都有(App Review 可能用英文测试)

### 回滚
- Pages 部署失败 → 重设 Source / 等 5min / 检查 `docs/privacy.html` 文件名
- URL 404 → 等部署完成 / 重看 Settings → Pages 状态

---

## 任务 6 — 截图准备(7 张, App Store build 抓 + Figma 标语包装)

### 验证锚点
- `ls assets/appstore-screenshots/` 出 7 个 `.png` 文件(`01-XX.png` 到 `07-XX.png`)
- `sips -g pixelHeight -g pixelWidth assets/appstore-screenshots/01-*.png` 每张 2880×1800 或 2560×1600(Retina 标准)
- 任务 3.4 上传到 ASC 全过

### 截图状态(reality check 发现)
- `assets/screenshots/` 现有 **3 张**(`05-dedup.png` / `06-focus-review.png` / `07-search.png` — v2.3 新增 3 张)
- README 引用 7 张(01-grid / 02-preview / 03-quickviewer / 04-inspector / 05-dedup / 06-focus-review / 07-search), **但 01-04 物理文件不在磁盘**(README 链接已死), 需要重截
- App Store 截图必须用 **App Store build 抓**(任务 4 产出的 `.pkg` 解包安装版, codex round 1 P2(截图真实性约束)), 因此**全 7 张都要重截**, 不只是缺的 01-04

### 步骤

#### 6.1 装 App Store build 用于截图

| 步骤 | 命令 | 期望 |
|---|---|---|
| 6.1.a | 任务 4 跑完, 有 `dist/export-appstore/Glance.pkg` | — |
| 6.1.b | 双击 `.pkg` 装到本机 `/Applications/Glance.app`(覆盖任何旧 build) | macOS 安装器跑完, Applications 出现 Glance |
| 6.1.c | 启动 Glance, 验证关于面板版本 = `2.3.0 (<commit>.<stamp>)` | 跟 Marketing 一致 |
| 6.1.d | 装测试图库到 `~/Pictures/glance-test/`(20-50 张, 含 2-3 组重复, 几张 EXIF 完整) | 截图素材就位 |

#### 6.2 重截 7 张原始截图(无 Figma 标语)

| 编号 | 内容 | UI 操作 |
|---|---|---|
| 01-grid.png | V1 侧边栏树形 + 缩略图网格 | 加 1 个根文件夹, 等索引完, 侧边栏展开, 缩略图网格显示 16-24 张图 |
| 02-preview.png | 内嵌预览(单击) | 单击缩略图网格一张图, 等预览渲染, 截图含侧边栏 + 内嵌预览 + 缩略图网格 3 区 |
| 03-quickviewer.png | 快速看图器(双击) | 双击进 `QuickViewer`, 等全屏渲染 + filmstrip 出, 截图全窗口 |
| 04-inspector.png | EXIF Inspector | `QuickViewer` 内 ⌘I 出 Inspector 侧栏, 选含 EXIF 完整的图 |
| 05-dedup.png | 重复清理总览 | 侧边栏点「重复清理」, 等 reload, 显示组数 + 可省空间 |
| 06-focus-review.png | 逐组审阅浮层 | 重复清理总览点「逐组审阅 ›」, 浮层出, 2 列大图 |
| 07-search.png | 全局搜索 ⌘F + chips 筛选 | ⌘F 出 search overlay, 输入"png" + 点类型 chip, 显示筛选结果 |

**截图工具**: macOS `Cmd+Shift+5` 截窗口(去掉投影: 按住 Option 拖); 保存原始 PNG 到 `assets/appstore-screenshots-raw/01-07.png`

#### 6.3 Figma 标语包装

| 编号 | hero 标语 | 优先级理由 |
|---|---|---|
| 01-dedup-hero.png | 重复清理 + "跨文件夹找重复 · 省 GB 级硬盘" | 转化率最关键, 主打卖点 |
| 02-focus-review.png | 逐组审阅浮层 + "逐组眼审 · 撤销随时可用" | 重复清理的安全感配套 |
| 03-search.png | 全局搜索 + "⌘F 全库搜 · 类型/大小/时间筛选" | 强生产力 |
| 04-quickviewer.png | `QuickViewer` + "沉浸看图 · 零打扰" | 看图体验 |
| 05-grid.png | 缩略图网格 + "本地零网络 · 你的图你的库" | 隐私 / 不抢库 哲学 |
| 06-inspector.png | EXIF + "完整 EXIF / 元数据 / 副本去向" | (备用, 可选) |
| 07-preview.png | 内嵌预览 + "原生 SwiftUI · 跟随系统外观" | (备用, 可选) |

每张顶部加 64-80px hero 标语区, 蓝紫色调跟 app 一致(取 `DesignSystem.swift` DS.Color.accent 蓝紫值)。Figma 模板可 1h 内拼完。

输出 7 张 **2880×1800** PNG(Retina 主流, App Store 推荐), 存 `assets/appstore-screenshots/01-07.png`。

#### 6.4 验证

| 步骤 | 命令 | 期望 |
|---|---|---|
| 6.4.a | `ls -1 assets/appstore-screenshots/` | 7 个文件 `01-*.png` 到 `07-*.png` |
| 6.4.b | `for f in assets/appstore-screenshots/*.png; do sips -g pixelHeight -g pixelWidth "$f"; done` | 每张 1800×2880 或 1600×2560(高×宽) |
| 6.4.c | 视觉自查 | 标语清晰 / 颜色跟 app 一致 / 无 trademark 侵权 / 无 broken UI |

### 回滚
- 截图 UI 残缺 → 重截
- App Store build 装不上 → 重跑任务 4 / 检查 .pkg pkgutil 签名

---

## 任务 7 — TestFlight 内测预 step + altool 上传 + 准备审核备注 + 提交审核

### 验证锚点
- TestFlight 收到 build 并装到至少 1 台 Mac 验证(可选但推荐)
- App Store Connect → My Apps → Glance → macOS → v2.3.0 → 选了任务 4 上传的 Build
- App Review 状态 `Waiting for Review` → `In Review` → `Pending Developer Release`

### 步骤

#### 7.1 上传 .pkg

| 步骤 | 命令 | 期望 |
|---|---|---|
| 7.1.a | 任务 4 跑完, `dist/export-appstore/Glance.pkg` 就位 | — |
| 7.1.b | `xcrun altool --upload-app --type macos --file dist/export-appstore/Glance.pkg --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>` | "No errors uploading" 退出 0 |
| 7.1.c | 等 ASC 处理 build(5-30min); 验证 `xcrun altool --list-apps --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>` 或 ASC 后台看 Build 列表 | Build 出现 |

**备选**(codex round 2 P2(altool 仍稳但建议 Transporter/JWT 现代首选)): 现代首选优先级 Transporter CLI 或 ASC API JWT 自动化 > altool。若 altool flag 漂移失败, 换 `Transporter.app` GUI(同 API Key/JWT 路径, UI 差异)。

#### 7.2 TestFlight 内测预 step(可选但推荐, codex round 1 P2(TestFlight 预留))

| 步骤 | 落点 | 改动 |
|---|---|---|
| 7.2.a | ASC → Glance → TestFlight → External Testing(or Internal) | 创建测试组 |
| 7.2.b | 添加 1-2 个测试人(自己 + 朋友 Apple ID) | — |
| 7.2.c | 把任务 7.1 上传的 Build 推给测试组 | TestFlight app 装到测试 Mac |
| 7.2.d | 装并验证: 首启行为 / 沙盒 / 加文件夹 / 重复清理 / 快速看图器 / 关于面板版本 | 全 OK 才进 7.3 提交审核 |
| 7.2.e | 发现问题 → fix → 重 archive → 重传 → 重测(每 cycle 1-2 天) | — |

**优势**: 拦截签名/manifest/沙盒错误, 比正式 review 拒了再 fix 快。

#### 7.3 准备审核备注文案(codex round 1 P1(审核员空态可复现性)必加)

App Store Connect → Version → "App Review Information" 段填:

| 字段 | 内容 |
|---|---|
| **Sign-in Required** | No(无登录) |
| **App Review Notes**(中英双语) | 见下 |

**App Review Notes 中英双语内容**:

```
[中文]
Glance 是 macOS 本地图片浏览 + 重复清理工具, 零网络零数据收集。

首次启动空态:
- App 启动后侧边栏左上有 + 按钮, 点击通过 NSOpenPanel 添加文件夹根目录
- 添加根目录后, 系统会启动后台索引(SQLite + 缩略图 + SHA256)
- 索引完成后可在「全部最近」「重复清理」等智能文件夹中浏览

测试图库建议:
- 准备 20-30 张图片(.jpg/.png), 含 2-3 组重复(同一张图复制到不同文件夹), 用于测试「重复清理」功能
- 单击缩略图进入内嵌预览, 双击进入快速看图器(全屏看图)
- ⌘F 触发全局搜索, ⌘I 在快速看图器内查看 EXIF

隐私承诺:
- 零网络请求(Activity Monitor 可验证)
- 零数据上传(所有索引/缩略图/SHA256/Vision feature print 全部存
  ~/Library/Containers/com.sunhongjun.glance/)
- 重复清理走 macOS 系统废纸篓, 不直接删文件

[English]
Glance is a macOS local image browsing + duplicate cleanup tool. Zero network
requests, zero data collection.

First launch:
- Empty state after launch. Click "+" button on top-left of sidebar to add
  folder root via NSOpenPanel
- Background indexing starts after folder added (SQLite + thumbnails + SHA256)
- After indexing, browse via "All Recent", "Duplicate Cleanup" smart folders

Test library setup:
- Prepare 20-30 images (.jpg/.png), with 2-3 duplicate groups (same image
  copied to different folders) for testing "Duplicate Cleanup"
- Single-click thumbnail = inline preview; double-click = QuickViewer (full
  immersive view)
- ⌘F triggers global search; ⌘I in QuickViewer shows EXIF metadata

Privacy:
- Zero network requests (verifiable via Activity Monitor)
- Zero data upload (all indexes/thumbnails/SHA256/Vision feature prints stored
  in ~/Library/Containers/com.sunhongjun.glance/ locally)
- Duplicate cleanup uses macOS trash via FileManager.trashItem, no direct unlink
```

#### 7.4 关联 Build 到 v2.3.0 + 填 Version 元数据 + 提交审核

| 步骤 | 落点 | 改动 |
|---|---|---|
| 7.4.a | ASC → Glance → macOS → "+ Version or Platform" → v2.3.0 | 创建 Version |
| 7.4.b | "Build" 段 → Select → 选 7.1 上传 + ASC 处理完的 build | — |
| 7.4.c | "What's New in This Version" — 用 v2.3 release notes 内容(GitHub Release notes 复用), 中英双语 | — |
| 7.4.d | "App Review Information" 段填 7.3 写的中英双语备注 | — |
| 7.4.e | "Version Release" 段选 **Manually release this version**(D5.4 配合小红书发推时机) | — |
| 7.4.f | "Save" → "Submit for Review" | 状态翻 Waiting for Review |

#### 7.5 等审核

| 阶段 | 预期 |
|---|---|
| Waiting for Review | 几小时 → 几天(随 Apple 队列) |
| In Review | 通常 1-2 天 |
| Pending Developer Release(通过) / Rejected(拒) | — |

**拒因处理**(codex round 1 P1(时间预估改 2-3 周) + codex round 2 P1(审核时间措辞校正)):
- 正常 1-2 天通过; 被拒后**重新计时, 不累计**
- 首次通过概率 60-70%, 1-2 次拒因 cycle 正常, 总 2-3 周日历
- 拒因 → 看 ASC Resolution Center → 改 metadata / 加 entitlement 说明 / 重 build / 重提

#### 7.6 通过后**不要**立刻 release

D5.4: 手动 release, 等任务 8 双轨上架 + 小红书发推时机协调好再点。

### 回滚
- altool 上传失败 → 改用 Transporter.app GUI
- TestFlight 内测发现 bug → 修 → 重 archive → 重传
- 首次审核拒 → 看 Resolution Center → 改 → 重提

---

## 任务 8 — 双轨上架后 + D5.6 双装兜底(降级 dialog 落代码) + README badge

### 验证锚点
- README 顶部出现 App Store badge + GitHub Release badge 双入口
- `Glance/IndexStore/IndexStoreSchema.swift` 含 schema-version-too-high error dialog 路径
- 旧版 binary 打开新 schema DB 时弹明确 error, 不允许 silent data corruption
- `specs/PENDING-USER-ACTIONS.md` 加 App Store 跟踪人工项

### 步骤

#### 8.1 README badge + 双入口

| 步骤 | 文件 | 改动 |
|---|---|---|
| 8.1.a | `README.md` 顶部下载段 | 加 Mac App Store badge(Apple 官方 marketing badge): `[<img src="https://developer.apple.com/assets/elements/badges/download-on-the-mac-app-store.svg" alt="Download on the Mac App Store" height="50">](https://apps.apple.com/cn/app/id<APP_ID>)` + 紧跟现有 GitHub Release 链接 |
| 8.1.b | `<APP_ID>` 替换为任务 3.1 创建的 ASC App ID(数字) | — |
| 8.1.c | 加"已装 GitHub 版?"子段(50-100 字): 解释**同 Bundle ID 共享 sandbox container**, 切到 App Store 版**无缝继承所有 root + 索引数据**, **建议二选一不同装**(避免 schema 冲突) | — |

#### 8.2 D5.6 降级路径代码兜底(codex round 2 P1(降级路径(App Store → GitHub)未明确)必加 + codex plan review P1(schema-alert-wrong-hook)修正)

设计 design Section 8.4 明示"旧版 binary 打开新 schema DB 必须弹 error dialog 不允许 silent corruption"。Reality check: `IndexStoreSchema.swift` 现 `currentVersion = 2`, `migrate(_:currentDbVersion:)` 只处理 `currentDbVersion < 2` 的 forward migration, 没处理 `currentDbVersion > currentVersion` 的"DB 版本超前于 binary 预期"情况。

**codex plan review P1(schema-alert-wrong-hook) 关键修正**: 原 plan 把 alert 监听落到 `wireIfReady` 是错的 — Reality check `IndexStoreHolder.bootstrap()` (`IndexStoreHolder.swift:46-55`) 若 `try IndexStore()` throws, 只 set `initError: String?`, **`isReady` 永不 set true**, `store` 永远 nil, ContentView `.onChange(of: holder.isReady)` 永不 fire → alert **永远弹不出**。**修正**: 给 IndexStoreHolder 增独立 `@Published var fatalSchemaError: SchemaTooNewError?` 字段, `bootstrap()` catch `SchemaTooNewError` 时 set 它, ContentView 用 `.alert(item: $holder.fatalSchemaError)` 监听**独立于 isReady**, 弹出 + 退出 NSApp.terminate。

| 步骤 | 文件 | 改动 |
|---|---|---|
| 8.2.a | `Glance/IndexStore/IndexStoreSchema.swift` | `migrate` 方法开头加 guard: 若 `currentDbVersion > currentVersion` 抛 typed error `SchemaTooNewError(dbVersion: currentDbVersion, expected: currentVersion)`; struct 定义放同文件, conform `Error` + `Identifiable`(为 `.alert(item:)` 用, `id = dbVersion`) |
| 8.2.b | `Glance/IndexStore/IndexStoreHolder.swift` | 加 `@Published var fatalSchemaError: SchemaTooNewError?`; `bootstrap()` 的 catch 段 do-catch `SchemaTooNewError` → set 该字段(**不**走 `initError`, initError 保留给其它 IndexStore init 错误如磁盘满 / 路径权限不足) |
| 8.2.c | `Glance/ContentView.swift` 主 view 末尾 | 加 `.alert(item: $indexStoreHolder.fatalSchemaError) { err in Alert(title: Text("数据库版本不兼容"), message: Text(messageFor(err)), dismissButton: .default(Text("退出 App"), action: { NSApp.terminate(nil) })) }` |
| 8.2.d | 同 ContentView, 加 helper `func messageFor(_ err: SchemaTooNewError) -> String` | 返回: "当前 App 期望 schema v\(err.expected), 但磁盘 DB 是 v\(err.dbVersion)。这通常发生在你装过更新版本的 Glance(如 App Store 版)之后回退到旧版本。\n\n请重装 App Store 版本(数据无损), 或清空 ~/Library/Containers/com.sunhongjun.glance/Application Support/ 重建数据库(会丢失索引但不影响磁盘原始图片)。" |
| 8.2.e | 单元 / 真机验证 | 临时把 `IndexStoreSchema.currentVersion = 2` 改 `currentVersion = 1` build, 让 binary 装到一台已经跑过 v2.3.0 的 Mac, 启动 → bootstrap throws SchemaTooNewError → fatalSchemaError set → ContentView alert 弹 → 点退出 → NSApp.terminate |
| 8.2.f | reality check 关键 callsite 不漏(codex plan review P2(OK-schema-guard) + P2(OK-no-extra-migrate-callsites)验过) | `IndexStoreSchema.migrate()` 全项目唯一直接调用点在 `IndexStore.swift:29` (`IndexStore.init`), `FolderStoreIndexBridge`/`FolderStore` 不直接调 migrate, 仅在 store ready 后用 IndexStore. 8.2.a 在 migrate 开头加 guard 完全覆盖, 无 init path 漏 |

**测试纪律**: 8.2.e 改 currentVersion 改回原值前**不可 commit**, 仅本地验证, 避免误推。

#### 8.3 PENDING 队列追加

| 步骤 | 文件 | 改动 |
|---|---|---|
| 8.3.a | `specs/PENDING-USER-ACTIONS.md` Pending 段 | 加 App Store 跟踪项(用户每条独立列): 1) 装 App Store 版 vs GitHub 版数据无缝继承真机验; 2) App Store 自动更新行为真机验(等 v2.4 时); 3) 评分 / 评论运营每周一查; 4) 拒因复盘归档(若被拒, fix 流程归档); 5) D5.6 降级 dialog 真机走查(临时改 currentVersion 模拟); 6) App Store 描述跟实际 UI 一致性核(避免 metadata mismatch 用户投诉) |

#### 8.4 验证

| 步骤 | 命令 | 期望 |
|---|---|---|
| 8.4.a | `grep "Mac App Store" README.md` | 1+ 行 |
| 8.4.b | `grep "SchemaTooNewError\|schema v" Glance/IndexStore/IndexStoreSchema.swift Glance/IndexStore/IndexStore.swift` | 见 typed error + guard |
| 8.4.c | 真机模拟 8.2.e | alert 弹 + 点退出 |
| 8.4.d | `grep "App Store" specs/PENDING-USER-ACTIONS.md` | 6 项追加确认 |

### 回滚
- README badge 链 404 → 等 App Store release 后再上 PR(Marketing URL 任务 7 release 后才稳)
- 降级 dialog 实现复杂 → 简化版: 直接 `fatalError("Schema too new")` 也行, 但 fatalError crash 比 alert 用户体验差, 建议走 alert

---

## 任务 9 — Roadmap + CONTEXT 同步 + verify.sh 通过

### 验证锚点
- `./scripts/verify.sh` Stage 1(静态规则) + Stage 2(编译) 通过
- `specs/Roadmap.md` "关键架构决策"段加 App Store 决策, **合并入主 D 序号**(下一空闲编号开始, 如 D41+, 跟 9.2.b 推荐一致 — App Store 上架是一次性子系统不像 OpenWith/`QuickViewer` 跨多里程碑, 不开独立命名空间; codex plan review P2(decision-namespace-conflict) 修)
- `CONTEXT.md` "独立子系统"表加"Mac App Store 上架"行

### 步骤

#### 9.1 Roadmap 更新

| 步骤 | 文件 | 改动 |
|---|---|---|
| 9.1.a | `specs/Roadmap.md` 已完成段或独立子系统段 | 加"Mac App Store 上架"行, commit hash + submission ID + 上架日期 |
| 9.1.b | `specs/Roadmap.md` 关键架构决策段 | 折入 D5.1-D5.7 的拍板理由(已在 design 文档, 此处摘要 5-10 行); 风格 mirror D-OW / D-`QuickViewer` |
| 9.1.c | `specs/Roadmap.md` Bug Fix 段 | 若任务 7 cycle 有拒因 → 修 → 重提, 各 cycle commit hash 写明 |

#### 9.2 CONTEXT.md 更新

| 步骤 | 文件 | 改动 |
|---|---|---|
| 9.2.a | `CONTEXT.md` D.3 独立子系统表 | 加一行: `\| Mac App Store 上架 \| 双轨分发路径(跟 GitHub Release 并存), 首发 v2.3.0 \| ✅ \|` |
| 9.2.b | `CONTEXT.md` D.4 决策 ID 命名空间表 | **不开 D-AS 独立空间**(已 codex P2(decision-namespace-conflict) 修, 跟任务 9 验证锚点一致); 仅在 D.3 独立子系统表加"Mac App Store 上架"行, 命名空间一栏写"合并入主 D"。理由: App Store 上架是一次性子系统不像 OpenWith / `QuickViewer` 跨多里程碑, 不需独立命名空间 |
| 9.2.c | `CONTEXT.md` 术语表 | 加"App Store 上架" / "Apple Distribution(证书)" / "Privacy Manifest" / "Privacy Nutrition Labels" 4 项术语登记 |

#### 9.3 PENDING 已整(任务 8.3 已加)

#### 9.4 verify.sh

| 步骤 | 命令 | 期望 |
|---|---|---|
| 9.4.a | `./scripts/verify.sh` | Stage 1+2 全过(单测 stage 3 skip 正常); 字典 enforcement 不报红(本 plan + 所有文档全用「任务」, 禁用词 `Slice`/`VS` 一律 inline backtick 包起来) |

#### 9.5 commit + push

| 步骤 | 命令 | 备注 |
|---|---|---|
| 9.5.a | `git add ...` 逐文件明确 | 不用 `git add -A` |
| 9.5.b | `git commit -m "feat(App Store): v2.3.0 上架完成 (任务 1-9 全过, Submission ID <X>)"` 或分多 commit | 跟 CLAUDE.md commit message 规范一致 |
| 9.5.c | `git push` | pre-push hook(秘密扫描)过 |

---

## 5. 风险点与回滚总结

| 阶段 | 出问题 | 兜底 |
|---|---|---|
| 任务 1 证书 | 装不上 keychain | mirror v1.0 流程; revoke + 重申 |
| 任务 1.4 API Key | Key 失效 | 后台重生 Key + 重装 `.p8` |
| 任务 2.1 pbxproj | 改坏 | `.bak` 还原; GUI Xcode Add Configuration 救场 |
| 任务 2.4 Privacy Manifest | reason code 错 | Xcode build warn / ASC 校验拒 → fix 重 archive |
| 任务 4 build .pkg | exportArchive 失败 | 校 profile name + signing identity match |
| 任务 4 quarantine xattr | 上传被 Apple 拒(2025-02-18 起) | release-appstore.sh Step 0 pre-archive 清 + Step 3 post-export 验证 |
| 任务 5 GitHub Pages | URL 404 | 等部署 5min / 重设 Source |
| 任务 7 altool | flag 漂移失败 | 换 Transporter.app GUI |
| 任务 7 TestFlight | 内测发现 bug | 修 → 重 archive → 重传 |
| 任务 7 审核拒 | 1-2 次 cycle 正常 | 改 metadata / entitlement 说明 / 重提 |
| 任务 8 双装冲突 | 用户同装 GitHub + AS | README + ASC 描述强烈建议二选一; D5.6 降级 dialog 兜底(任务 8.2) |

---

## 6. 时间线建议(2-3 周日历)

| 第几天 | 工作 | 阻塞 |
|---|---|---|
| Day 1 | 任务 1 证书 + ASC API Key + 任务 5 GitHub Pages | 等 Apple 颁发证书(几分钟) |
| Day 2-3 | 任务 2 pbxproj + Privacy Manifest + entitlements + 任务 4 release-appstore.sh | CC 跑 |
| Day 4-5 | 任务 3 ASC 元数据 + Nutrition Labels + 任务 6 截图 | 军哥本机做 |
| Day 6 | 任务 7.2 TestFlight 内测 + 任务 7.1 正式上传 + 任务 7.3 审核备注 | CC + 军哥 |
| Day 7 | 任务 7.4 提交审核 | 等 Apple |
| Day 8-10 | 等 Apple 首次审核 | Apple 审核中 |
| Day 10-12 | 第一次拒因 → 改 → 重提(预期 60-70% 概率走这步) | 军哥 + CC |
| Day 13-15 | 第二次审核, 期望通过 | 等 Apple |
| Day 15+ | 任务 8 + 9 上架后宣传 + 文档同步 | 军哥小红书 |

---

## 7. 不修改范围

- 现 `scripts/release.sh` / `make release` GitHub Release 流程**完全不动**
- v2.3 GitHub Release(已发, https://github.com/sunhuaian2026/Glance/releases/tag/v2.3)**完全不动**
- `Glance.app` 内代码**不改新 feature**(D5.6 降级 dialog 是兜底必加, 不算新 feature 算缺陷修复)
- App 内 UI / feature **不变化**(不为 App Store 加特殊 UI)
- 现 `Glance.entitlements` **不动**(新增 `Glance-AppStore.entitlements` 分轨)
- **Bundle ID `com.sunhongjun.glance` 不变**

---

## 8. Self-Review 清单(plan 写完后 CC 自己跑)

- [ ] **Design 覆盖**: design v3 9 大任务全有对应 plan 任务? (是, 1-9 顺次对应)
- [ ] **Code reality check 字段/签名级**:
  - [ ] `Glance.entitlements` 3 键(app-sandbox / files.user-selected.read-write / files.bookmarks.app-scope) — 验过, 任务 2.2 引用准确
  - [ ] `release.sh` MARKETING_VERSION="2.3.0" / NOTARY_PROFILE / Hardened Runtime / Developer ID 流程 — 验过, 任务 4 mirror 准确
  - [ ] `ExportOptions.plist` 4 字段 — 验过, 任务 4.1 新 plist 字段命名一致(`method`/`teamID`/`signingStyle`/`signingCertificate`)
  - [ ] `Makefile` `.PHONY` 行 / `release` target 风格 — 验过, 任务 4.3 加 target mirror 一致
  - [ ] `Info.plist` `CFBundleDocumentTypes` LSHandlerRank=Alternate — 验过, 不抢默认看图器, App Store 接受
  - [ ] `IndexStoreSchema.swift` `currentVersion = 2` + `migrate(_:currentDbVersion:)` — 验过, 任务 8.2 改动锚点准确
  - [ ] UserDefaults 用法 — BookmarkManager / FolderStore / AppState 全 grep 过, 任务 2.4 Privacy Manifest 引用准确
  - [ ] URLResourceValues 用法 — FolderStore / ImageInspectorViewModel 全 grep 过, 任务 2.4 FileTimestamp 引用准确
  - [ ] CryptoKit SHA256 — ContentHasher.swift line 21 验过, 任务 2.4.e 排除项引用准确
  - [ ] assets/screenshots/ 实际只有 3 张 — 验过, 任务 6 明示需重截全 7 张
- [ ] **任务粒度纪律自检**(CLAUDE.md 「`切片纪律`(硬约束)」, 每任务问"独立完成时可验证什么?"):
  - 任务 1 完成 → keychain 装好 + altool list-providers 出 team ✓ 端到端可验
  - 任务 2 完成 → xcodebuild -showBuildSettings 出新配置 + Xcode build Release-AppStore 0 error ✓ 端到端可验
  - 任务 3 完成 → ASC 后台 4 块绿 + 状态 Ready to Submit ✓ 端到端可验
  - 任务 4 完成 → `make release-appstore` 跑通出 .pkg + pkgutil 签名通过 ✓ 端到端可验
  - 任务 5 完成 → curl HTTP 200 + 浏览器渲染 ✓ 端到端可验
  - 任务 6 完成 → 7 张 PNG 齐 + sips 验尺寸 ✓ 端到端可验
  - 任务 7 完成 → ASC 状态翻 In Review → Pending Developer Release ✓ 端到端可验(Apple 异步)
  - 任务 8 完成 → README + IndexStoreSchema diff + 真机模拟降级 alert 弹 ✓ 端到端可验
  - 任务 9 完成 → verify.sh 全过 + commit pushed ✓ 端到端可验
- [ ] **术语字典合规**:
  - [ ] 全文 grep `Slice`/`slice`/`vertical slice`/`VS`/`切片`/`片`/``QuickViewer``/`SF`(独立词) — 0 命中(本 plan 用「任务」「快速看图器」「智能文件夹」, 禁用词列表全包 backtick 豁免 enforcement)
  - [ ] codex 引用 — 全部带含义("codex round 2 P0-5 UserDefaults required-reason 漏报"等), 无裸编号
- [ ] **Placeholder 扫描**:
  - [ ] 无 "TBD" / "TODO" / "implement later" / "add appropriate X"
  - [ ] `<App Store Glance Profile>` / `<KEY_ID>` / `<ISSUER_ID>` / `<APP_ID>` 是 placeholder, **但**实施时由任务 1 + 3 真实创建产出再回填, 不是设计 placeholder
- [ ] **Sequential 不可避免段**:
  - [ ] 任务 1 → 任务 4(证书必须先有), 任务 4 → 任务 6.1(`.pkg` 装到本机才能截图), 任务 7 → 任务 8(审核通过才上 README badge) — 阻塞关系明确不绕

---

## 9. Plan 跟 design 的差异点(implementer 注意)

| design 段 | plan 落点 | 差异/补充 |
|---|---|---|
| design Section 2 Scope | 本 plan 0. 全局约束 | 等价 |
| design Section 4 任务 1-9 | 本 plan 任务 1-9 | 任务名一致, 每任务展开为多步骤表格 + 验证锚点 |
| design Section 4 任务 6 "复用 7 张" | 本 plan 任务 6 reality check | **plan 修正: 实际只有 3 张, 需重截 7 张** |
| design Section 4 任务 8.4 降级 dialog | 本 plan 任务 8.2 | **plan 落代码到 IndexStoreSchema.swift 具体改动**, design 只说"加 error dialog" |
| design Section 6 时间预估 | 本 plan Section 6 | 完全一致 |
| design Section 11 codex review 折入对照 | 本 plan 各任务步骤注明 codex round 1/2 编号 | 等价 |

---

## 10. 完成判定

全 9 大任务完成 + App Store v2.3.0 状态翻 `Ready for Sale`(Apple 通过 + 手动 release) = 本 plan 完成。
