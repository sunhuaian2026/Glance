import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageMetadata {
    let birthTime: Date           // file birth time (创建/到达本机的时间)
    let fileSize: Int64
    let format: String            // "PNG" / "JPEG" / "HEIC" / etc.
    let filename: String
    let dimensionsWidth: Int?
    let dimensionsHeight: Int?
}

nonisolated enum ImageMetadataReader {

    /// Read metadata for a single file. Returns nil if the file is not an image
    /// (UTType not conforming to .image), is unreadable, or birth time missing.
    static func read(at url: URL) -> ImageMetadata? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }

        guard let creation = attrs[.creationDate] as? Date else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        guard let utType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
              utType.conforms(to: .image) else {
            return nil
        }
        let format = formatLabel(for: utType)

        var width: Int?
        var height: Int?
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int
            height = props[kCGImagePropertyPixelHeight] as? Int
        }

        return ImageMetadata(
            birthTime: creation,
            fileSize: size,
            format: format,
            filename: url.lastPathComponent,
            dimensionsWidth: width,
            dimensionsHeight: height
        )
    }

    /// chip 类型选项的唯一权威来源。顺序 = chip 显示顺序。
    /// 必须与 formatLabel 输出的标签**逐字符一致**（含 "WebP" 混合大小写），
    /// 否则 chip 的 `format IN (...)` 精确匹配会漏命中（design R5）。
    /// 新增格式时：formatLabel 加分支 + 此处加标签，两处同步。
    static let canonicalFormatLabels: [String] = ["PNG", "JPEG", "HEIC", "GIF", "WebP", "TIFF", "BMP", "RAW"]

    static func formatLabel(for utType: UTType) -> String {   // 去掉 private
        if utType.conforms(to: .png) { return "PNG" }
        if utType.conforms(to: .jpeg) { return "JPEG" }
        if utType.conforms(to: .heic) { return "HEIC" }
        if utType.conforms(to: .tiff) { return "TIFF" }
        if utType.conforms(to: .gif) { return "GIF" }
        if utType.conforms(to: .webP) { return "WebP" }
        if utType.conforms(to: .bmp) { return "BMP" }
        if utType.conforms(to: .rawImage) { return "RAW" }
        return utType.preferredFilenameExtension?.uppercased() ?? "IMAGE"
    }
}
