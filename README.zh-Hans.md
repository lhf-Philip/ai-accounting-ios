# AI 记账 (iOS + Android)

语言： [English](./README.md) | [繁體中文](./README.zh-Hant.md) | **简体中文**

AI 记账是个人财务管理 App，支持多币种记账、账户管理、预算、代垫、债务管理与备份。

- iOS 是产品 source of truth，也是主要 SwiftUI + SwiftData 实现。
- Android 是持续维护中的 Kotlin + Jetpack Compose 版本，按 iOS 的信息架构与功能语义对齐。
- Android 保留一个平台专属能力：桌面小组件。

## 核心功能

- 多账户记账：现金 / 银行 / 信用卡 / 借贷账户
- 多币种收入、支出、转账、代垫与债务流程
- 完整可编辑转账流程（含多腿转账分组与同账户跨币种转账）
- 代垫追踪、还款管理与结算中心
- 债务管理：借入、还款、免除债务
- 收入/支出报表（分类与标签钻取）
- 预算、超支提醒与 AI 预算建议
- 数据健康检查、JSON 备份/还原、WebDAV 远程备份、CSV 导出
- AI 小票扫描（用户自行填写 Gemini API Key）

## 平台状态

### iOS

- SwiftUI + SwiftData 版本，功能完整并持续迭代
- 维护四语：繁体中文、简体中文、英式英文、日文
- PR 会运行 iOS simulator build 与 string catalog 校验

### Android

- Kotlin + Jetpack Compose 版本，主页与核心财务流程已按 iOS 对齐
- Room 本地数据层、parity 测试向量、Android CI build / unit tests
- Android-only summary widget
- 对齐规格见 [`docs/specs/android-ios-parity.md`](./docs/specs/android-ios-parity.md)

## App 内使用教学

- 可在 `设置 > 使用教学` 打开。
- 首次使用 App 时，系统会自动显示教学页。

## 语言支持（iOS）

- 繁体中文（`zh-Hant`）
- 简体中文（`zh-Hans`）
- 英式英文（`en-GB`）
- 日文（`ja`）

## 技术栈

- iOS：SwiftUI、SwiftData、Charts、`generative-ai-swift`
- Android：Kotlin、Jetpack Compose、Room、WorkManager、Android widgets

## 环境要求

- macOS
- iOS：Xcode（已在 `Xcode 26.2` 验证）
- Android：JDK 17+ 与 Android SDK

## 快速开始

### iOS

1. 用 Xcode 打开 `AI 記帳.xcodeproj`
2. 选择 Simulator 或 iPhone 设备
3. 使用 `Cmd + R` 运行

### Android

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

APK 构建流程：[`docs/ANDROID_APK_BUILD.md`](./docs/ANDROID_APK_BUILD.md)

## CI

GitHub Actions 会在 `push` / `pull_request` 到 `main` 时执行：

- `iOS CI`：`Localizable.xcstrings` 校验 + iOS build
- `Android CI`：`:app:assembleDebug` + `:app:testDebugUnitTest`

## 数据兼容性

- 跨平台数据契约：[`docs/specs/data-model.md`](./docs/specs/data-model.md)
- 跨平台 parity 测试向量：[`docs/specs/parity-test-vectors.md`](./docs/specs/parity-test-vectors.md)
- 手动验证矩阵：[`docs/VALIDATION_MATRIX.md`](./docs/VALIDATION_MATRIX.md)

## 隐私与密钥

- Gemini API Key 由用户在 App 内自行设置
- API Key 存储在 iOS Keychain 与 Android secure storage
- 仓库不包含任何默认 API Key、token、私人备份或私钥

## 开源文件

- 许可证： [MIT](./LICENSE)
- 安全策略： [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | [简体中文](./SECURITY.zh-Hans.md)
- 贡献指南： [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)
- Pull Request 模板： [`.github/pull_request_template.md`](./.github/pull_request_template.md)
- CI 检查清单： [`docs/CI_CHECKLIST.md`](./docs/CI_CHECKLIST.md)
- Android APK 构建流程： [`docs/ANDROID_APK_BUILD.md`](./docs/ANDROID_APK_BUILD.md)

## 免责声明

本项目为个人财务管理工具，请自行评估使用风险并定期备份数据。
