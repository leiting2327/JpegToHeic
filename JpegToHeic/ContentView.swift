import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// 一个待转换的 JPEG 条目
struct ImageItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var preview: UIImage?
    var result: HeicConverter.Result?   // 转换成功后不为空
    var error: String?
    var isConverting = false
}

struct ContentView: View {
    @State private var items: [ImageItem] = []
    @State private var isPickerPresented = false
    @State private var lossless = true
    @State private var quality: Float = 0.95
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsCard
                    actionCard
                    if !items.isEmpty { resultList }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("JPEG → HEIC")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("选择照片") { isPickerPresented = true }
                        .disabled(isWorking)
                }
            }
            .sheet(isPresented: $isPickerPresented) {
                PhotoPicker { picked in loadPicked(picked) }
                    .ignoresSafeArea()
            }
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    // MARK: - 设置

    private var settingsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("转换设置").font(.headline)
                Picker("模式", selection: $lossless) {
                    Text("无损（像素100%保留）").tag(true)
                    Text("高质量有损").tag(false)
                }
                .pickerStyle(.segmented)

                if !lossless {
                    VStack(alignment: .leading, spacing: 4) {
                        Slider(value: $quality, in: 0.5...1.0)
                        Text(String(format: "质量：%.0f%%", quality * 100))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Text("无损模式完全保留画质清晰度，文件通常更大；有损高质量在肉眼几乎无差的前提下体积更小。")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private var actionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("操作").font(.headline)
                Button {
                    convertAll()
                } label: {
                    HStack {
                        Spacer()
                        if isWorking {
                            ProgressView().padding(.trailing, 6)
                        }
                        Text("开始转换（\(items.count) 张）")
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(items.isEmpty || isWorking || items.allSatisfy { $0.result != nil })

                HStack(spacing: 12) {
                    Button {
                        saveConvertedToLibrary()
                    } label: {
                        Label("保存到相册", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasResults)

                    Button {
                        shareConverted()
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasResults)
                }
            }
        }
    }

    private var resultList: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("转换结果").font(.headline)
                ForEach(items) { item in
                    row(for: item)
                        .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func row(for item: ImageItem) -> some View {
        HStack(spacing: 12) {
            if let preview = item.preview {
                Image(uiImage: preview)
                    .resizable().scaledToFill()
                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "photo"))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline).lineLimit(1)
                if let result = item.result {
                    Text(result.sizeDescription).font(.caption).foregroundColor(.secondary)
                    let pct = result.savedPercent
                    Text(String(format: "较原图 %.1f%% %@", abs(pct), pct >= 0 ? "小" : "大"))
                        .font(.caption)
                        .foregroundColor(pct >= 0 ? .green : .orange)
                } else if let err = item.error {
                    Text(err).font(.caption).foregroundColor(.red)
                } else if item.isConverting {
                    HStack(spacing: 6) { ProgressView(); Text("转换中…").font(.caption).foregroundColor(.secondary) }
                }
            }
            Spacer()
        }
    }

    private var hasResults: Bool {
        items.contains { $0.result != nil }
    }

    // MARK: - 加载与转换

    private func loadPicked(_ results: [PHPickerResult]) {
        for result in results {
            let provider = result.itemProvider
            guard provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) ||
                  provider.hasItemConformingToTypeIdentifier(UTType.heic.identifier) else { continue }
            let type = provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier)
                ? UTType.jpeg.identifier : UTType.heic.identifier
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, err in
                guard let url = url, err == nil else { return }
                let name = url.lastPathComponent
                let preview = UIImage(contentsOfFile: url.path)
                DispatchQueue.main.async {
                    self.items.append(ImageItem(name: name, url: url, preview: preview))
                }
            }
        }
    }

    private func convertAll() {
        isWorking = true
        let group = DispatchGroup()
        for i in items.indices {
            let jpegURL = items[i].url
            setItem(i) { $0.isConverting = true; $0.error = nil }
            group.enter()
            let outURL = tempOutputURL(for: items[i].name)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try HeicConverter.convert(
                        jpegURL: jpegURL, outputURL: outURL,
                        quality: self.quality, lossless: self.lossless
                    )
                    DispatchQueue.main.async {
                        self.setItem(i) { $0.result = result; $0.isConverting = false }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.setItem(i) { $0.error = error.localizedDescription; $0.isConverting = false }
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            isWorking = false
        }
    }

    /// 在主线程按索引修改一个条目（触发视图更新）
    private func setItem(_ index: Int, _ mutate: (inout ImageItem) -> Void) {
        guard items.indices.contains(index) else { return }
        var it = items[index]
        mutate(&it)
        items[index] = it
    }

    private func tempOutputURL(for name: String) -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let heicName = (name as NSString).deletingPathExtension + ".heic"
        return base.appendingPathComponent(heicName)
    }

    private func saveConvertedToLibrary() {
        let urls = items.compactMap { $0.result?.outputURL }
        guard !urls.isEmpty else { return }
        final class Counter { var value = 0 }
        let counter = Counter()
        let group = DispatchGroup()
        for u in urls {
            group.enter()
            HeicConverter.saveToPhotoLibrary(heicURL: u) { ok, _ in
                if ok { counter.value += 1 }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            message = counter.value > 0
                ? "已保存 \(counter.value) 张到相册。"
                : "未保存任何图片（可能未授权相册）。"
        }
    }

    private func shareConverted() {
        let urls = items.compactMap { $0.result?.outputURL }
        guard !urls.isEmpty else { return }
        let av = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            av.popoverPresentationController?.sourceView = root.view
            root.present(av, animated: true)
        }
    }
}

// MARK: - PHPicker 封装（兼容 iOS 15+）

struct PhotoPicker: UIViewControllerRepresentable {
    var onPicked: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0   // 0 = 不限数量
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            parent.onPicked(results)
        }
    }
}
