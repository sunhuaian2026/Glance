#!/bin/bash
# scripts/verify.sh — 三段式 oracle (cheap → expensive, stop on red)
#
#   stage 1/3  静态规则查      毫秒     grep/awk + 文档同步 + git hygiene
#   stage 2/3  编译             30-60s   xcodebuild build -quiet (isolated derived data)
#   stage 3/3  单测             skipped  Glance 暂无 XCTest target
#
# flags:
#   --with-codex   追加 codex 全项目审查（慢且花钱，~2-5min, ~$0.1-0.3）
#
# logs:
#   完整日志留 .verify-logs/*.log（gitignored）— stderr 只喂前 N 行 actionable
#
# 设计原则：
#   - 按成本递增，红即停（前面挂了，后面更贵的没必要跑）
#   - -quiet + grep 过滤，只喂 CC actionable 那几十行
#   - Warning 非阻塞但打印（留观察口子；"不引入新 warning" 靠 CC 自查）
#   - DerivedData 与 make build 的 ./build 隔离，不互相污染

set -u

WITH_CODEX=0
for arg in "$@"; do
  case "$arg" in
    --with-codex) WITH_CODEX=1 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "unknown: $arg" >&2; exit 2 ;;
  esac
done

LOG_DIR=.verify-logs
BUILD_DIR=./build     # 必须与 Makefile 的 BUILD_DIR 一致：verify 编的 .app 就是 make run 打开的那个
mkdir -p "$LOG_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)

PASS=0; FAIL=0
pass() { printf '  [\xe2\x9c\x93] %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  [\xe2\x9c\x97] %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  [\xe2\x9c\x88] %s\n' "$1"; }
note() { printf '      %s\n' "$1"; }

die_if_red() {
  if [ "$FAIL" -gt 0 ]; then
    echo
    echo "━━ STOP: stage $1 red ($FAIL fail), later stages skipped ━━" >&2
    echo "━━ summary: $PASS passed, $FAIL failed ━━"
    exit 1
  fi
}

echo "=== verify.sh — 三段式 oracle (cheap → expensive, stop on red) ==="

# ═══════════════════════════════════════════════════════════════════
# Stage 1/3: 静态规则查（ms）
# ═══════════════════════════════════════════════════════════════════
echo
echo "── Stage 1/3: 静态规则查 ──"
SRC=$(find Glance -name '*.swift' 2>/dev/null)

# 1a. 代码规则 grep ───────────────────────────────
TB=$(grep -nE 'try!' $SRC 2>/dev/null || true)
[ -z "$TB" ] && pass "no try!" || { fail "try! found"; printf '%s\n' "$TB" | sed 's/^/      /'; }

AB=$(grep -nE '\bas![^=]' $SRC 2>/dev/null || true)
[ -z "$AB" ] && pass "no as!" || { fail "as! found"; printf '%s\n' "$AB" | sed 's/^/      /'; }

BT=$(grep -nE '//[[:space:]]*TODO:' $SRC 2>/dev/null \
     | grep -vE '//[[:space:]]*TODO:[[:space:]]*\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' || true)
if [ -z "$BT" ]; then
  pass "TODO format: all match // TODO: [YYYY-MM-DD]"
else
  fail "TODO format violations"; printf '%s\n' "$BT" | sed 's/^/      /'
fi

APPLE='^(SwiftUI|Foundation|AppKit|Combine|ImageIO|UniformTypeIdentifiers|CoreGraphics|CoreImage|CoreText|CoreFoundation|CoreServices|OSLog|Security|IOKit|QuartzCore|Metal|AVFoundation|AVKit|MapKit|PhotosUI|Photos|PDFKit|WebKit|StoreKit|LocalAuthentication|AuthenticationServices|Network|NetworkExtension|SystemConfiguration|UserNotifications|EventKit|Contacts|Intents|CoreLocation|CoreBluetooth|CoreMotion|CoreML|Vision|NaturalLanguage|Speech|Accelerate|simd|os|Darwin|Dispatch|XCTest|SQLite3|CryptoKit)$'
IMPS=$(grep -hE '^import ' $SRC 2>/dev/null | awk '{print $2}' | sort -u)
BAD_IMPS=$(printf '%s\n' "$IMPS" | grep -vE "$APPLE" | grep -v '^$' || true)
if [ -z "$BAD_IMPS" ]; then
  NUM=$(printf '%s\n' "$IMPS" | sed '/^$/d' | wc -l | tr -d ' ')
  pass "imports: Apple frameworks only ($NUM unique)"
else
  fail "non-Apple imports"; printf '%s\n' "$BAD_IMPS" | sed 's/^/      /'
fi

VIEWER_FILES=""
[ -d Glance/QuickViewer ] && VIEWER_FILES="$VIEWER_FILES $(ls Glance/QuickViewer/*.swift 2>/dev/null)"
[ -d Glance/ImageViewer ] && VIEWER_FILES="$VIEWER_FILES $(ls Glance/ImageViewer/*.swift 2>/dev/null)"
if [ -n "$(echo $VIEWER_FILES | tr -d ' ')" ]; then
  SP=$(grep -nE '\.spring\(' $VIEWER_FILES 2>/dev/null || true)
  if [ -z "$SP" ]; then
    pass ".spring: none in viewer-family files"
  else
    fail ".spring in viewer files (use DS.Anim.*)"; printf '%s\n' "$SP" | sed 's/^/      /'
  fi
fi

IPV=Glance/ImageViewer/ImagePreviewView.swift
if [ -f "$IPV" ]; then
  HC=$(grep -nE 'Color\.(white|black)\b|\.foregroundColor\(\.(white|black)\)|\.foregroundStyle\(\.(white|black)\)' "$IPV" 2>/dev/null || true)
  if [ -z "$HC" ]; then
    pass "ImagePreviewView: no hardcoded .white/.black"
  else
    fail "ImagePreviewView hardcoded .white/.black"; printf '%s\n' "$HC" | sed 's/^/      /'
  fi
fi

# 1b. 文档同步 ───────────────────────────────
RM=specs/Roadmap.md
if [ -f "$RM" ]; then
  MH=$(awk '
    /^## 已完成模块/ { i=1; next }
    /^## / && i { i=0 }
    i && /^\| / && !/^\| 模块/ && !/^\|---/ && !/^\|:---/ {
      n=split($0, a, "|"); if (n<5) next
      h=a[4]; gsub(/^ +| +$/, "", h)
      if (h=="" || h !~ /^[0-9a-f]{6,}$/) print NR": "a[2]"—hash=["h"]"
    }' "$RM")
  [ -z "$MH" ] && pass "Roadmap 已完成 rows have commit hashes" \
               || { fail "Roadmap rows missing hash"; printf '%s\n' "$MH" | sed 's/^/      /'; }

  MS=$(awk -F'|' '/^## 已完成模块/{i=1;next} /^## /&&i{i=0} i&&/^\|/&&!/^\| 模块/&&!/^\|---/&&!/^\|:---/{s=$3;gsub(/^ +| +$/,"",s); if(s~/\.md$/) print s}' "$RM" | sort -u)
  MISSING=""
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if [ ! -f "specs/$s" ] && [ ! -f "docs/archive/$s" ]; then
      MISSING="$MISSING$s\n"
    fi
  done <<< "$MS"
  [ -z "$MISSING" ] && pass "all Roadmap-referenced specs exist" \
                    || { fail "missing specs"; printf '%b' "$MISSING" | sed 's/^/      /'; }
else
  fail "$RM not found"
fi

# 1c. git hygiene ───────────────────────────────
HP=$(git config --get core.hooksPath 2>/dev/null || echo "")
[ "$HP" = ".githooks" ] && pass "core.hooksPath=.githooks" \
                        || fail "core.hooksPath unset — run: make hooks-install"
[ -x .githooks/pre-push ] && pass ".githooks/pre-push executable" \
                          || fail ".githooks/pre-push not executable — run: make hooks-install"

# 1d. 术语字典遵守（CONTEXT.md「术语字典表」强制规范）─────────────────
# 只扫本次 commit 引入的新增行（git diff 的 + 行），不扫历史文档（历史不主动返工）
# 弃用别名出现 → 报红阻塞；建议改用的词在错误消息里给出
# BSD ERE 兼容（不依赖 -P / lookbehind）:
#   - ASCII 简写用 ASCII_BOUNDARY=(^|[^A-Za-z0-9_]) ... ([^A-Za-z0-9_]|$) 模拟 word boundary
#   - 中文词无 word concept 直接子串匹配
#   - 排除 +++ 文件头用 ^\+[^+] 而非 lookbehind
# 走临时文件中转（绕开 bash/zsh 间 printf|grep pipe 编码差异）
DEPRECATED_TERMS_ASCII=(
  # 「ASCII 简写|改用建议」
  'QV|快速看图器（代码符号场景用 QuickViewer*）'
  'SF|智能文件夹（代码符号场景用 SmartFolder）'
  'QVT|D-QV（QVT 已并入 D-QV 命名空间）'
)
DEPRECATED_TERMS_CN=(
  # 「中文词|改用建议」
  '看图器|快速看图器'
  '看图窗|快速看图器'
  '看图覆盖层|快速看图器'
  '内容去重|重复清理（功能）或 去重（动作）'
  '主窗口|图库主窗'
  '代表项|保留张'
  '找类似|找相似图'
  '类似图|相似图'
)

# staged 优先；没 staged 看 working-tree 未 stage 改动
# 豁免 CONTEXT.md（字典本身列弃用词，规则不该误伤自己的来源文档）
TERM_TMP=$(mktemp)
git diff --cached --no-color -U0 -- '*.md' ':(exclude)CONTEXT.md' > "$TERM_TMP" 2>/dev/null
[ ! -s "$TERM_TMP" ] && git diff --no-color -U0 -- '*.md' ':(exclude)CONTEXT.md' > "$TERM_TMP" 2>/dev/null

if [ ! -s "$TERM_TMP" ]; then
  pass "术语字典：no .md changes — skip"
  rm -f "$TERM_TMP"
else
  TERM_VIOLATIONS=0
  TERM_REPORT=""

  check_term() {
    local PATTERN_REGEX="$1"
    local SUGGEST="$2"
    local DISPLAY="$3"
    local HITS
    HITS=$(grep -nE "^\+[^+].*${PATTERN_REGEX}" "$TERM_TMP" 2>/dev/null || true)
    if [ -n "$HITS" ]; then
      TERM_VIOLATIONS=$((TERM_VIOLATIONS + 1))
      TERM_REPORT="${TERM_REPORT}\n      ✗ '${DISPLAY}' → 改用 ${SUGGEST}\n$(echo "$HITS" | head -3 | sed 's/^/        /')"
    fi
  }

  for RULE in "${DEPRECATED_TERMS_ASCII[@]}"; do
    WORD="${RULE%%|*}"
    SUGGEST="${RULE#*|}"
    check_term "(^|[^A-Za-z0-9_])${WORD}([^A-Za-z0-9_]|\$)" "$SUGGEST" "$WORD"
  done
  for RULE in "${DEPRECATED_TERMS_CN[@]}"; do
    WORD="${RULE%%|*}"
    SUGGEST="${RULE#*|}"
    check_term "${WORD}" "$SUGGEST" "$WORD"
  done

  rm -f "$TERM_TMP"

  if [ "$TERM_VIOLATIONS" -eq 0 ]; then
    pass "术语字典：本次 .md 改动无弃用词"
  else
    fail "术语字典：本次 .md 改动 ${TERM_VIOLATIONS} 处违规（见 CONTEXT.md「术语字典表」）"
    printf '%b\n' "$TERM_REPORT"
  fi
fi

die_if_red 1

# ═══════════════════════════════════════════════════════════════════
# Stage 2/3: 编译（30-60s）
# ═══════════════════════════════════════════════════════════════════
echo
echo "── Stage 2/3: xcodebuild build -quiet ──"
BUILD_LOG="$LOG_DIR/build-$STAMP.log"

# build 版本号注入：与 Makefile build target 一致（<commit>[-d].<MMDD-HHMM>）
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
if git diff --quiet HEAD -- Glance/ Makefile scripts/ 2>/dev/null; then
  DIRTY=""
else
  DIRTY="-d"
fi
BUILD_STAMP=$(date +%m%d-%H%M)
BUILD_VERSION="${COMMIT}${DIRTY}.${BUILD_STAMP}"

# 关于面板 Copyright 字段（与 Makefile 同步）
COPYRIGHT="© 2026 孙红军 · 16414766@qq.com · 小红书 382336617"

xcodebuild build \
  -project Glance.xcodeproj \
  -scheme Glance \
  -configuration Debug \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  CURRENT_PROJECT_VERSION="$BUILD_VERSION" \
  INFOPLIST_KEY_NSHumanReadableCopyright="$COPYRIGHT" \
  -quiet >"$BUILD_LOG" 2>&1
BUILD_EXIT=$?

if [ "$BUILD_EXIT" -eq 0 ]; then
  # 增量编译只动 bundle 内部文件（Contents/MacOS/Info.plist 等），wrapper 目录 mtime 不变；
  # touch 让 Finder 显示的 .app mtime 与当前编译时刻一致，方便用户凭 Finder 判断 freshness
  touch "$BUILD_DIR/Glance.app"

  # 写 BuildInfo.txt sidecar（不动 .app 内部，不影响 codesign）
  {
    printf 'commit:       %s\n' "$COMMIT"
    printf 'dirty:        %s\n' "$([ -z "$DIRTY" ] && echo no || echo yes)"
    printf 'version:      %s\n' "$BUILD_VERSION"
    printf 'commit_time:  %s\n' "$(git log -1 --format=%cI 2>/dev/null || echo unknown)"
    printf 'commit_msg:   %s\n' "$(git log -1 --format=%s 2>/dev/null || echo unknown)"
    printf 'built_at:     %s\n' "$(date +%FT%T%z)"
    printf 'host:         %s\n' "$(hostname)"
  } > "$BUILD_DIR/Glance.app.BuildInfo.txt"

  # 同步到 ~/sync/（Syncthing 目录），与 Makefile build target 行为一致；用户本地测试机从此处拉
  SYNC_DIR="$HOME/sync"
  rm -rf "$SYNC_DIR/Glance.app" "$SYNC_DIR/Glance.app.BuildInfo.txt"
  if cp -R "$BUILD_DIR/Glance.app" "$SYNC_DIR/Glance.app" \
     && cp "$BUILD_DIR/Glance.app.BuildInfo.txt" "$SYNC_DIR/Glance.app.BuildInfo.txt"; then
    pass "sync: copied to $SYNC_DIR/Glance.app + .BuildInfo.txt (version: $BUILD_VERSION)"
  else
    fail "sync: cp -R to $SYNC_DIR failed"
  fi

  CODE_WARNS=$(grep -cE '\.(swift|m|mm|h):[0-9]+:[0-9]+: warning: ' "$BUILD_LOG" || true)
  CODE_WARNS=${CODE_WARNS:-0}
  if [ "$CODE_WARNS" -eq 0 ]; then
    pass "build: SUCCEEDED, 0 code warnings"
  else
    # warning 非阻塞（不计 FAIL），但必须打印提示 — "不引入新 warning" 靠 CC 自查
    pass "build: SUCCEEDED"
    echo "      [!] $CODE_WARNS code warnings — 按全局规则不得引入新 warning，请 CC 自查修复："
    grep -E '\.(swift|m|mm|h):[0-9]+:[0-9]+: warning: ' "$BUILD_LOG" | head -10 | sed 's/^/        /'
    echo "      完整 log: $BUILD_LOG"
  fi
else
  fail "build: xcodebuild exit=$BUILD_EXIT"
  note "first 30 actionable lines:"
  grep -E ' error: |undefined symbol|Swift Compiler Error|fatal error' "$BUILD_LOG" | head -30 | sed 's/^/        /'
  note "完整 log: $BUILD_LOG"
fi

die_if_red 2

# ═══════════════════════════════════════════════════════════════════
# Stage 3/3: 单测（当前 skip）
# ═══════════════════════════════════════════════════════════════════
echo
echo "── Stage 3/3: xcodebuild test ──"
skip "skipped: Glance 暂无 XCTest target"
note "补 test bundle 后在 verify.sh 取消下方注释启用:"
note "  xcodebuild test -project ... -scheme ... -destination 'platform=macOS' \\"
note "    CONFIGURATION_BUILD_DIR=\"$BUILD_DIR\" -quiet >\"\$TEST_LOG\" 2>&1"

# ═══════════════════════════════════════════════════════════════════
# Optional: codex 全项目审查
# ═══════════════════════════════════════════════════════════════════
if [ "$WITH_CODEX" -eq 1 ]; then
  echo
  echo "── Optional: codex 全项目审查 ──"
  if ! command -v codex >/dev/null 2>&1; then
    fail "codex binary not found"
  else
    CODEX_LOG="$LOG_DIR/codex-$STAMP.log"
    TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 600"
    PROMPT='Audit the Glance working tree against CLAUDE.md + specs/UI.md hard rules. Output ONLY issues, one per line:
[P1|P2] <path>:<line> — <issue>
If no issues: output exactly: CLEAN

Focus on: force unwrap / magic numbers / single public type per file / TODO format / non-Apple imports / async-await compliance / DS.* usage in UI constants / .spring in viewer-family / hardcoded .white or .black in ImagePreviewView / QuickViewerOverlay dark-only colors.'
    if $TO codex exec -s read-only --ephemeral --color never \
        -o "$CODEX_LOG" -c 'model_reasoning_effort="high"' "$PROMPT" >/dev/null 2>&1; then
      R=$(cat "$CODEX_LOG")
      if [ -z "$R" ]; then
        fail "codex returned empty output"
      elif printf '%s\n' "$R" | grep -q '\[P1\]'; then
        fail "codex [P1] issues"
        printf '%s\n' "$R" | sed 's/^/      /'
      elif printf '%s\n' "$R" | grep -q '\[P2\]'; then
        pass "codex: no [P1]"
        note "[P2] warnings:"
        printf '%s\n' "$R" | grep '\[P2\]' | sed 's/^/        /'
      else
        pass "codex: CLEAN"
      fi
    else
      fail "codex exec failed or timed out"
      note "log: $CODEX_LOG"
    fi
  fi
fi

echo
echo "=== summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
