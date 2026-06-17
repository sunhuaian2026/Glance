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
[ -x .githooks/commit-msg ] && pass ".githooks/commit-msg executable" \
                            || fail ".githooks/commit-msg not executable — run: make hooks-install"

# 1d. 术语字典遵守（CONTEXT.md「术语字典表」强制规范）─────────────────
# 规则源：.githooks/_glossary_rules.sh（单一来源，commit-msg hook 共用）
# 范围：所有 staged .md 改动（含新增/修改/重命名）的 + 行；CONTEXT.md 自身豁免
# 豁免：fenced code block (``` ... ```) 内容 + inline backtick `...` 内容
# diff -U999 拿足够大上下文以重建 fenced 边界状态
GLOSSARY_RULES_FILE=".githooks/_glossary_rules.sh"
if [ ! -f "$GLOSSARY_RULES_FILE" ]; then
  fail "术语字典规则文件缺失：$GLOSSARY_RULES_FILE"
else
  # shellcheck source=/dev/null
  . "$GLOSSARY_RULES_FILE"

  TERM_TMP=$(mktemp)
  # 豁免:CONTEXT.md（字典本身）+ AGENTS.md（会话历史日志）+ CLAUDE.md（术语规则元文档,自身要列禁用词）
  git diff --cached --no-color -U999 -- '*.md' ':(exclude)CONTEXT.md' ':(exclude)AGENTS.md' ':(exclude)CLAUDE.md' > "$TERM_TMP" 2>/dev/null

  if [ ! -s "$TERM_TMP" ]; then
    pass "术语字典：no staged .md changes — skip"
    rm -f "$TERM_TMP"
  else
    CLEAN_TMP=$(mktemp)
    glossary_filter_diff < "$TERM_TMP" > "$CLEAN_TMP"
    rm -f "$TERM_TMP"

    glossary_check "$CLEAN_TMP"
    rm -f "$CLEAN_TMP"

    if [ "$GLOSSARY_VIOLATIONS" -eq 0 ]; then
      pass "术语字典：本次 .md 改动无弃用词"
    else
      fail "术语字典：本次 .md 改动 ${GLOSSARY_VIOLATIONS} 处违规（见 CONTEXT.md「术语字典表」）"
      printf '%b\n' "$GLOSSARY_REPORT"
    fi
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
