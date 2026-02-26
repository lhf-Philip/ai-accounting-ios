# AI 记账 (AI Accounting iOS)

语言： [English](./README.md) | [繁體中文](./README.zh-Hant.md) | **简体中文**

AI 记账是一个使用 SwiftUI + SwiftData 开发的 iOS 个人记账 App，支持多币种、转账、借贷、报表分析、备份还原与 AI 小票扫描。

## 主要功能

- 多账户记账：现金 / 银行 / 信用卡等账户类型
- 多币种交易：每笔交易可使用独立币种
- 转账与借贷流程：包含正负号一致性与双边交易联动
- 报表分析：按分类 / 标签查看支出结构
- 快捷记账：快速记录常用交易
- 备份与还原：JSON 全量备份、CSV 导出
- AI 小票扫描：可选填 Gemini API Key 启用

## 语言支持

- 繁体中文（`zh-Hant`）
- 简体中文（`zh-Hans`）
- 英式英文（`en-GB`）
- 日文（`ja`）

## 技术栈

- SwiftUI
- SwiftData
- Charts
- Google Generative AI Swift SDK（`generative-ai-swift`）

## 环境要求

- macOS
- Xcode（已在 `Xcode 26.2` 验证）
- iOS Simulator 或真机

## 快速开始

1. Clone 仓库
2. 用 Xcode 打开 `AI 記帳.xcodeproj`
3. 选择 Simulator 或 iPhone 设备
4. 使用 `Cmd + R` 运行

## CI

GitHub Actions 会在 `push` / `pull_request` 到 `main` 时执行：

- `Localizable.xcstrings` 结构校验
- iOS 项目 build 检查

## 隐私与密钥

- Gemini API Key 由用户在 App 内自行设置
- API Key 存储在 iOS Keychain（不会写入仓库）
- 仓库不包含任何默认 API Key、token 或私钥

## 数据兼容性

- 从 `2026-02-24` 快照版（`4417c97`）到当前版本无破坏性数据模型迁移
- 旧版 JSON 备份可正常导入

## 开源文件

- 许可证： [MIT](./LICENSE)
- 安全策略： [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | [简体中文](./SECURITY.zh-Hans.md)
- 贡献指南： [English](./CONTRIBUTING.md) | [繁體中文](./CONTRIBUTING.zh-Hant.md) | [简体中文](./CONTRIBUTING.zh-Hans.md)
- Pull Request 模板： [`.github/pull_request_template.md`](./.github/pull_request_template.md)

## 免责声明

本项目为个人财务管理工具，请自行评估使用风险并定期备份数据。
