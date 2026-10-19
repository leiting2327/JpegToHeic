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
    @State private var pairedVideo: PairedVideo?
    @State private var liveStatus = ""

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
                Text("给 iPhone 相机拍摄的 HEIC 照片补上摄影风格元数据，照片 App 编辑时会出现调色板；iOS 27 上还有质感/颗粒。移植后存相册会自动保留实况照片。")
                    .font(.footnote).foregroundColor(.secondary)
                Text("只支持 iPhone 相机拍摄的 HEIC 原图（自带 HDR 增益图+分块结构）。JPEG 或转码副本无法移植。首次会请求相册访问，用于联动实况视频。")
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
                if !liveStatus.isEmpty {
                    Label(liveStatus, systemImage: pairedVideo != nil ? "livephoto" : "photo")
                        .font(.footnote).foregroundColor(pairedVideo != nil ? .green : .secondary)
                }
                Text("「存相册」会自动保留实况（含风格化视频轨道）；「分享」用于传到文件。")
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
        pairedVideo = nil
        liveStatus = ""
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try StylePorter().patch(
                    data,
                    options: StylePortOptions(analyzePhoto: true, texture: true, livePhoto: true)
                )
                DispatchQueue.main.async {
                    self.resultData = result.data
                    self.resultMode = modeText(result.report.mode, texture: result.report.addedTexture)
                    self.isWorking = false
                    self.lookupLiveVideo()
                }
            } catch {
                DispatchQueue.main.async {
                    self.message = "移植失败：\(error.localizedDescription)"
                    self.isWorking = false
                }
            }
        }
    }

    /// 移植完成后，反查原照片的实况视频并风格化，以便存回相册时仍为实况。
    private func lookupLiveVideo() {
        guard let data = resultData else { return }
        liveStatus = "正在检测是否为实况照片…"
        PhotoLib.requestReadAccess { granted in
            guard granted else {
                self.liveStatus = "（未授权读取相册，按静态照片处理）"
                return
            }
            PhotoLib.findPairedVideo(forHEIC: data) { pv in
                guard let pv = pv else {
                    DispatchQueue.main.async {
                        self.liveStatus = "静态照片（未检测到配对实况视频）"
                        self.pairedVideo = nil
                    }
                    return
                }
                DispatchQueue.main.async { self.liveStatus = "检测到实况视频，正在处理视频轨道…" }
                Task.detached {
                    do {
                        let outDir = try TempFiles.newDir()
                        let styled = outDir.appendingPathComponent("styled.mov")
                        if #available(iOS 16, *) {
                            try await LivePhotoStyler.style(pv.url, to: styled, texture: true)
                            DispatchQueue.main.async {
                                self.pairedVideo = PairedVideo(url: styled,
                                                               filename: pv.filename,
                                                               typeIdentifier: pv.typeIdentifier)
                                self.liveStatus = "实况照片已就绪（含风格化视频）"
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.liveStatus = "系统低于 iOS 16，仅移植静态图"
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.liveStatus = "视频轨道处理失败（静态图仍可用）：\(error.localizedDescription)"
                        }
                    }
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
        let video = pairedVideo
        PhotoLib.savePair(photoURL: url, photoName: pickedName, video: video) { res in
            DispatchQueue.main.async {
                switch res {
                case .success:
                    self.message = video != nil ? "已保存为实况照片（含风格调色盘）。" : "已保存到相册。"
                case .failure(let e):
                    self.message = "保存失败：\(e.localizedDescription)"
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
