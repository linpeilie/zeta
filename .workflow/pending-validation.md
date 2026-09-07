# 未完成事项

更新于 2026-09-07。本页从既有记录汇总，文档清理不代表这些检查已执行。

| 事项 | 状态与下一步 | 证据来源 |
| --- | --- | --- |
| 应用状态改造最终集成 | 代码阶段完成；复核生产组合入口并在最终基线跑完整门禁 | [阶段索引](plan/2026-09-05-lib-cohesion/00-index.md#待完成的集成验收) |
| Codex experimental Plan | 原记录 18/19，缺少 `turn/plan/updated`；需真实协议核验 | [WP-E](plan/2026-09-04-provider-plugin-packages/08-wpe-validation.md) |
| Claude 凭据读取 | 三平台真实账号读取仍待执行 | [凭据入口](feature/2026-09-05-claude-credentials/00-validation.md) |
| Claude 登录续期 | 真实远端轮换、Windows 权限与原子替换、Linux 原生文件系统检查待执行 | [续期记录](feature/2026-09-05-claude-token-refresh/00-validation.md) |
| 桌面生命周期 | 真实 CLI、macOS 手工退出、原生目录打开及 Windows/Linux Profile 待执行 | [首页检测](refactor/2026-09-06-home-detection/00-validation.md)、[会话所有权](refactor/2026-09-06-conversation-owner/00-validation.md) |
| 发布端到端 | 需按目标版本验证完整附件、安装、启动和 macOS 安装窗口；旧指南中指定的临时 Tag 不再作为下一版本指令 | [发版指南](../docs/zh/release/release_guide.md) |
| 历史分页 | 已跳过，未排期；重新评估需性能证据 | [评估记录](plan/2026-09-03-agent-conversation-ui-rendering/05-wp5-history-pagination.md) |
| Markdown P2 | 三项已跳过，未排期；分别确认需求或性能证据 | [决定](plan/2026-09-03-agent-conversation-ui-rendering/06-wp6-markdown-vendor.md) |

关闭事项时补充日期、提交、平台、工具版本、实际结果和对应记录链接。没有设备或账号时写明未执行，不能填“通过”。
