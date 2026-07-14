# 产品需求文档

最后更新：2026-07-14

## 1. 产品概述

Zeta 是一个基于 Flutter Desktop 的本地 AI IDE 壳层。它面向需要在本地项目中与编码 Agent 协作的开发者，提供项目目录浏览、文件上下文选择、Agent 对话、工具调用展示、权限审批和会话恢复等能力。

当前版本重点不是实现完整代码编辑器，而是验证“本地项目上下文 + Agent 线程 + 可审计工具时间线”的桌面工作流。

## 2. 目标用户

- 主要用户：日常使用本地代码仓库、希望通过 Agent 辅助开发的开发者。
- 次要用户：评估 Agent IDE 交互体验、线程恢复和权限审批模型的产品或工程人员。

## 3. 核心问题

- 开发者需要在多个本地项目之间快速切换，并让 Agent 知道当前项目和当前文件。
- Agent 运行时会产生消息、工具调用和审批请求，用户需要在一个连续时间线中理解执行过程。
- 桌面应用重启后，应尽量恢复上次打开的项目、文件树展开状态和最近使用的 Agent thread。

## 4. 产品目标

- 提供一个稳定的三栏 IDE 工作台：Projects、Agent、Files。
- 支持选择本地项目目录，并在右侧浏览项目文件树。
- 支持将当前项目路径和选中文件路径作为 Agent 上下文传递给 provider。
- 支持通过 Codex CLI app-server、Grok ACP 和默认关闭的 Cursor ACP Beta 创建、恢复和继续
  Agent thread，并按握手能力降级 UI。
- 支持展示 Agent 消息与工具调用状态，并把权限、提问和计划审批固定在输入框上方。
- 支持持久化 IDE 会话状态，减少重启后的上下文丢失。

## 5. 当前范围

### 已有能力

- 桌面端 Flutter 应用入口和自定义窗口启动流程。
- 三栏布局：左侧项目与 thread，中间 Agent 时间线，右侧文件树。
- 本地目录选择和文件树懒加载。
- 忽略常见大目录：`.git`、`.dart_tool`、`build`、`node_modules` 等。
- 使用 `~/.zeta` 下的版本化 JSON 文件保存 Zeta 自有 IDE 会话、Agent provider、外观设置、
  Cursor 最小索引与使用统计派生索引；旧 SharedPreferences 仅用于一次性迁移。
- 应用日志按日期写入 `~/.zeta/logs`；Agent CLI 自有配置和 session 历史保持原位，
  不迁入 `~/.zeta`。
- 内置 Codex CLI、Grok ACP 与 Cursor ACP provider；Codex 仍为默认 active provider，
  Cursor 为默认关闭的 Beta。
- Agent 管理页支持 CLI 身份、版本、账号、连接、配置和脱敏诊断；Cursor 同名 `agent`
  必须经多信号身份校验。
- Agent 事件统一映射为领域模型，UI 不直接绑定 Codex、xAI 或 Cursor 原始协议细节。
- 支持 capability 驱动的 thread 列表、历史、恢复、发送、取消、权限和动态 session 配置；
  不支持的 provider 操作不展示且不会静默成功。
- Cursor session 在官方 list 能力缺失时使用仅含 id/workspace/title/time/status 的 Zeta
  本地索引；prompt、回复、token 和完整 payload 不进入索引。

### 暂不包含

- 内置代码编辑器。
- 文件内容读取、编辑器内 diff 或保存流程。
- 远程仓库、云同步或账号体系。
- 完整插件系统。
- 移动端适配。
- Cursor Cloud Agent、Automations、自动安装/更新和私有本地数据解析。

## 6. 关键用户流程

### 打开项目

1. 用户点击 Projects 面板中的打开目录按钮。
2. 系统调用平台目录选择器。
3. 用户选择本地目录后，系统加载顶层文件树。
4. 项目加入最近项目列表，并成为当前工作区。
5. Agent 上下文更新为当前项目路径。

### 选择文件上下文

1. 用户在 Files 面板展开目录。
2. 用户点击某个文件。
3. 系统选中该文件，并把文件路径设置为 Agent 当前上下文。
4. Agent 面板顶部显示当前文件名。

### 发起 Agent 请求

1. 用户在 Agent 输入框输入请求。
2. 系统创建或恢复当前项目对应的 Agent session。
3. 系统把用户请求和当前文件路径上下文发送给 provider。
4. Agent 时间线展示用户消息、Agent 消息和工具卡片，并允许用户滚动回看上下文。
5. 如 provider 请求权限、用户输入或计划审批，输入框上方的固定交互区立即展示卡片，
   响应后自动移除且不在时间线重复显示。
6. Cursor 提问和计划审批使用独立卡片；取消、超时、他端响应或 provider 退出时必须完成协议收尾。

### 恢复会话

1. 应用启动时读取持久化 IDE 会话。
2. 系统过滤已经不存在的项目或文件。
3. 系统恢复项目列表、当前项目、文件树展开状态、选中文件和 thread 缓存。
4. 用户再次发送消息或切换 thread 时，系统尝试恢复对应 Agent session。

## 7. 非功能需求

- 启动失败、目录读取失败、provider 进程失败不应导致应用崩溃。
- 文件树必须避免一次性递归扫描大型仓库。
- Provider 协议差异应隔离在 data 层实现中，UI 只依赖领域接口。
- Agent 默认审批策略应保持保守，不能自动授权命令或文件写入。
- Cursor 默认禁用；Zeta 不保存 Cursor API key/token，也不读取 Cursor 私有日志或会话库。
- Beta 发布前必须执行自动化门禁与各声明平台真实 CLI smoke；无设备/凭据不得推断通过。
- UI 需要适配桌面窗口大小变化，避免文本和面板明显溢出。
- 新增行为需要配套单元测试或 widget 测试，至少覆盖风险最高的状态转换。

## 8. 成功指标

- 用户可以稳定打开本地项目并浏览文件树。
- 用户可以针对当前项目向已启用且检测通过的 provider 发起 Agent thread。
- Agent 状态、工具调用和审批请求能被清晰展示。
- 应用重启后能恢复最近工作区上下文。
- `flutter analyze` 和 `flutter test` 在主干保持通过。

## 9. 开放问题

- 是否需要内置文本编辑器，还是继续把 Zeta 定位为 Agent 协作面板？
- Cursor Beta 在至少两个 CLI 版本和全部声明平台通过真实 smoke 后，是否提升默认展示层级？
- Agent 是否需要读取选中文件内容，还是继续只传递路径上下文？
- 权限审批是否需要持久化审计记录？
- Thread 列表与项目列表是否需要搜索和归档能力？
