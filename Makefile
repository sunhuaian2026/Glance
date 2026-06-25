.PHONY: build run clean hooks-install hooks-uninstall verify verify-codex release release-dry release-appstore

BUILD_DIR = ./build
SYNC_DIR  = $(HOME)/sync

# build 版本号注入：<commit short hash>[-d].<MMDD-HHMM>
# 关于面板（macOS About）显示「版本 1.0 (fb7f900-d.0504-2318)」；
# -d 后缀标记 working tree 有未 commit 改动，避免误读为该 commit 真值
COMMIT  := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
DIRTY   := $(shell git diff --quiet HEAD -- Glance/ Makefile scripts/ 2>/dev/null && echo "" || echo "-d")
STAMP   := $(shell date +%m%d-%H%M)
VERSION := $(COMMIT)$(DIRTY).$(STAMP)

# 关于面板 Copyright 字段（系统 NSAboutPanel 单行 truncate-by-tail，
# 多行 \n 不渲染折行，所以信息压一行）。Year 跟随 commit_time 调，
# 暂硬编 2026
COPYRIGHT := © 2026 孙红军 · 16414766@qq.com · 小红书 382336617

build:
	xcodebuild -project Glance.xcodeproj -scheme Glance \
		-configuration Debug CONFIGURATION_BUILD_DIR=$(BUILD_DIR) \
		CURRENT_PROJECT_VERSION="$(VERSION)" \
		INFOPLIST_KEY_NSHumanReadableCopyright="$(COPYRIGHT)" \
		build
	@touch $(BUILD_DIR)/Glance.app
	@echo "  ✓ touched $(BUILD_DIR)/Glance.app — Finder mtime 同步到当前编译时刻"
	@printf 'commit:       %s\ndirty:        %s\nversion:      %s\ncommit_time:  %s\ncommit_msg:   %s\nbuilt_at:     %s\nhost:         %s\n' \
		"$(COMMIT)" \
		"$$([ -z '$(DIRTY)' ] && echo no || echo yes)" \
		"$(VERSION)" \
		"$$(git log -1 --format=%cI 2>/dev/null || echo unknown)" \
		"$$(git log -1 --format=%s 2>/dev/null || echo unknown)" \
		"$$(date +%FT%T%z)" \
		"$$(hostname)" \
		> $(BUILD_DIR)/Glance.app.BuildInfo.txt
	@echo "  ✓ wrote $(BUILD_DIR)/Glance.app.BuildInfo.txt (version: $(VERSION))"
	@rm -rf $(SYNC_DIR)/Glance.app $(SYNC_DIR)/Glance.app.BuildInfo.txt
	@cp -R $(BUILD_DIR)/Glance.app $(SYNC_DIR)/Glance.app
	@cp $(BUILD_DIR)/Glance.app.BuildInfo.txt $(SYNC_DIR)/Glance.app.BuildInfo.txt
	@echo "  ✓ synced to $(SYNC_DIR)/Glance.app + .BuildInfo.txt"

run: build
	open $(BUILD_DIR)/Glance.app

clean:
	rm -rf $(BUILD_DIR)

hooks-install:
	chmod +x .githooks/commit-msg .githooks/pre-push scripts/verify.sh
	git config core.hooksPath .githooks
	@echo "✓ git hooks installed (core.hooksPath=.githooks)"
	@echo "  active hooks:"
	@echo "    commit-msg — 字典禁用词扫描"
	@echo "    pre-push   — secrets/.env 防泄漏拦截 (轻量 0ms, 2026-06-17 重建)"
	@echo "  bypass one push: git push --no-verify"

hooks-uninstall:
	-git config --unset core.hooksPath
	@echo "✓ git hooks disabled (core.hooksPath unset)"

verify:
	@chmod +x scripts/verify.sh 2>/dev/null || true
	@./scripts/verify.sh

verify-codex:
	@chmod +x scripts/verify.sh 2>/dev/null || true
	@./scripts/verify.sh --with-codex

# 公开分发打包：xcodebuild archive (Release + Hardened Runtime + Developer ID signed)
#   → exportArchive → create-dmg → notarytool submit --wait → stapler staple
#   → dist/Glance-<MARKETING_VERSION>.dmg
release:
	@chmod +x scripts/release.sh 2>/dev/null || true
	@./scripts/release.sh

# 跳过公证的 dry-run（本地验证签名 + DMG 流程，不耗 Apple notarization quota）
release-dry:
	@chmod +x scripts/release.sh 2>/dev/null || true
	@SKIP_NOTARIZE=1 ./scripts/release.sh

# Mac App Store 上架打包: xcodebuild archive (Release-AppStore + Apple Distribution signed)
#   → exportArchive (ExportOptions-AppStore.plist) → dist/export-appstore/Glance.pkg
# 任务 4 (Mac App Store 上架 plan)
release-appstore:
	@chmod +x scripts/release-appstore.sh 2>/dev/null || true
	@./scripts/release-appstore.sh
