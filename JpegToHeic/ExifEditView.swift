import SwiftUI
import PhotosUI
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// 「元数据」功能：读取并修改照片的拍摄设备信息（厂商/机型/软件）与 GPS 位置。
/// 通过 CGImageDestinationCopyImageSource 只改写元数据、不重编码像素，画质不变。
struct ExifEditView: View {
    @State private var isPickerPresented = false
    @State private var pickedData: Data?
    @State private var fileName = ""

    @State private var make = ""
    @State private var model = ""
    @State private var software = ""
    @State private var latitude = ""
    @State private var longitude = ""

    @State private var isWorking = false
    @State private var resultData: Data?
    @State private var message: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    infoCard
                    if pickedData != nil { editorCard }
                    if resultData != nil { resultCard }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("元数据修改")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("选择照片") { isPickerPresented = true }
                        .disabled(isWorking)
                }
            }
            .sheet(isPresented: $isPickerPresented) {
                ExifPhotoPicker { data, name in load(data: data, name: name) }
                    .ignoresSafeArea()
            }
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var infoCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("设备与位置信息", systemImage: "info.circle.fill").font(.headline)
                Text("修改照片 EXIF 里的拍摄设备（厂商/机型/软件）与 GPS 经纬度。只改元数据，不重新压缩画面。")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private var editorCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(fileName).font(.subheadline).lineLimit(1)
                field("厂商 Make", text: $make)
                field("机型 Model", text: $model)
                field("软件 Software", text: $software)
                Divider()
                field("纬度（如 26.6）", text: $latitude)
                field("经度（如 119.5）", text: $longitude)
                Button {
                    applyEdit()
                } label: {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView().padding(.trailing, 6) }
                        Text("写入新元数据")
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
    }

    private var resultCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("已生成新文件").font(.headline).foregroundColor(.green)
                Text("新文件保留原画面，仅替换设备/位置元数据。")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Button { shareResult() } label: {
                        Label("分享/存文件", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    Button { saveToLibrary() } label: {
                        Label("存相册", systemImage: "photo.badge.plus").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled(true)
        }
    }

    // MARK: - 读取

    private func load(data: Data, name: String) {
        pickedData = data
        fileName = name
        resultData = nil
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            message = "无法读取这张照片的元数据。"
            return
        }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        make = tiff?[kCGImagePropertyTIFFMake] as? String ?? ""
        model = tiff?[kCGImagePropertyTIFFModel] as? String ?? ""
        software = tiff?[kCGImagePropertyTIFFSoftware] as? String ?? ""
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        if let lat = gps?[kCGImagePropertyGPSLatitude] as? Double {
            let ref = gps?[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            latitude = String(lat) + (ref == "S" ? "S" : "")
        } else { latitude = "" }
        if let lon = gps?[kCGImagePropertyGPSLongitude] as? Double {
            let ref = gps?[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            longitude = String(lon) + (ref == "W" ? "W" : "")
        } else { longitude = "" }
    }

    // MARK: - 写入（不重编码像素）

    private func applyEdit() {
        guard let data = pickedData else { return }
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let uti = CGImageSourceGetType(src) else {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.message = "不支持的图片格式。"
                }
                return
            }
            var newMeta: [CFString: Any] = [:]
            var tiff: [CFString: Any] = [:]
            if !make.isEmpty { tiff[kCGImagePropertyTIFFMake] = make }
            if !model.isEmpty { tiff[kCGImagePropertyTIFFModel] = model }
            if !software.isEmpty { tiff[kCGImagePropertyTIFFSoftware] = software }
            if !tiff.isEmpty { newMeta[kCGImagePropertyTIFFDictionary] = tiff }

            var gps: [CFString: Any] = [:]
            if let lat = Double(latitude.filter { !$0.isLetter }),
               let lon = Double(longitude.filter { !$0.isLetter }) {
                gps[kCGImagePropertyGPSLatitude] = abs(lat)
                gps[kCGImagePropertyGPSLatitudeRef] = lat >= 0 ? "N" : "S"
                gps[kCGImagePropertyGPSLongitude] = abs(lon)
                gps[kCGImagePropertyGPSLongitudeRef] = lon >= 0 ? "E" : "W"
            }
            if !gps.isEmpty { newMeta[kCGImagePropertyGPSDictionary] = gps }

            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, uti, 1, nil) else {
                DispatchQueue.main.async { self.isWorking = false; self.message = "创建输出失败。"; return }
                return
            }
            var err: Unmanaged<CFError>?
            let ok = CGImageDestinationCopyImageSource(
                dest, src,
                [kCGImageDestinationMetadata: newMeta as CFDictionary,
                 kCGImageDestinationMergeMetadata: true] as CFDictionary,
                &err)
            DispatchQueue.main.async {
                self.isWorking = false
                if ok {
                    self.resultData = out as Data
                    self.message = "元数据已写入。"
                } else {
                    self.message = "写入失败：\(err?.takeRetainedValue().localizedDescription ?? "未知错误")"
                }
            }
        }
    }

    // MARK: - 输出

    private func resultFileURL() -> URL? {
        guard let data = resultData else { return nil }
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let ext = (fileName as NSString).pathExtension
        let url = base.appendingPathComponent((fileName as NSString).deletingPathExtension + "_edited." + (ext.isEmpty ? "heic" : ext))
        do { try data.write(to: url, options: .atomic); return url }
        catch { return nil }
    }

    private func shareResult() {
        guard let url = resultFileURL() else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            av.popoverPresentationController?.sourceView = root.view
            root.present(av, animated: true)
        }
    }

    private func saveToLibrary() {
        guard let url = resultFileURL() else { return }
        PhotoLib.requestAddAccess { ok in
            guard ok else { self.message = "未授权相册访问。"; return }
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, fileURL: url, options: nil)
            } completionHandler: { success, err in
                DispatchQueue.main.async {
                    self.message = success ? "已保存到相册。" : "保存失败：\(err?.localizedDescription ?? "未知错误")"
                }
            }
        }
    }
}

/// 选图：接受 HEIC/JPEG，读出持久化后的 Data 与文件名。
struct ExifPhotoPicker: UIViewControllerRepresentable {
    let onPick: (Data, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration(photoLibrary: .shared())
        cfg.filter = .images
        cfg.selectionLimit = 1
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (Data, String) -> Void
        init(onPick: @escaping (Data, String) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let r = results.first else { return }
            let provider = r.itemProvider
            let type = provider.hasItemConformingToTypeIdentifier(UTType.heic.identifier)
                ? UTType.heic.identifier : UTType.image.identifier
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url = url, let data = try? Data(contentsOf: url) else { return }
                DispatchQueue.main.async { self.onPick(data, url.lastPathComponent) }
            }
        }
    }
}
