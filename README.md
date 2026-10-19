# JpegToHeic

iOS 双功能小工具：**JPEG → HEIC 格式转换** + **给 HEIC 加摄影风格调色盘**。

## 功能一：格式转换（JPEG → HEIC）

- **最高质量档**：以 HEIC 最高码率编码，肉眼零损失、画质清晰度保留（文件通常比原图更大）
- **高质量有损**：肉眼几乎无差的压缩，体积更小
- 支持批量选择、保存到相册、分享到文件/隔空投送
- 全程在 iPhone 本地处理，照片不上传任何服务器

### 使用
1. 打开 App →「格式转换」→「选择照片」多选 JPEG
2. 选择模式：最高质量 / 高质量有损（可调质量）
3. 点「开始转换」→ 每个结果会显示 原大小 → HEIC 大小
4. 「保存到相册」或「分享」导出 HEIC 文件

> 说明：最高质量档以 HEIC 最高码率编码、肉眼零损失，但对本身已压缩过的高质量 JPEG，HEIC 文件通常会更大（正常现象）。若想体积更小，用「高质量有损」。

## 功能二：调色盘移植（给 HEIC 加摄影风格）

把 iPhone 相机拍摄的 HEIC 照片补上摄影风格元数据，照片 App 编辑时会出现**调色板**；iOS 27 上还有**质感/颗粒**。

### 使用
1. 打开 App →「调色盘」→「选择 HEIC」
2. 选择 **iPhone 相机拍摄的 HEIC 原图**（不能是 JPEG 或转码副本）
3. 状态显示「可移植」→ 点「移植调色盘」
4. 完成后建议「分享 → 存储到文件」传输（避免照片图库重新编码丢失数据）

> **重要限制**：调色盘移植只支持 iPhone 相机拍摄的 HEIC（自带 HDR 增益图 + 分块结构）。从 JPEG 用 ImageIO 新转出的 HEIC 缺少这些结构，**无法**移植——这是 Apple 相机 HEIC 的私有结构，非本工具能补齐。本仓库集成的是 [nathanatgit/Shalielie](https://github.com/nathanatgit/Shalielie) 官方 Swift 移植核心（StylePortCore，MIT）。

## 自签名安装（本仓库产出未签名 IPA）

本仓库的 GitHub Actions 默认构建**未签名 IPA**（`JpegToHeic-<版本>-unsigned.ipa`），需要你自己签名后安装：

1. 到仓库 **Actions / Releases** 下载最新 `JpegToHeic-<版本>-unsigned.ipa`
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
./scripts/build_ipa.sh      # 产出 build/JpegToHeic-<版本>-unsigned.ipa
```
