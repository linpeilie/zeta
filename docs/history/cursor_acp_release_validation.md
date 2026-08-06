# Cursor ACP 历史发布门禁

最后更新：2026-07-17

Cursor 已退役，相关运行实现与真实 CLI smoke 工具已经删除。本文只保留删除前发布门禁的
历史结论，不代表当前支持。

## 删除前门禁结论

- 单元测试曾覆盖 CLI 定位、进程参数、ACP provider、session replay、诊断、最小索引和
  Agent 管理 repository。
- synthetic fixture 只能冻结 fake/test 形状，无法证明真实 Cursor 的 messageId、eventId、
  delta/snapshot 或 replay 语义。
- 缺少跨版本、跨平台的真实协议证据，因此不能把 Cursor 提升为稳定 Provider，也不能为其
  实施新的 stream identity 规则。

## 退役后的发布门禁

- Cursor 不出现在 catalog、设置、创建会话或 Agent 管理入口。
- app 组合、bootstrap、deep link、workspace 恢复和 provider factory 不创建 Cursor 运行时。
- 旧配置可容错解码，显示 unavailable，并在不保存配置的情况下安全回退。
- process spy 证明不会启动 Cursor；数据边界回归证明受保护目录、遗留索引和旧配置不变。
- Cursor 专属运行实现与测试删除；共享 ACP decoder、mapper 和 JSON-RPC transport 继续由
  Grok/Codex 回归测试保护。

详细执行记录见 `plan/agent_stream_identity_adaptation_plan.md` 的 Phase 3。
