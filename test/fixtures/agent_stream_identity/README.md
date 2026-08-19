# Agent stream identity Phase 0 fixtures

本目录冻结流式身份整改前的输入形状、版本证据和已知未知项。Fixture 只描述
Provider 输入，不承诺 Phase 1 以后生成的规范化 `entryId`。

## 版本与来源

| Provider | Fixture 基线 | 本机版本证据 | 来源等级 |
|----------|--------------|--------------|----------|
| Grok | `0.2.101` ACP redacted shape | `grok 0.2.102 (ab5ebf69ac)` | 现有脱敏抓取形状 + 当前测试的脱敏合成 |
| Codex | `0.144.1` stable schema | `codex-cli 0.144.1` | 版本匹配 stable schema + 当前 provider 测试 |

机器可读的完整索引见 `manifest.json`。场景覆盖：

- Grok：text → tool start/update → text、thought → tool → thought、重复 tool
  update 原地更新、turn completed，以及 live/history 完整 canonical signature。
- Codex：agentMessage delta、item/completed、agentMessage item →
  commandExecution item → agentMessage item。

## 脱敏约束

- 不保存 prompt 正文；用户输入只允许 `[PROMPT_REDACTED]` 标记。
- 不保存凭据、认证字段、token、真实路径或用户文件内容。
- agent/reasoning/tool/command/output 文本全部使用大写方括号占位符。
- session、turn、message、item、tool 和 event id 均为人工占位值。
- `<WORKSPACE_REDACTED>` 不是路径，只用于保留 schema 必需字段的位置。

## 证据记录

- `baseline_report.md`：迁移前 mapper、provider、history、EventBuffer 和
  TimelineStore 测试结果与当前行为。
- `codex_stable_schema_evidence.md`：Codex `0.144.1` stable schema 证据。
