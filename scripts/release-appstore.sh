#!/bin/bash
# release-appstore.sh — Glance Mac App Store 上架打包流程
#
# 流程：xcodebuild archive (Release-AppStore + Apple Distribution signed)
#   → exportArchive → dist/export-appstore/Glance.pkg
#
# Usage: ./scripts/release-appstore.sh
#
# 凭据体系（任务 1 已部署到 keychain + ASC）：
#   - keychain identity: "Apple Distribution: Hongjun Sun (8KW8Z92GRA)"
#   - provisioning profile: 装到 ~/Library/MobileDevice/Provisioning Profiles/
#   - ExportOptions-AppStore.plist 占位 __APP_STORE_PROFILE_NAME_PLACEHOLDER__
#     必须由军哥任务 1.3 创建 profile 后回填真实 profile name
#
# 上传命令（任务 7 用，本脚本不直接上传）：
#   xcrun altool --upload-app --type macos \
#     --file dist/export-appstore/Glance.pkg \
#     --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
#
# 注意：跟 release.sh 完全独立，两次 archive 路径分开互不冲突

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

# 路径（跟 release.sh 完全独立，不互覆盖）
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
ARCHIVE_PATH="${DIST_DIR}/Glance-AppStore.xcarchive"
EXPORT_PATH="${DIST_DIR}/export-appstore"
PKG_PATH="${EXPORT_PATH}/Glance.pkg"
EXPORT_OPTIONS="${ROOT_DIR}/scripts/ExportOptions-AppStore.plist"

cd "${ROOT_DIR}"

# ============== Pre-flight checks ==============
echo "==> Pre-flight checks"

# (1) Apple Distribution identity
if ! security find-identity -v -p codesigning | grep -q "${SIGN_IDENTITY}: Hongjun Sun (${TEAM_ID})"; then
    echo "❌ Apple Distribution identity 没装到 login keychain"
    echo "   期望: \"${SIGN_IDENTITY}: Hongjun Sun (${TEAM_ID})\""
    echo "   去 Apple Developer 创建/下载 Apple Distribution .cer + 私钥(.p12)装到登录 keychain"
    exit 1
fi
echo "  ✓ Apple Distribution identity OK"

# (2) ExportOptions plist
if [[ ! -f "${EXPORT_OPTIONS}" ]]; then
    echo "❌ ExportOptions-AppStore.plist 不存在: ${EXPORT_OPTIONS}"
    exit 1
fi
echo "  ✓ ExportOptions-AppStore.plist OK"

# (3) Profile name 占位检查 — 提醒军哥任务 1 完成后回填
if grep -q "__APP_STORE_PROFILE_NAME_PLACEHOLDER__" "${EXPORT_OPTIONS}"; then
    echo "❌ ExportOptions-AppStore.plist 仍含 profile name 占位 __APP_STORE_PROFILE_NAME_PLACEHOLDER__"
    echo "   任务 1.3 创建 App Store provisioning profile 后, 回填占位为真实 profile name"
    echo "   (e.g. 'Glance App Store')"
    exit 1
fi
echo "  ✓ ExportOptions-AppStore.plist profile name 已回填"

# ============== Clean ==============
echo ""
echo "==> Clean previous AppStore artifacts"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"
mkdir -p "${DIST_DIR}"

# ============== Step 0: Pre-archive quarantine xattr 清理 ==============
# Apple 2025-02-18 起 TestFlight/App Store 提交不能带 com.apple.quarantine xattr
# (codex round 2 P0(quarantine xattr 上传门禁缺失))
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
echo "==> Step 2/4: exportArchive (Apple 推荐路径，自动签 .pkg)"
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

# ============== Step 3: Post-export quarantine xattr 验证 ==============
# (codex round 2 P0(quarantine xattr 上传门禁缺失) — post-export 二次验证不漏)
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
