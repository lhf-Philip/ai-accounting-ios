# 安全策略

语言： [English](./SECURITY.md) | [繁體中文](./SECURITY.zh-Hant.md) | **简体中文**

## 支持版本

当前维护中的主要版本：`1.x`

## 漏洞上报

请不要公开发布可直接利用的漏洞细节。

建议流程：

1. 优先使用 GitHub Private Vulnerability Reporting（如已启用）
2. 或先创建标题含 `[SECURITY]` 的 issue（不附 exploit 细节）
3. 维护者联系后再私下提供完整细节

## 敏感数据规则

- 禁止提交 API keys、access tokens、private keys
- 禁止提交包含个人信息的真实备份数据（JSON/CSV）
- 若发现敏感数据泄露，请立即轮换凭证并通知维护者
