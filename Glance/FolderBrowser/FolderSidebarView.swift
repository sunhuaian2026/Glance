//
//  FolderSidebarView.swift
//  Glance
//

import SwiftUI

struct FolderSidebarView: View {
    @EnvironmentObject var folderStore: FolderStore
    @State private var isDropTargeted: Bool = false

    /// Slice D — hide toggle 回调：(rootURL, nodeURL)；root 节点 nodeURL == rootURL。
    /// 由 ContentView 实现，调 IndexStore + 触发 SmartFolderStore re-query。
    var onToggleHide: ((URL, URL) -> Void)? = nil
    /// Slice D — query effective hidden 给 menu label 动态文案；同 (rootURL, nodeURL) 语义。
    var isEffectivelyHidden: ((URL, URL) -> Bool)? = nil
    /// Slice D follow-up — 是否 row 自己显式 hide=1（不走继承）。给行视觉决定是否显 eye.slash。
    /// 区分于 isEffectivelyHidden：root hide 整树场景 subfolder effective hidden 但非 explicit，不显图标避噪音。
    var isExplicitlyHidden: ((URL, URL) -> Bool)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 紫色环境光光晕
            RadialGradient(
                colors: [DS.Color.glowPrimary.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            List(
                folderStore.rootFolders,
                children: \.children,
                selection: Binding<URL?>(
                    get: { folderStore.selectedFolder },
                    set: { url in
                        if let url { folderStore.selectFolder(url) }
                    }
                )
            ) { node in
                folderRow(node)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            // 删除 .background(DS.Color.appBackground)：让 NavigationSplitView + listStyle(.sidebar)
            // 自带的 NSVisualEffectView material .sidebar 接管 — 跟 Finder/Mail/Notes 一致，
            // 失焦自动响应（state = .followsWindowActiveState 默认），dark/light 自动切
            .contextMenu {
                Button("添加文件夹…") { folderStore.addFolder() }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        folderStore.addFolder()
                    } label: {
                        Label("添加文件夹", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("文件夹")
        } // ZStack
        // Finder 拖拽入口：整个 sidebar 接 URL，filter 目录后走 FolderStore 批量入口
        .dropDestination(for: URL.self) { urls, _ in
            folderStore.addFolders(from: urls)
            return true
        } isTargeted: { hovering in
            withAnimation(DS.Anim.fast) { isDropTargeted = hovering }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DS.Sidebar.dropBorderCornerRadius)
                    .strokeBorder(
                        DS.Color.glowPrimary.opacity(DS.Sidebar.dropBorderOpacity),
                        lineWidth: DS.Sidebar.dropBorderWidth
                    )
                    .padding(DS.Sidebar.dropBorderPadding)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 找 node 所属的 root URL：root 节点本身 / 或某 root 是 node.url 路径前缀。
    /// 用于把 hide toggle 落到 IndexStore 的 (rootId, relativePath) 坐标。
    /// 嵌套 root 场景（同时管理 /parent 和 /parent/child）必须取**最长前缀**，
    /// 否则 /parent/child/foo.png 会被错路由到 /parent root（codex P2）。
    private func rootURL(for nodeURL: URL) -> URL? {
        let nodePath = nodeURL.standardizedFileURL.path
        let candidates = folderStore.rootFolders.filter { root in
            let rootPath = root.url.standardizedFileURL.path
            return rootPath == nodePath || nodePath.hasPrefix(rootPath + "/")
        }
        return candidates.max(by: { lhs, rhs in
            lhs.url.standardizedFileURL.path.count < rhs.url.standardizedFileURL.path.count
        })?.url
    }

    // MARK: - 行视图

    @ViewBuilder
    private func folderRow(_ node: FolderNode) -> some View {
        let isRoot = folderStore.rootFolders.contains(where: { $0.url == node.url })
        let count = folderStore.imageCountByFolder[node.url]

        HStack {
            Label(node.url.lastPathComponent, systemImage: "folder")
            // Slice D follow-up — row 自己 explicit hide=1 时显 eye.slash 图标。
            // 用 explicit 而非 effective：root hide 整树时 subfolder 继承 hidden 但非显式 set，
            // 不显图标避免视觉噪音（root 行图标已表达整树状态）
            if let rootURL = rootURL(for: node.url),
               isExplicitlyHidden?(rootURL, node.url) == true {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("在智能文件夹中隐藏")
            }
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        // 未选中行用 Color.clear 让 listStyle(.sidebar) 的 NSVisualEffectView material 透出
        // （否则 row 被硬色覆盖会造成"紫深色条纹 + 选中行 vibrancy"的不一致视觉）。
        // 选中行也 clear，让系统选中高亮（accent color）独立渲染在 vibrancy 上。
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: node.url.path)
            }
            // 刷新 = 重建该 node 所属 root 整子文件夹树 + 若选中节点在该树内则 reload grid 图片
            // (右键直接点的 node 即用户意图目标, Finder 行为, 不再依赖 selection)
            Button("刷新") { folderStore.refreshNode(node.url) }
            if let toggle = onToggleHide, let rootURL = rootURL(for: node.url) {
                let hidden = isEffectivelyHidden?(rootURL, node.url) ?? false
                Button(hidden ? "在智能文件夹中显示" : "在智能文件夹中隐藏") {
                    toggle(rootURL, node.url)
                }
            }
            if isRoot {
                Divider()
                Button("移除文件夹", role: .destructive) {
                    folderStore.removeFolder(node.url)
                }
            }
        }
    }
}
