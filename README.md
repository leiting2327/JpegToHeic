# JpegToHeic

> **永久免费开源项目**。本工具完全免费、无广告、无内购、不上传任何数据，永久免费开放使用。
> 全程在 iPhone 本地处理，照片不出设备。

iOS 三功能小工具：**JPEG → HEIC 格式转换** + **给 HEIC 加摄影风格调色盘（保留实况）** + **修改照片元数据（设备/位置）**。

## 功能

### 一、格式转换（JPEG → HEIC）
- 最高质量档：HEIC 最高码率编码，肉眼零损失、保留画质清晰度
- 高质量有损：肉眼几乎无差的压缩，体积更小
- 支持批量选择、保存到相册、分享到文件/隔空投送

### 二、调色盘移植（给 HEIC 加摄影风格）
- 给 iPhone 相机拍摄的 HEIC 补上摄影风格元数据，照片 App 编辑时出现**调色板**；iOS 27 还有**质感/颗粒**
- **保留实况**：移植后存相册会自动联动原照片的实况视频，移植完仍是实况照片
- 只支持 iPhone 相机拍摄的 HEIC 原图（自带 HDR 增益图 + 分块结构）；JPEG 或转码副本无法移植

### 三、元数据修改
- **拍摄设备**：下拉选择苹果全系机型（iPhone 6 → 18 Pro Max），自动填 Make=Apple
- **拍摄位置**：搜索地名自动定位，写入 GPS；也可勾选「位置不变」保留原位置
- 只改元数据，不重新压缩画面

## 自签名安装（未签名 IPA）

本项目通过 GitHub Actions 构建**未签名 IPA**，请到 [Releases](../../releases) 下载最新 `JpegToHeic-<版本>-unsigned.ipa`，用你自己的证书签名后安装（AltStore / Sideloadly / 爱思助手等均可）。

- Bundle ID：`com.jpegtoheic.app`
- 最低系统：iOS 15

## 开源与致谢

- 协议：[MIT License](LICENSE)，可自由使用、修改、分发
- 调色盘移植核心集成自 [nathanatgit/Shalielie](https://github.com/nathanatgit/Shalielie)（StylePortCore，MIT）

## 声明

本工具仅供个人学习与合法使用，修改照片元数据应遵守当地法律法规与平台规则，不得用于伪造证据或任何违法用途。使用风险自负。
