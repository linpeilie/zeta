# Cursor Agent 退役历史说明

最后更新：2026-07-17

Cursor 已从 Zeta 的 provider catalog、设置、Agent 管理、运行时组合、进程启动、deep link、
workspace 恢复和历史加载路径中退役。退役完成时的活跃 Provider 是 Codex 与 Grok；
这是历史快照，不代表今天的 Provider 清单。

## 最终清退状态

- 当前 Provider 枚举、配置 codec、catalog、UI、factory、恢复、测试与 fixture 均不含 Cursor。
- 不为未发布 schema 保留旧 provider id、kind、decode/fallback 或 unavailable 展示。
- 当前代码不读取、迁移、改写或删除 Cursor CLI 私有数据。

## 历史证据

- `plan/cursor_acp_integration_plan.md`（已随 `plan/` 目录移除，仅存于 Git 历史） 仅记录删除前实现背景。
- [历史发布门禁](cursor_acp_release_validation.md) 记录退役前的验证要求与缺口。
- 删除前的 synthetic fixture 仅存于 Git 历史，不代表真实协议或当前支持。

## 未来重新支持

任何重新支持都必须另立方案，采集真实且脱敏的 live/replay 协议 fixture，重新完成
catalog、配置、恢复、factory、进程、数据边界和跨平台门禁；不得直接恢复已删除实现或把
synthetic fixture 当作协议契约。
