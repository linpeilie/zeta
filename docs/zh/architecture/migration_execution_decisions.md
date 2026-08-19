# 迁移执行决策日志

中文 | [English](../../en/architecture/migration_execution_decisions.md)

状态：**持续记录中**。本文记录架构基线冻结后，实施阶段出现的偏差、证据、决策与
影响。2026-08-19，项目所有者授权迁移 Agent 对后续决策采用风险最低、最符合既有架构
的建议方案并持续执行。

## 2026-08-19 — 步骤 10 桌面契约校正

**问题。** 脚手架级桌面 port 过窄，无法保留旧项目行为：字体缺少稳定 family identity；
文件选择与剪贴板 API 无法表达多图片/多文件；menu、window、attention 与系统文件管理器
操作缺少所需的类型化输入。

**证据。** 旧项目 macOS/Windows/Linux runner 与 app composition 已使用这些行为；同时
冻结规则仍禁止 Flutter/plugin 类型越过共享包边界。

**决策。** 经所有者逐项批准，只扩充 pure-Dart value contract；所有 plugin/channel
具体实现仍限制在 `lib/app/platform/`。使用结构化不可变值和可注入 facade，不暴露
plugin 类型。

**影响。** 步骤 10 在不把平台 IO 移入 Bloc/Presentation 的前提下保留行为。native
contract test 与 Windows Debug build 已验证结果；未改 Provider port。

## 2026-08-19 — 步骤 11 当前 schema 与失败语义

**问题。** 旧 Provider codec 同时接受 settings V1/V2、迁移权限字段，并在文件损坏时
静默返回默认值或空 cache/context。步骤 11 明确要求只支持当前 schema，并返回 typed
decode failure；共享层 `AgentProviderSettings.supportedVersions` 与
`AgentModelCatalogCacheStore` 注释仍保留旧语义。

**证据。** `AgentProviderSettings.supportedVersions` 为 `{1, 2}`，cache port 要求损坏或
不兼容内容返回空列表，与步骤 11 任务及包 API 契约直接冲突。

**决策。** 经所有者批准：Provider settings 只支持 V2；未知版本、非法 JSON、字段结构
错误、重复稳定 id、落盘 thread identity 不匹配均返回类型化解码失败。文件不存在仍是
正常首次运行状态（空列表或 `null`）。是否重建由上层决定，Data client 不自行恢复。
不持久化 active Provider 选择状态，也不新增或修改 Provider 方法签名。

**影响。** 共享契约注释与支持版本常量收敛到当前 schema。`agent_config_client` 失败关闭，
不做历史迁移或静默截断，使用原子替换，并排除 CLI locator、Controller 与选择状态。
