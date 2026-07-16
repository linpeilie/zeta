# 开发记录

## 2026-07-16

### 侧栏 thread 执行中指示与详情 runtime 对齐

- 根因：`turn/completed` 等路径只走 `_flushStreamChangesNow`，未推
  `threadSnapshotListenable`，详情已 idle、列表仍 `isTurnRunning: true`。
- 修复：stream flush 同步 snapshot；turn 结束收束 sticky `active`；
  `syncRuntimeSnapshot` / `setThreadRunning(false)` 防御列表 `isBusy` 假阳性。
- 文档：`plan/agent_running_status_ux_plan.md` §2.5，以及 design / developer /
  project_memory 中的同步契约说明。

### Turn footer 展示本回合模型配置

- turn 终态 footer 在耗时与 token 之外，追加模型、思考程度（若有）、
  Fast（有且开启时）展示。
- 新增 `AgentTurnModelConfig`：历史 turn 从 `model` / `turnContext` 解析；
  live turn 在发送时冻结当前 composer 选择。
- 覆盖 domain 解析、timeline 挂载与 footer widget 测试。

### 移除 ActivityRail 选中侧边指示条

- `IdeActivityRail` 选中态不再绘制图标旁的 `accent` 指示条/小方块，仅保留中性
  `selectedSurface` 底色与 `accentForeground` 图标色。
- 删除 `IdeActivityRailIndicatorSide` 与 `indicatorSide` API；同步清理
  `IdeHome` 与 golden 测试中的传参。
- 更新统一设计系统实施文档与 UI 现代化蓝图中的状态视觉说明。

## 2026-07-09

### Codex app-server Phase 1 收尾

- Phase 1（核心流式体验）在适配计划中全部完成：reasoning / plan 流、回合
  diff、线程 waiting 状态、`serverRequest/resolved`、MCP 进度、模型改道与
  弃用提示、18 种 ThreadItem、`thread/unsubscribe`、本地图片输入。
- 同步刷新 `plan/codex_app_server_adaptation_plan.md` 顶部协议覆盖表与 §1
  已适配清单；更新 `docs/design_document.md` Agent 设计节。
- 真实 app-server 冒烟（`tool/smoke_codex_app_server.py`，CLI `0.142.5`）
  17/17 通过：`initialize`/`model/list`/`thread/start`、`turn/start` 接受
  `text`+`localImage` 且 item 通知可见图片、`thread/status/changed`、
  `thread/tokenUsage/updated`（`modelContextWindow=258400`）、agent 消息流、
  `turn/interrupt`→`interrupted`、`thread/unsubscribe`。本轮短回复未触发
  reasoning/plan/`turn/diff`（脚本记为 optional）；他端解决审批需双客户端，
  未在单进程冒烟中覆盖。
- 下一阶段：Phase 2（thread 管理与审批深化）。

### Codex app-server 协议同步机制

- 新增 `tool/gen_codex_schema.sh` 与 `tool/gen_codex_schema.ps1`，从本机 Codex CLI 导出 JSON Schema。
- 将 pinned 快照提交到 `third_party/codex_app_server_schema/`（当前 `0.144.5`），并排除键序不稳定的 v2 聚合文件。
- 新增 `docs/codex_app_server_protocol.md`，记录 pin 版本、再生命令与升级 diff 流程；同步开发者文档、设计文档与工程规范入口。
- Phase 0（协议对齐审计）在适配计划中全部完成。

## 2026-07-07

### 提炼重构后工程规范

- 扫描当前 `lib/` 结构，确认项目已经从宽泛分层演进为轻量 feature-sliced 架构。
- 在 `AGENTS.md` 中补充 app/core/features/ui 边界、依赖方向、状态拆分、协议隔离、持久化容错和 UI 性能约束。
- 新增 `docs/engineering_standards.md`，集中记录代码组织、状态编排、provider 协议边界、持久化、UI、文件系统和测试评审规范。
- 同步更新开发者文档、设计文档和项目记忆，修正过时的目录结构与 ProjectThreads controller/view model 分工。

## 2026-07-04

### 初始化项目文档

- 建立项目文档体系：产品需求文档、设计文档、开发者文档、开发记录和项目记忆。
- 梳理当前代码状态：Zeta 已从 Flutter 默认示例演进为桌面 Agent IDE 壳层。
- 记录当前核心能力：三栏 IDE 布局、本地项目文件树、Codex CLI provider、Agent thread 恢复、工具时间线、权限审批和会话持久化。
- 保留既有 Flutter AI 参考资料，并在文档首页中作为参考资料入口。

### 当前基线

- 应用入口：`lib/main.dart`。
- 根组件：`MainApp`。
- 核心界面：`IdeHome`。
- 默认 Agent provider：Codex CLI app-server。
- 会话状态版本：2。
- 支持平台目录：`linux`、`macos`、`windows`。

### 后续建议

- 将根 README 从默认 Flutter 文案更新为 Zeta 项目说明。
- 为 provider 配置管理明确产品范围。
- 决定是否增加内置文件预览或编辑器。
- 为关键用户流程补充 widget 测试或集成测试。
