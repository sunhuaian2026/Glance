#!/bin/bash
# release.sh — Glance 公开分发打包流程
#
# 流程：xcodebuild archive (Release + Hardened Runtime + Developer ID signed)
#   → exportArchive → create-dmg → notarytool submit → stapler staple
#   → dist/Glance-<MARKETING_VERSION>.dmg + SHA256
#
# Usage: ./scripts/release.sh
#
# 环境变量：
#   SKIP_NOTARIZE=1     跳过公证（仅签名 + DMG，本地干跑验证用）
#   NOTARY_PROFILE      notarytool keychain profile name（默认 "glance-notary"）
#
# 一次性配置 notarytool（首次跑前必须做）：
#   xcrun notarytool store-credentials "glance-notary" \
#     --apple-id <your-apple-id> --team-id 8KW8Z92GRA \
#     --password <App-specific password>

set -euo pipefail

# ============== 配置 ==============
PROJECT="Glance.xcodeproj"
SCHEME="Glance"
TEAM_ID="8KW8Z92GRA"
BUNDLE_ID="com.sunhongjun.glance"
SIGN_IDENTITY="Developer ID Application"
NOTARY_PROFILE="${NOTARY_PROFILE:-glance-notary}"

# 用户可见版本（marketing），跟 pbxproj MARKETING_VERSION 保持一致
MARKETING_VERSION="2.3.0"

# 内部 build version（给开发者看，跟 commit 关联），注入到 CFBundleVersion
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
DIRTY=""
if ! git diff --quiet HEAD -- Glance/ Makefile scripts/ 2>/dev/null; then
    DIRTY="-d"
fi
STAMP=$(date +%m%d-%H%M)
BUILD_VERSION="${COMMIT}${DIRTY}.${STAMP}"

# Copyright（关于面板单行紧凑展示）
COPYRIGHT="© 2026 孙红军 · 16414766@qq.com · 小红书 382336617"

# 路径
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
ARCHIVE_PATH="${DIST_DIR}/Glance.xcarchive"
EXPORT_PATH="${DIST_DIR}/export"
APP_PATH="${EXPORT_PATH}/Glance.app"
DMG_NAME="Glance-${MARKETING_VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
EXPORT_OPTIONS="${ROOT_DIR}/scripts/ExportOptions.plist"

cd "${ROOT_DIR}"

# ============== Pre-flight checks ==============
echo "==> Pre-flight checks"

# (1) Developer ID Application identity
if ! security find-identity -v -p codesigning | grep -q "${SIGN_IDENTITY}: Hongjun Sun (${TEAM_ID})"; then
    echo "❌ Developer ID Application identity 没装到 login keychain"
    echo "   期望: \"${SIGN_IDENTITY}: Hongjun Sun (${TEAM_ID})\""
    echo "   去 Apple Developer 创建/下载 .cer + 私钥（.p12）装到登录 keychain"
    exit 1
fi
echo "  ✓ codesigning identity OK"

# (2) notarytool credentials
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
    if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" &>/dev/null; then
        echo "❌ notarytool keychain profile '${NOTARY_PROFILE}' 没配置或无效"
        echo ""
        echo "   先跑（一次性配置，App-specific password 在 https://appleid.apple.com 生成）："
        echo "     xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\"
        echo "       --apple-id <your-apple-id> \\"
        echo "       --team-id ${TEAM_ID} \\"
        echo "       --password <App-specific password>"
        echo ""
        echo "   或先跑 SKIP_NOTARIZE=1 ./scripts/release.sh 验证签名 + DMG 流程"
        exit 1
    fi
    echo "  ✓ notarytool profile '${NOTARY_PROFILE}' OK"
else
    echo "  ⚠ SKIP_NOTARIZE=1, 跳过公证（仅签名 + DMG）"
fi

# (3) create-dmg
if ! command -v create-dmg &>/dev/null; then
    echo "❌ create-dmg 未安装。先跑：brew install create-dmg"
    exit 1
fi
echo "  ✓ create-dmg OK"

# ============== Clean ==============
echo ""
echo "==> Clean previous artifacts"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}" "${DMG_PATH}"
mkdir -p "${DIST_DIR}"

# ============== Step 1: Archive ==============
echo ""
echo "==> Step 1/6: xcodebuild archive (Release + Hardened Runtime)"
echo "    Marketing: ${MARKETING_VERSION} | Build: ${BUILD_VERSION}"

xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
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

# ============== Step 2: Export Archive ==============
echo ""
echo "==> Step 2/6: exportArchive (Developer ID signed .app)"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -quiet

if [[ ! -d "${APP_PATH}" ]]; then
    echo "❌ 导出的 .app 不存在: ${APP_PATH}"
    exit 1
fi
echo "  ✓ App: ${APP_PATH}"

# 校验签名
echo ""
echo "==> Verifying codesign"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | grep -E "valid on disk|satisfies its Designated Requirement" || true
codesign -dvvv "${APP_PATH}" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier|Hardened" | head -10

# ============== Step 3: Create DMG ==============
echo ""
echo "==> Step 3/6: create-dmg"
create-dmg \
    --volname "Glance ${MARKETING_VERSION}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Glance.app" 175 190 \
    --hide-extension "Glance.app" \
    --app-drop-link 425 190 \
    --no-internet-enable \
    "${DMG_PATH}" \
    "${APP_PATH}"

if [[ ! -f "${DMG_PATH}" ]]; then
    echo "❌ DMG 不存在: ${DMG_PATH}"
    exit 1
fi
echo "  ✓ DMG: ${DMG_PATH}"

# ============== Step 4 + 5 + 6: Notarize / Staple / Verify ==============
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
    echo ""
    echo "==> Step 4/6: notarytool submit (公证，5-15 分钟)"
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait \
        --timeout 30m

    echo ""
    echo "==> Step 5/6: stapler staple (.app standalone + DMG)"
    # .app 单独 staple — 解决 v1.0.0 ".app 单独 staple 在 v1.0.1 加" 分发债，.app 单独拖出 DMG 也能离线启动
    xcrun stapler staple "${APP_PATH}"
    xcrun stapler validate "${APP_PATH}"
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"

    echo ""
    echo "==> Step 6/6: spctl Gatekeeper assessment (.app + DMG)"
    spctl --assess --type execute --verbose "${APP_PATH}" 2>&1 || true
    spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}" 2>&1 || true
else
    echo ""
    echo "==> Skipped: notarize / staple / spctl (SKIP_NOTARIZE=1)"
fi

# ============== Summary ==============
# 写 .sha256 sidecar 文件供 GitHub Release upload（gh release create 会单独上传该文件）
shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"
SHA256=$(awk '{print $1}' "${DMG_PATH}.sha256")
DMG_SIZE=$(du -h "${DMG_PATH}" | awk '{print $1}')

echo ""
echo "================================================================"
echo "✅ Release build complete"
echo ""
echo "  DMG:           ${DMG_PATH}"
echo "  Size:          ${DMG_SIZE}"
echo "  Marketing:     ${MARKETING_VERSION}"
echo "  Build:         ${BUILD_VERSION}"
echo "  SHA256:        ${SHA256}"
echo ""
echo "  下一步：装到一台干净 Mac 双击直开测试，确认无 Gatekeeper 警告"
echo "================================================================"
