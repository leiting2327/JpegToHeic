import Foundation
import Photos
import ImageIO
import UniformTypeIdentifiers

/// 一张实况照片的配对视频文件。
struct PairedVideo: Sendable {
    let url: URL
    let filename: String
    let typeIdentifier: String
}

enum TempFiles {
    static func newDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("J2H-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// 相册读取 / 反查实况视频 / 配对保存。仅用 completion 回调，兼容 iOS 15。
enum PhotoLib {

    // MARK: - 权限

    static func hasReadAccess() -> Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .authorized || s == .limited
    }

    static func requestReadAccess(_ completion: @escaping (Bool) -> Void) {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if s == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { st in
                DispatchQueue.main.async { completion(st == .authorized || st == .limited) }
            }
        } else {
            completion(s == .authorized || s == .limited)
        }
    }

    static func requestAddAccess(_ completion: @escaping (Bool) -> Void) {
        let s = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if s == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { st in
                DispatchQueue.main.async { completion(st == .authorized || st == .limited) }
            }
        } else {
            completion(s == .authorized || s == .limited)
        }
    }

    // MARK: - 读取资源

    static func data(for resource: PHAssetResource,
                     _ completion: @escaping (Result<Data, Error>) -> Void) {
        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true
        var buf = Data()
        PHAssetResourceManager.default().requestData(
            for: resource, options: opts,
            dataReceivedHandler: { buf.append($0) },
            completionHandler: { err in
                if let err = err { completion(.failure(err)) }
                else { completion(.success(buf)) }
            })
    }

    static func writeToTemp(resource: PHAssetResource,
                            _ completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            let dir = try TempFiles.newDir()
            let name = resource.originalFilename.isEmpty ? "video.mov" : resource.originalFilename
            let dest = dir.appendingPathComponent(name)
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(
                for: resource, toFile: dest, options: opts
            ) { err in
                if let err = err { completion(.failure(err)) }
                else { completion(.success(dest)) }
            }
        } catch { completion(.failure(error)) }
    }

    // MARK: - 反查实况配对视频

    /// 根据 HEIC 的实况内容标识（MakerNote 0x11）与拍摄时间，在相册里反查它的配对视频。
    static func findPairedVideo(forHEIC data: Data,
                                _ completion: @escaping (PairedVideo?) -> Void) {
        guard let identifier = AppleExif.contentIdentifier(ofHEIC: data),
              let captured = captureDate(of: data) else {
            completion(nil); return
        }
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND (mediaSubtypes & %d) != 0",
            captured.addingTimeInterval(-3) as NSDate,
            captured.addingTimeInterval(3) as NSDate,
            Int(PHAssetMediaSubtype.photoLive.rawValue))
        opts.fetchLimit = 12
        let candidates = PHAsset.fetchAssets(with: .image, options: opts)
        tryMatch(index: 0, candidates: candidates, identifier: identifier, completion: completion)
    }

    private static func tryMatch(index: Int,
                                 candidates: PHFetchResult<PHAsset>,
                                 identifier: String,
                                 completion: @escaping (PairedVideo?) -> Void) {
        guard index < candidates.count else { completion(nil); return }
        let asset = candidates.object(at: index)
        let resources = PHAssetResource.assetResources(for: asset)
        guard let photo = resources.first(where: { $0.type == .photo }),
              let paired = resources.first(where: { $0.type == .pairedVideo }) else {
            tryMatch(index: index + 1, candidates: candidates, identifier: identifier, completion: completion)
            return
        }
        data(for: photo) { res in
            guard case .success(let d) = res,
                  AppleExif.contentIdentifier(ofHEIC: d) == identifier else {
                tryMatch(index: index + 1, candidates: candidates, identifier: identifier, completion: completion)
                return
            }
            writeToTemp(resource: paired) { wres in
                guard case .success(let url) = wres else {
                    tryMatch(index: index + 1, candidates: candidates, identifier: identifier, completion: completion)
                    return
                }
                completion(PairedVideo(url: url,
                                       filename: paired.originalFilename,
                                       typeIdentifier: paired.uniformTypeIdentifier))
            }
        }
    }

    // MARK: - 配对保存（照片 + 视频 = 实况）

    /// 同一个创建请求里同时加照片与配对视频，Photos 会按内容标识自动配回实况照片。
    static func savePair(photoURL: URL,
                         photoName: String,
                         video: PairedVideo?,
                         completion: @escaping (Result<Void, Error>) -> Void) {
        requestAddAccess { ok in
            guard ok else {
                completion(.failure(NSError(domain: "PhotoLib", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: "未授权相册访问"])))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                let po = PHAssetResourceCreationOptions()
                po.originalFilename = photoName
                po.uniformTypeIdentifier = UTType.heic.identifier
                po.shouldMoveFile = false
                req.addResource(with: .photo, fileURL: photoURL, options: po)
                if let v = video {
                    let vo = PHAssetResourceCreationOptions()
                    vo.originalFilename = v.filename
                    vo.uniformTypeIdentifier = v.typeIdentifier
                    vo.shouldMoveFile = false
                    req.addResource(with: .pairedVideo, fileURL: v.url, options: vo)
                }
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success { completion(.success(())) }
                    else {
                        completion(.failure(error ?? NSError(domain: "PhotoLib", code: 2,
                                                              userInfo: [NSLocalizedDescriptionKey: "未知错误"])))
                    }
                }
            })
        }
    }

    // MARK: - 拍摄时间（用于反查窗口）

    static func captureDate(of data: Data) -> Date? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = offset == nil ? "yyyy:MM:dd HH:mm:ss" : "yyyy:MM:dd HH:mm:ssxxx"
        return f.date(from: original + (offset ?? ""))
    }
}
