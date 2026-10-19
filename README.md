# JpegToHeic

把 JPEG 照片无损转成 HEIC（HEVC）的 iOS 小工具。

- **无损模式**：像素 100% 保留，画质清晰度零损失（文件通常比原图更大）
- **高质量有损**：肉眼几乎无差的压缩，体积更小
- 支持批量选择、保存到相册、分享到文件/隔空投送
- 全程在 iPhone 本地处理，照片不上传任何服务器

## 为什么转 HEIC

HEIC（H.265/HEVC）是比 JPEG 更高效的图片格式。如果你需要**在 iPhone 上编辑摄影风格调色盘 / 质感颗粒**（需 HEIC），或在 iOS 之外对相片做统一管理，转成 HEIC 很方便。

## 使用

1. 打开 App → 「选择照片」多选 JPEG
2. 选择模式：无损 / 高质量有损（可调质量）
3. 点「开始转换」→ 每个结果会显示 原大小 → HEIC 大小
4. 「保存到相册」或「分享」导出 HEIC 文件

> 说明：无损转换完全保留画质，但对本身已压缩过的高质量 JPEG，HEIC 文件通常会更大（这是无损的正常表现）。若想体积更小，用「高质量有损」。

## 自签名安装（本仓库产出未签名 IPA）

本仓库的 GitHub Actions 默认构建**未签名 IPA**（`JpegToHeic-unsigned.ipa`），需要你自己签名后安装：

1. 到仓库 **Actions / Releases** 下载最新 `JpegToHeic-unsigned.ipa`
2. 用你自己的证书签名：
   - Mac：`codesign -f -s "你的证书" Payload/JpegToHeic.app`，再重新压成 ipa
   - 或用爱思助手 / AltStore / Sideloadly 等工具导入证书安装
3. Bundle ID：`com.jpegtoheic.app`，签名描述文件需包含你的设备 UDID

### 用签名材料自动构建（可选）

在仓库 **Settings → Secrets and variables → Actions** 配置以下 Secret 后，Actions 会自动签名并产出可直装 IPA：

| Secret | 说明 |
|---|---|
| `CERTIFICATE_BASE64` | 你的开发证书 .p12 的 base64 |
| `P12_PASSWORD` | p12 密码 |
| `PROVISIONING_PROFILE_BASE64` | 描述文件 .mobileprovision 的 base64（需含你的设备 UDID） |

## 构建

```bash
brew install xcodegen
xcodegen generate
./scripts/build_ipa.sh      # 产出 build/JpegToHeic-unsigned.ipa
```
