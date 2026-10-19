import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import Photos
import UIKit

/// JPEG → HEIC 转换引擎。
/// 使用 iOS 原生 ImageIO 编码 HEIC(HEVC)，支持无损 / 高质量有损两种模式。
enum HeicConverter {

    enum ConvertError: LocalizedError {
        case cannotReadSource
        case cannotDecodeImage
        case cannotCreateDestination
        case finalizeFailed

        var errorDescription: String? {
            switch self {
            case .cannotReadSource:   return "无法读取图片源文件"
            case .cannotDecodeImage:  return "无法解码该 JPEG 图片"
            case .cannotCreateDestination: return "无法创建 HEIC 输出文件"
            case .finalizeFailed:     return "HEIC 写入失败"
            }
        }
    }

    /// 一次转换的结果
    struct Result {
        let sourceSize: Int64
        let outputSize: Int64
        let outputURL: URL

        var savedBytes: Int64 { sourceSize - outputSize }
        var savedPercent: Double {
            sourceSize > 0 ? Double(sourceSize - outputSize) / Double(sourceSize) * 100 : 0
        }
        var sizeDescription: String {
            "\(fmt(sourceSize)) → \(fmt(outputSize))  KB"
        }
        private func fmt(_ b: Int64) -> String {
            String(format: "%.1f", Double(b) / 1024)
        }
    }

    /// 把 JPEG 文件编码为 HEIC 文件。
    /// - Parameters:
    ///   - jpegURL: 源 JPEG 文件
    ///   - outputURL: 目标 HEIC 文件位置
    ///   - quality: 有损模式质量 0...1
    ///   - lossless: 是否无损（无损时像素 100% 保留，文件通常更大）
    static func convert(jpegURL: URL, outputURL: URL, quality: Float, lossless: Bool) throws -> Result {
        guard let source = CGImageSourceCreateWithURL(jpegURL as CFURL, nil) else {
            throw ConvertError.cannotReadSource
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConvertError.cannotDecodeImage
        }
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.heic.identifier as CFString, 1, nil
        ) else {
            throw ConvertError.cannotCreateDestination
        }

        let props: [CFString: Any] = lossless
            ? [kCGImagePropertyLossless: true]
            : [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw ConvertError.finalizeFailed
        }
        return Result(
            sourceSize: fileSize(jpegURL),
            outputSize: fileSize(outputURL),
            outputURL: outputURL
        )
    }

    /// 把生成的 HEIC 文件保存到系统相册（需要相册添加权限）
    static func saveToPhotoLibrary(heicURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(false, nil)
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                request.addResource(with: .photo, fileURL: heicURL, options: options)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    completion(success, error)
                }
            }
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }
}
