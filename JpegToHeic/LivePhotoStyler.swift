import Foundation

/// 给实况照片的视频补上风格轨道（线性缩略图、遮罩、风格元数据），
/// 与移植后的静态 HEIC 配对，使照片 App 的编辑器能对整段实况生效。
@available(iOS 16, *)
enum LivePhotoStyler {
    /// 把 `source` 视频风格化后写到 `destination`；不缺任何部件时原样复制。
    static func style(_ source: URL, to destination: URL, texture: Bool) async throws {
        let video = try Data(contentsOf: source, options: .mappedIfSafe)
        var wanted = LivePhotoVideo.Parts.style
        if texture { wanted.insert(.textureInfo) }
        let missing = wanted.subtracting(try LivePhotoVideo.parts(of: video))
        guard !missing.isEmpty else {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        let thumbnail = missing.contains(.linearThumbnail)
            ? try await LinearThumbnailEncoder.encode(videoURL: source)
            : nil
        let styled = try LivePhotoVideo.add(wanted, to: video, linearThumbnail: thumbnail)
        try styled.0.write(to: destination, options: .atomic)
    }
}
