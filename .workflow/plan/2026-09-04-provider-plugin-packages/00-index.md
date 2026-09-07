# Provider 拆包记录

任务日期：2026-09-04—2026-09-05。原记录状态：WP-A 至 WP-E 的代码和自动化阶段已完成。真实协议与平台限制见下文，不等同于全部实机验收通过。

## 结果

- api 保存中立装配契约，sdk 保存共享机制与独立测试入口。
- Codex、Grok、Claude Code 分别进入插件包，通过 manifest 登记。
- 管理与用量由插件贡献，宿主消费中立端口；过渡 import 已移除。
- 隔离守卫和 CI 包矩阵覆盖自动发现的内部包。

现行规范见[工程规范 §2.1](../../../docs/zh/architecture/engineering_standards.md#21-provider-插件包边界)，新增接入见[开发者指南](../../../docs/zh/development/developer_guide.md#新增-provider-插件)。不再依据旧拆包清单改代码。

## 历史验证

| 阶段 | 记录 |
| --- | --- |
| WP-C 拆包 | [实现与验证](06-wpc-validation.md) |
| WP-D 管理与用量贡献 | [实现与验证](07-wpd-validation.md) |
| WP-E 守卫与 CI | [实现与验证](08-wpe-validation.md) |

安装指引例外的原决策保留在 [WP-D §3.6](04-wpd-app-contributions.md#36-安装指引例外)。约束正文已归入工程规范。

Codex 在 Darwin/x86_64、0.144.5 的 stable 冒烟原记录为 18/18；experimental Plan 为 18/19，缺少 `turn/plan/updated`。这项差异仍需核验，其他平台也不能据此记为通过。本次清理没有重新运行冒烟。
