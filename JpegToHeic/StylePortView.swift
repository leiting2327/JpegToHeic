import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Photos
import UIKit

/// 「调色盘移植」功能：给 iPhone 相机拍摄的 HEIC 照片补上摄影风格（Photographic Styles）
/// 与 iOS 27 质感/颗粒，让编辑照片时出现调色板。
/// 说明：移植只支持 iPhone 相机拍摄的 HEIC（自带 HDR 增益图 + 分块结构）。
struct StylePortView: View {
    @State private var isPickerPresented = false
    @State private var pickedName = ""
    @State private var pickedData: Data?
    @State private var eligibility: StylePorter.Eligibility?
    @State private var resultData: Data?
    @State private var resultMode = ""
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    infoCard
                    if pickedData != nil { photoCard }
                    if resultData != nil { resultCard }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("调色盘移植")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("选择 HEIC") { isPickerPresented = true }
                        .disabled(isWorking)
                }
            }
            .sheet(isPresented: $isPickerPresented) {
                PhotoPicker { picked in loadHeic(picked) }
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
                Label("摄影风格调色板移植", systemImage: "paintpalette.fill").font(.headline)
                Text("给 iPhone 相机拍摄的 HEIC 照片补上摄影风格元数据，照片 App 编辑时会出现调色板；iOS 27 上还有质感/颗粒。")
                    .font(.footnote).foregroundColor(.secondary)
                Text("只支持 iPhone 相机拍摄的 HEIC 原图（自带 HDR 增益图+分块结构）。JPEG 或转码副本无法移植。")
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var photoCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("已选照片").font(.headline)
                Text(pickedName).font(.subheadline).lineLimit(1)
                if let el = eligibility {
                    Label(eligibilityText(el), systemImage: eligibilityIcon(el))
                        .font(.footnote)
                        .foregroundColor(eligibilityColor(el))
                }
                if eligibility == .port || eligibility == .addTexture {
                    Button {
                        port()
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView().padding(.trailing, 6) }
                            Text("移植调色盘")
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                }
            }
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("移植完成").font(.headline).foregroundColor(.green)
                if !resultMode.isEmpty {
                    Text(resultMode).font(.footnote).foregroundColor(.secondary)
                }
                Text("建议通过「分享」→「存储到文件」传输，避免照片图库重新编码丢失数据。")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Button {
                        shareResult()
                    } label: {
                        Label("分享/存文件", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        saveToLibrary()
                    } label: {
                        Label("存相册", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - 选图与移植

    private func loadHeic(_ results: [PHPickerResult]) {
        guard let r = results.first else { return }
        let provider = r.itemProvider
        guard provider.hasItemConformingToTypeIdentifier(UTType.heic.identifier) else {
            message = "所选照片不是 HEIC。请选 iPhone 相机拍摄的 HEIC 原图。"
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.heic.identifier) { url, err in
            guard let url = url, err == nil,
                  let data = try? Data(contentsOf: url) else {
                DispatchQueue.main.async { self.message = "读取 HEIC 文件失败。" }
                return
            }
            let el = StylePorter.eligibility(of: data)
            DispatchQueue.main.async {
                self.pickedName = url.lastPathComponent
                self.pickedData = data
                self.eligibility = el
                self.resultData = nil
                self.resultMode = ""
            }
        }
    }

    private func port() {
        guard let data = pickedData else { return }
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try StylePorter().patch(
                    data,
                    options: StylePortOptions(analyzePhoto: true, texture: true, livePhoto: false)
                )
                DispatchQueue.main.async {
                    self.resultData = result.data
                    self.resultMode = modeText(result.report.mode, texture: result.report.addedTexture)
                    self.isWorking = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.message = "移植失败：\(error.localizedDescription)"
                    self.isWorking = false
                }
            }
        }
    }

    // MARK: - 输出

    private func resultFileURL() -> URL? {
        guard let data = resultData else { return nil }
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base.appendingPathComponent((pickedName as NSString).deletingPathExtension + "_PhotographicStyle.heic")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
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
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.message = "未授权相册访问。" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, fileURL: url, options: nil)
            } completionHandler: { ok, err in
                DispatchQueue.main.async {
                    self.message = ok ? "已保存到相册。" : "保存失败：\(err?.localizedDescription ?? "未知错误")"
                }
            }
        }
    }

    // MARK: - 文案

    private func eligibilityText(_ el: StylePorter.Eligibility) -> String {
        switch el {
        case .port: return "可移植摄影风格调色板"
        case .addTexture: return "已带风格，将添加质感/颗粒"
        case .alreadyStyled: return "已带风格与质感/颗粒，无需处理"
        case .unsupported: return "不支持的照片（需 iPhone 相机拍摄的 HEIC）"
        }
    }
    private func eligibilityIcon(_ el: StylePorter.Eligibility) -> String {
        switch el {
        case .port, .addTexture: return "checkmark.circle.fill"
        case .alreadyStyled: return "info.circle.fill"
        case .unsupported: return "xmark.octagon.fill"
        }
    }
    private func eligibilityColor(_ el: StylePorter.Eligibility) -> Color {
        switch el {
        case .port, .addTexture: return .green
        case .alreadyStyled: return .blue
        case .unsupported: return .red
        }
    }
    private func modeText(_ mode: StylePortReport.Mode, texture: Bool) -> String {
        var t = "模式：\(mode.rawValue)"
        if texture { t += " · 已加质感/颗粒" }
        return t
    }
}
