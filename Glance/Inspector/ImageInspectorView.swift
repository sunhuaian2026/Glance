//
//  ImageInspectorView.swift
//  Glance
//

import SwiftUI

struct ImageInspectorView: View {
    let url: URL?
    /// Slice H — closure 注入：query 跟 url 内容相同（同 SHA256）的其他 image path 列表。
    /// 由 ContentView 提供，内部走 IndexStore.fetchDuplicatesByFullPath。
    /// nil 时副本段不渲染（V1 单 folder 模式 / IndexStore 未就绪）。
    var duplicatesProvider: ((URL) -> [(id: Int64, fullPath: String)])? = nil

    @StateObject private var viewModel = ImageInspectorViewModel()
    @State private var duplicates: [(id: Int64, fullPath: String)] = []

    var body: some View {
        Group {
            if url == nil {
                ContentUnavailableView(
                    "未选择图片",
                    systemImage: "info.circle",
                    description: Text("双击图片查看元信息")
                )
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let info = viewModel.info, let url {
                infoForm(info, url: url)
            } else {
                ContentUnavailableView(
                    "无法读取元信息",
                    systemImage: "exclamationmark.circle"
                )
            }
        }
        .task(id: url) {
            guard let url else {
                viewModel.cancel()
                duplicates = []
                return
            }
            await viewModel.load(url: url)
            // Slice H — 同步刷副本列表（IndexStore 内部 sync queue 阻塞但快速 SQL）
            duplicates = duplicatesProvider?(url) ?? []
        }
        .onDisappear { viewModel.cancel() }
        // 边线绑定到 Inspector 视图本身，跟随 .move(.trailing)+.opacity transition
        // 同步出入，避免 ContentView 里独立 Divider 与 Inspector 动画不同步
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DS.Color.separatorColor)
                .frame(width: DS.Inspector.separatorWidth)
        }
    }

    // MARK: - Form

    @ViewBuilder
    private func infoForm(_ info: ImageInfo, url: URL) -> some View {
        Form {
            Section("文件信息") {
                LabeledContent("文件名", value: info.fileName)
                LabeledContent("尺寸", value: info.dimensions)
                LabeledContent("修改日期", value: info.modifiedDate)
                LabeledContent("大小", value: info.fileSize)
                if let cs = info.colorSpace {
                    LabeledContent("色彩空间", value: cs)
                }
            }

            if info.cameraMake != nil || info.cameraModel != nil || info.lensModel != nil {
                Section("相机") {
                    if let make = info.cameraMake { LabeledContent("品牌", value: make) }
                    if let model = info.cameraModel { LabeledContent("型号", value: model) }
                    if let lens = info.lensModel { LabeledContent("镜头", value: lens) }
                }
            }

            if info.aperture != nil || info.shutterSpeed != nil || info.iso != nil || info.focalLength != nil {
                Section("拍摄参数") {
                    if let taken = info.dateTaken { LabeledContent("拍摄时间", value: taken) }
                    if let ap = info.aperture { LabeledContent("光圈", value: ap) }
                    if let ss = info.shutterSpeed { LabeledContent("快门", value: ss) }
                    if let iso = info.iso { LabeledContent("ISO", value: iso) }
                    if let fl = info.focalLength { LabeledContent("焦距", value: fl) }
                    if let ev = info.exposureBias { LabeledContent("曝光补偿", value: ev) }
                }
            }

            if let gps = info.gps {
                Section("位置") {
                    LabeledContent("GPS", value: gps)
                }
            }

            // Slice D.2: 来源段。跨 folder 智能文件夹场景下用户找原文件路径的快捷入口；
            // V1 单 folder 模式同样有用（confirm 当前选中图属于哪个文件夹）。
            Section("来源") {
                LabeledContent("路径") {
                    Text(url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
            }

            // Slice H：副本段。条件展示——有 duplicates 才显示（同 SHA256 其他 image rows）。
            // 列出每条 fullPath（truncation .middle）+ "在 Finder 中显示"按钮。
            if !duplicates.isEmpty {
                Section("副本（\(duplicates.count) 个）") {
                    ForEach(duplicates, id: \.id) { dup in
                        HStack {
                            Text(dup.fullPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                let dupURL = URL(fileURLWithPath: dup.fullPath)
                                NSWorkspace.shared.activateFileViewerSelecting([dupURL])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("在 Finder 中显示")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
