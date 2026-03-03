# AI 记账 (iOS + Android)

语言： [English](./README.md) | [繁體中文](./README.zh-Hant.md) | **简体中文**

AI 记账是个人财务管理项目。

- iOS 版本是当前主线，功能完整并持续迭代。
- Android 版本目前处于骨架阶段（Jetpack Compose），用于后续与 iOS 对齐。

## iOS 主要功能

- 多账户记账：现金 / 银行 / 信用卡 / 借贷账户
- 多币种交易：每笔交易可使用独立币种
- 转账流程支持完整编辑（含多腿转账分组）
- 代垫追踪与还款管理
- 收入/支出报表（分类与标签钻取）
- JSON 全量备份/还原、CSV 导出
- AI 小票扫描（可选填写 Gemini API Key）

## Android 状态（骨架）

- Compose app shell
- Widget stub（`SummaryWidgetProvider`）
- Unit test scaffold
- Android CI baseline

详见：`android/README.md`

## App 内使用教学（iOS）

- 可在 `设置 > 使用教学` 打开。
- 首次使用 App 时，系统会自动显示教学页。

## 语言支持（iOS）

- 繁体中文（`zh-Hant`）
- 简体中文（`zh-Hans`）
- 英式英文（`en-GB`）
- 日文（`ja`）

## 技术栈

- iOS：SwiftUI、SwiftData、Charts、`generative-ai-swift`
- Android：Kotlin、Jetpack Compose（骨架阶段）

## 环境要求

- macOS
- iOS：Xcode（已在 `Xcode 26.2` 验证）
- Android：JDK 17+ 与 Android SDK

## 快速开始

### iOS

1. 用 Xcode 打开 `AI 記帳.xcodeproj`
2. 选择 Simulator 或 iPhone 设备
3. 使用 `Cmd + R` 运行

### Android（骨架）

```bash
gradle -p android :app:assembleDebug
gradle -p android :app:testDebugUnitTest
```

## CI

GitHub Actions 会在 `push` / `pull_request` 到 `main` 时执行：

- `iOS CI`：`Localizable.xcstrings` 校验 + iOS build
- `Android CI`：`:app:assembleDebug` + `:app:testDebugUnitTest`

## 数据兼容性

- 跨平台数据契约：`docs/specs/data-model.md`
- 跨平台 parity 测试向量：`docs/specs/parity-test-vectors.md`

## 隐私与密钥

- Gemini API Key 由用户在 App 内自行设置
- API Key 存储在 iOS Keychain（不会写入仓库）
- 仓库不包含任何默认 API Key、token 或私钥

## 开源文件

- 许可证： [MIT](./LICENSE)
- 安全策略： [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | [简体中文](./SECURITY.zh-Hans.md)
- 贡献指南： [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)
- Pull Request 模板： [`.github/pull_request_template.md`](./.github/pull_request_template.md)
- CI 检查清单： [`docs/CI_CHECKLIST.md`](./docs/CI_CHECKLIST.md)

## 免责声明

本项目为个人财务管理工具，请自行评估使用风险并定期备份数据。
