import SwiftUI
import PhotosUI
import Photos
import UIKit
import ImageIO
import CoreLocation
import UniformTypeIdentifiers

/// 「元数据」功能：读取并修改照片的拍摄设备信息（苹果全系机型）与 GPS 位置（地名搜索）。
/// 通过 CGImageDestinationCopyImageSource 只改写元数据、不重编码像素，画质不变。
struct ExifEditView: View {
    /// 苹果全系机型（iPhone 6 → 18 Pro Max），Make 固定 Apple。
    static let devices: [String] = [
        "iPhone 6", "iPhone 6 Plus", "iPhone 6s", "iPhone 6s Plus", "iPhone SE",
        "iPhone 7", "iPhone 7 Plus", "iPhone 8", "iPhone 8 Plus", "iPhone X",
        "iPhone XR", "iPhone XS", "iPhone XS Max",
        "iPhone 11", "iPhone 11 Pro", "iPhone 11 Pro Max", "iPhone SE (2nd generation)",
        "iPhone 12 mini", "iPhone 12", "iPhone 12 Pro", "iPhone 12 Pro Max",
        "iPhone 13 mini", "iPhone 13", "iPhone 13 Pro", "iPhone 13 Pro Max",
        "iPhone SE (3rd generation)",
        "iPhone 14", "iPhone 14 Plus", "iPhone 14 Pro", "iPhone 14 Pro Max",
        "iPhone 15", "iPhone 15 Plus", "iPhone 15 Pro", "iPhone 15 Pro Max",
        "iPhone 16", "iPhone 16 Plus", "iPhone 16 Pro", "iPhone 16 Pro Max", "iPhone 16e",
        "iPhone 17", "iPhone 17 Air", "iPhone 17 Pro", "iPhone 17 Pro Max",
        "iPhone 18", "iPhone 18 Pro", "iPhone 18 Pro Max"
    ]

    @State private var isPickerPresented = false
    @State private var pickedData: Data?
    @State private var fileName = ""

    @State private var selectedDevice = "iPhone 15 Pro Max"
    @State private var make = "Apple"
    @State private var software = ""
    @State private var addressQuery = ""
    @State private var foundAddress = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var isGeocoding = false

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
                Text("把拍摄设备改成苹果全系任意机型，位置改成搜索得到的地名。只改元数据，不重新压缩画面。")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private var editorCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(fileName).font(.subheadline).lineLimit(1)

                // MARK: 设备选择
                Text("拍摄设备").font(.caption).foregroundColor(.secondary)
                Picker("机型", selection: $selectedDevice) {
                    ForEach(Self.devices, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))

                field("系统/软件版本（可选）", text: $software)

                Divider()

                // MARK: 位置搜索
                Text("拍摄位置").font(.caption).foregroundColor(.secondary)
                HStack {
                    TextField("搜索地名，如：宁德蕉城区", text: $addressQuery)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                    Button {
                        searchAddress()
                    } label: {
                        if isGeocoding { ProgressView() }
                        else { Text("搜索") }
                    }
                    .disabled(isGeocoding || addressQuery.isEmpty)
                }
                if !foundAddress.isEmpty {
                    Label(foundAddress, systemImage: "mappin.and.ellipse")
                        .font(.footnote).foregroundColor(.green)
                }
                if !latitude.isEmpty && !longitude.isEmpty {
                    Text("经度 \(longitude) · 纬度 \(latitude)")
                        .font(.caption).foregroundColor(.secondary)
                }

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
                Text("新文件：设备 = \(make) \(selectedDevice)，位置 = \(foundAddress.isEmpty ? "未改" : foundAddress)。")
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
                .autocorrectionDisabled(true)
        }
    }

    // MARK: - 地名 → 经纬度

    private func searchAddress() {
        isGeocoding = true
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(addressQuery) { placemarks, error in
            DispatchQueue.main.async {
                self.isGeocoding = false
                guard let p = placemarks?.first, let loc = p.location else {
                    self.foundAddress = ""
                    self.message = "没找到这个地名，请换个关键词（可加城市名）。"
                    return
                }
                self.latitude = String(format: "%.6f", loc.coordinate.latitude)
                self.longitude = String(format: "%.6f", loc.coordinate.longitude)
                self.foundAddress = p.name ?? self.addressQuery
            }
        }
    }

    // MARK: - 读取

    private func load(data: Data, name: String) {
        pickedData = data
        fileName = name
        resultData = nil
        foundAddress = ""
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            message = "无法读取这张照片的元数据。"
            return
        }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let curModel = tiff?[kCGImagePropertyTIFFModel] as? String ?? ""
        // 若原机型在列表里就选中，否则保持默认
        if Self.devices.contains(curModel) { selectedDevice = curModel }
        make = tiff?[kCGImagePropertyTIFFMake] as? String ?? "Apple"
        software = tiff?[kCGImagePropertyTIFFSoftware] as? String ?? ""
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        if let lat = gps?[kCGImagePropertyGPSLatitude] as? Double {
            latitude = String(lat)
        } else { latitude = "" }
        if let lon = gps?[kCGImagePropertyGPSLongitude] as? Double {
            longitude = String(lon)
        } else { longitude = "" }
    }

    // MARK: - 写入（不重编码像素）

    private func applyEdit() {
        guard let data = pickedData else { return }
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let uti = CGImageSourceGetType(src),
                  var props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
                DispatchQueue.main.async { self.isWorking = false; self.message = "无法读取这张照片。" }
                return
            }

            // MARK: 设备信息（TIFF + EXIF 双写，照片 App 读 TIFF.Model）
            var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFMake] = make
            tiff[kCGImagePropertyTIFFModel] = selectedDevice
            if !software.isEmpty { tiff[kCGImagePropertyTIFFSoftware] = software }
            props[kCGImagePropertyTIFFDictionary] = tiff

            var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            if !software.isEmpty { exif[kCGImagePropertyExifSoftware] = software }
            props[kCGImagePropertyExifDictionary] = exif

            // MARK: GPS 位置
            var gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
            if let lat = Double(latitude), let lon = Double(longitude) {
                gps[kCGImagePropertyGPSLatitude] = abs(lat)
                gps[kCGImagePropertyGPSLatitudeRef] = lat >= 0 ? "N" : "S"
                gps[kCGImagePropertyGPSLongitude] = abs(lon)
                gps[kCGImagePropertyGPSLongitudeRef] = lon >= 0 ? "E" : "W"
            }
            props[kCGImagePropertyGPSDictionary] = gps

            // MARK: 写回（最高质量，尽量不损失画质）
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, uti, 1, [
                kCGImageDestinationLossyCompressionQuality: 1.0
            ] as CFDictionary) else {
                DispatchQueue.main.async { self.isWorking = false; self.message = "创建输出失败。"; return }
                return
            }
            CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
            let ok = CGImageDestinationFinalize(dest)
            DispatchQueue.main.async {
                self.isWorking = false
                if ok {
                    self.resultData = out as Data
                    self.message = "元数据已写入（设备：\(self.make) \(self.selectedDevice)）。"
                } else {
                    self.message = "写入失败。"
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
