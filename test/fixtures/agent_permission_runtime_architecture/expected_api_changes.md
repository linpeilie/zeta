# 阶段 A 预期 API / 编译变化清单

这些项目只记录目标契约，不在阶段 A 修改生产 API：

- domain 增加不可变 `AgentPermissionRequestSnapshot`，或由现有
  `AgentTurnConfiguration.permissionSelection` 明确承担同等请求快照语义。
- application 增加按 provider runtime identity/generation 与 threadId 隔离的
  permission state store；provider default 与 thread effective 使用不同字段。
- bundle 暴露中立 runtime permission state stream，使 Grok `runtime` scope 能广播给
  共享同一运行实例的所有 ViewModel。
- `AgentThreadSettingsUpdatedEvent` 只保留
  `AgentPermissionSelection? permissionSelection`；不得新增
  `approvalPolicy`、`sandboxPolicy`、`activePermissionProfileId`。
- data/config 增加 `AgentPermissionPreferenceMigrator`、Codex/Grok 专属实现与 registry；
  domain `AgentProviderConfig` 不再解释 provider-specific legacy 字段。
