# Cursor Agent 退役历史说明

最后更新：2026-07-17

Cursor 已从 Zeta 的 provider catalog、设置、Agent 管理、运行时组合、进程启动、deep link、
workspace 恢复和历史加载路径中退役。当前活跃 Provider 只有 Codex 与 Grok。

## 当前兼容行为

- 旧 `cursor` provider id 与 `cursorAcp` kind 仍可容错解码。
- 最后选择 Cursor 的旧配置会显示 unavailable，并只在内存中安全回退到已启用的 Provider。
- factory 对 Cursor 配置始终 fail-closed，不会创建 provider 或启动进程。
- 遗留 Cursor thread 可以保留不可用/只读说明，但不能恢复到 Cursor 运行时。
- Zeta 不读取、迁移、改写或删除 `~/.cursor`、项目 `.cursor`、旧 Provider 配置或
  `~/.zeta/state/cursor_sessions.json`。

## 历史证据

- `plan/cursor_acp_integration_plan.md`（已随 `plan/` 目录移除，仅存于 Git 历史） 仅记录删除前实现背景。
- [历史发布门禁](cursor_acp_release_validation.md) 记录退役前的验证要求与缺口。
- `test/fixtures/agent_stream_identity/` 中的 Cursor JSON 是 synthetic fixture，只用于退役
  决策和删除前行为审计，不代表真实协议或当前支持。

## 未来重新支持

任何重新支持都必须另立方案，采集真实且脱敏的 live/replay 协议 fixture，重新完成
catalog、配置、恢复、factory、进程、数据边界和跨平台门禁；不得直接恢复已删除实现或把
synthetic fixture 当作协议契约。
