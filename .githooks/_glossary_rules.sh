#!/bin/bash
# Glossary enforcement rules — single source of truth, shared by:
#   - scripts/verify.sh Stage 1d (scans staged .md diff)
#   - .githooks/commit-msg     (scans commit message)
#
# Rule changes here must stay in sync with CONTEXT.md「术语字典表」.
# See CONTEXT.md for human-readable docs; this file is the machine-checked form.

# ==== Rule arrays ====
# Format: 'pattern|改用建议'
# ASCII = simple word, wrapped with word-boundary at runtime
# REGEX = pattern with special chars (- / #), used as-is (no boundary wrap)
# CN    = Chinese word, no boundary needed

GLOSSARY_ASCII=(
  # ── A 自造简写 ────────────────────────
  'QV|快速看图器（代码符号场景用 QuickViewer*）'
  'SF|智能文件夹（代码符号场景用 SmartFolder）'
  'QVT|D-QV（QVT 已并入 D-QV 命名空间）'
  'I1|codex 实施期 issue（一句话内容）'
  'I2|codex 实施期 issue（一句话内容）'
  'M-1|codex major issue（一句话内容）'
  # ── 三层方法论：Slice 单词大小写禁用 ────
  'Slice|任务（V2 M1 任务 A / M2 任务 J 等）'
  'slice|任务（V2 M1 任务 A / M2 任务 J 等）'
  # ── B 同义簇（英文场景，代码符号请在 backtick 内）────
  'Sandbox|沙盒（首字母大写仅在 macOS 文档原文场景保留）'
  'Bookmark|首次写全 Security Scoped Bookmark 后续 bookmark（句首大写之外）'
  'Canonical|保留张'
  'Ephemeral|临时结果（视图）'
  'FullScreen|全屏'
  'Thumbnail|缩略图'
  'Focus|焦点'
  # ── C 中英文边界 ───────────────────────
  'Sidebar|侧边栏'
  'Toolbar|工具栏'
  'Grid|缩略图网格'
)
GLOSSARY_REGEX=(
  # ── A codex review 编号 ───────────────
  'P[12]-[0-9A-Z]+|codex P1/P2（一句话内容）'
  'P[12]#[0-9]+|codex P1/P2（一句话内容）'
  'I-[0-9]+|codex 实施期 issue（一句话内容）'
  # ── 三层方法论：Slice 系列禁用,改"任务" ─
  '[Vv]ertical [Ss]lice|任务'
  '\bVS[0-9]|任务（如 VS1 → 任务 1）'
)
GLOSSARY_CN=(
  # ── B 同义簇（中文）─────────────────────
  # 注：「看图器」用 (^|[^速])看图器 避免「快速看图器」子串误匹配
  '(^|[^速])看图器|快速看图器'
  '看图窗|快速看图器'
  '看图覆盖层|快速看图器'
  '内容去重|重复清理（功能）或 去重（动作）'
  '主窗口|图库主窗'
  '代表项|保留张'
  '找类似|找相似图'
  '类似图|相似图'
  '书签|首次写全 Security Scoped Bookmark 后续 bookmark'
  # ── 三层方法论（中文 Slice 别名）────────
  '切片|任务（V2 M1 任务 A / M2 任务 J 等）'
  # 注：单字「片」误伤太广（图片/片段/动作片），不机械拦截，靠人工 review
  # ── C 中英文边界（小写英文）──────────────
  'sidebar|侧边栏'
  'toolbar|工具栏'
)

# ==== Diff preprocessor (verify.sh 用) ====
# 输入: diff -U999 内容（stdin）
# 输出: 仅 + 新增行（剥 inline backtick、跳过 fenced code block / 文件元信息）
glossary_filter_diff() {
  awk '
    /^diff --git/ { in_fenced = 0; next }
    /^\+\+\+/ || /^---/ || /^@@/ || /^index/ || /^Binary / { next }
    {
      line = $0
      first = substr(line, 1, 1)
      content = substr(line, 2)
      # fenced 边界（支持 ``` 在 + - 或 context 行）
      if (match(content, /^[[:space:]]*```/)) {
        in_fenced = 1 - in_fenced
        next
      }
      if (in_fenced) next
      if (first != "+") next
      gsub(/`[^`]*`/, "", content)
      print NR ":" content
    }
  '
}

# ==== Plain-text preprocessor (commit-msg 用) ====
# 输入: commit message 文本（stdin）
# 输出: 剥 inline backtick + 跳 fenced code block 后的纯文本
glossary_filter_text() {
  awk '
    {
      line = $0
      if (match(line, /^[[:space:]]*```/)) {
        in_fenced = 1 - in_fenced
        next
      }
      if (in_fenced) next
      gsub(/`[^`]*`/, "", line)
      print NR ":" line
    }
  '
}

# ==== Rule runner ====
# 输入:
#   $1 = filtered text file (一行一行，含可选 LINENO: 前缀)
# 输出全局变量:
#   GLOSSARY_VIOLATIONS = 违规计数
#   GLOSSARY_REPORT     = 多行报告字符串
glossary_check() {
  local INPUT="$1"
  GLOSSARY_VIOLATIONS=0
  GLOSSARY_REPORT=""

  _check() {
    local PATTERN="$1"
    local SUGGEST="$2"
    local DISPLAY="$3"
    local HITS
    HITS=$(grep -nE "$PATTERN" "$INPUT" 2>/dev/null || true)
    if [ -n "$HITS" ]; then
      GLOSSARY_VIOLATIONS=$((GLOSSARY_VIOLATIONS + 1))
      GLOSSARY_REPORT="${GLOSSARY_REPORT}\n      ✗ '${DISPLAY}' → 改用 ${SUGGEST}\n$(echo "$HITS" | head -3 | sed 's/^/        /')"
    fi
  }

  for RULE in "${GLOSSARY_ASCII[@]}"; do
    WORD="${RULE%%|*}"
    SUGGEST="${RULE#*|}"
    _check "(^|[^A-Za-z0-9_])${WORD}([^A-Za-z0-9_]|\$)" "$SUGGEST" "$WORD"
  done
  for RULE in "${GLOSSARY_REGEX[@]}"; do
    PAT="${RULE%%|*}"
    SUGGEST="${RULE#*|}"
    _check "$PAT" "$SUGGEST" "$PAT"
  done
  for RULE in "${GLOSSARY_CN[@]}"; do
    WORD="${RULE%%|*}"
    SUGGEST="${RULE#*|}"
    _check "$WORD" "$SUGGEST" "$WORD"
  done
}
