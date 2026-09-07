# AI 开发约束

Zeta 是连接本机 AI 编码助手的 Flutter 桌面应用。支持 Codex、Grok、Claude Code；当前登记以 `lib/src/app/plugins/agent_provider_manifest.dart` 为准。

本文件只保留开发规则。细则见[工程规范](docs/zh/architecture/engineering_standards.md)，操作步骤见[开发者指南](docs/zh/development/developer_guide.md)。规则冲突时以本文件为准，并修正相关文档。

## 开始工作

- 先看 `git status`，保留用户已有改动；日常集成分支是 `develop`；分支来源、PR 目标和生命周期遵循[贡献指南](CONTRIBUTING.md#分支模型)。
- 有 `.codegraph/` 时，定位和理解代码先用 `codegraph explore` / `codegraph node` 或同名 MCP 工具；没有索引就用 `rg`，不自行建索引。
- 按下表阅读相关细则，不必每次通读所有文档。版本以 `pubspec.yaml`、CI 和协议快照为准，不复制历史测试数或耗时作为当前事实。

| 改动 | 必读 |
| --- | --- |
| 分层、状态、生命周期 | [工程规范 §1–3](docs/zh/architecture/engineering_standards.md) |
| 路由、位置状态 | [工程规范 §3](docs/zh/architecture/engineering_standards.md#3-状态与异步编排)、[开发者指南 §8](docs/zh/development/developer_guide.md#8-路由开发指南) |
| Provider、事件、流式消息、审批 | [工程规范 §4](docs/zh/architecture/engineering_standards.md#4-provider-与协议边界)、[开发者指南 §7](docs/zh/development/developer_guide.md#7-agent-provider-开发指南) |
| UI、文案、性能 | [工程规范 §6](docs/zh/architecture/engineering_standards.md#6-ui-与交互)、[开发者指南 §9](docs/zh/development/developer_guide.md#9-ui-开发指南) |
| 存储、统计、通知 | [工程规范 §5](docs/zh/architecture/engineering_standards.md#5-持久化与恢复)、[开发者指南 §10](docs/zh/development/developer_guide.md#10-会话和持久化) |
| 协议升级 | [Codex](docs/zh/protocols/codex_app_server_protocol.md)、[Claude Code](docs/zh/protocols/claude_code_stream_json_protocol.md) |
| Markdown 渲染包 | [UPSTREAM.md](packages/zeta_markdown/UPSTREAM.md)；定制保留上游默认值，变更追加记录 |
| 文档 | [文档维护](docs/zh/development/documentation.md) |

## 核心规则

### G1 · 共享层不含厂商逻辑

Pipeline、CoalescingPolicy/Buffer、Dispatcher、TimelineStore、共享 reduction handler 和 SDK 的 ACP 机制不得依赖具体 Provider、按厂商身份分支或从原始数据猜身份。厂商差异在各自插件的 adapter/reducer 中处理。

Provider handler 覆盖只能在自己的 bundle 注册，并说明共享实现为何不适用。权限、提问、Plan 审批的六个 requested/resolved handler 禁止覆盖；覆盖 turn 完成 handler 时须验证 Plan 执行交接。

### G2 · Provider 决定身份与证据

`entryId`、消息分段、去重、终态及文件变更证据由 Provider 产生。Store 只按明确 id 合并和替换 typed snapshot，UI 不解析命令或读取工作区补算差异。`sourceItemId` / `sourceMessageId` 只是 metadata。

原始协议用不可变、不透明的 `AgentProviderRawPayload` 包装；仅上下文面板可展示原文。共享层不读取原文。新增 typed 字段须覆盖所有逐字段重建点以及 live/history/replay 测试。

### G3 · reducer 同步，副作用校验作用域

reducer 只返回状态、mutation 和 effect，不创建 `Timer`、执行 `Future` 或调用外部回调。副作用走 EffectRunner，执行前复核 listener generation、runtime/epoch 和必要的 thread/turn scope。live、history、replay 使用独立 reducer 状态。

### G4 · 能力不足必须明确失败

UI 按 capability 和 bundle 端口渲染；application/data 执行前再次校验，缺端口抛 `UnsupportedError`。禁止 no-op、伪造空成功或语义不等价的降级。

Session config 以端口为能力真源，结果走 `AgentCommandOutcome`；显示值仅随 Provider 事件更新。排队命令冻结目标，执行前后复核，关闭立即结算为过期，取消与审批不得被偏好保存阻塞。

### G5 · 四种审批独立，禁止预授权

权限审批、用户提问、Provider Plan 审批、Zeta 本地 Plan 执行交接分别建模、排队和回写。接受计划不授权其中的命令、文件或网络操作。

执行交接必须新建显式 Default 回合；只恢复同 Binding/thread/runtime generation 内仍有效的用户权限选择。失效则使用 Provider 声明的保守默认；无可用默认时要求用户选择。不得自动提权或持久化本次覆盖。

### G6 · 单向依赖与单一状态所有者

- 依赖方向：`main → app → presentation/application → domain`；`app → data → domain`。presentation 订阅 application 状态和命令契约；application 不依赖 presentation。
- `domain` 无 Flutter、`dart:io` 或厂商协议。协议、CLI 配置与历史解析只在各 Provider 插件的 data 层；中立机制在 core/sdk，Zeta 自有状态在根应用。
- 具体插件只由 manifest 导入；根测试实现类型只经 `test/src/testing/`。跨包只用公开 barrel，生产代码禁用 testing barrel。新 Provider 声明完整贡献，不能要求修改共享 Store 或其他插件。
- 跨 Widget 的业务状态由 application 的 `Notifier` / `AsyncNotifier` 独占；位置（当前页、活动项目、选中会话、设置分区）以路由 URL 为唯一真源，slice 只作投影，写位置只走导航。会话级 UI 快照（输入草稿、滚动、Markdown/plan 缓存）经 presentation 层 retention/缓存 store 按 controller 弱身份承载，随 entry 关闭清除；禁止把切换后仍需保留的状态私藏在会被路由销毁的 widget State。只用 `flutter_riverpod`，禁 Widget API、手写 listener 状态库、镜像 Notifier、延迟绑定及状态管理 codegen。焦点、弹层、IME 等临时状态留 presentation。
- GoRouter 由 app 层单例 Provider 持有，任何路径不得重建该实例。redirect 是同步纯函数，闭包内只 `ref.read`、禁止 `ref.watch`。Widget 读位置用 `GoRouterState.of(context)`；非 widget 消费方才用路由投影。细则见[开发者指南 §8](docs/zh/development/developer_guide.md#8-路由开发指南)。
- 依赖注入走 Riverpod overrides；组合根不覆盖调用方可替换的依赖。Runner 用工厂取得 owner/result sink，不反向查 provider。application、domain 与 data 不得 import `go_router`；app 层需要导航的对象只依赖注入的导航端口。
- UI 会话命令只经 `AgentConversationActions`；Project Threads 只经 `ProjectThreadsOperations`。旧句柄不得重新定位新 owner；异步结果复核 owner lifetime/scope，每个等待者恰好结算一次。
- 业务资源显式关闭，不随页面退订释放。关闭复用同一 Future，先结算等待者并排空真实执行，再释放 entry/lease、BindingManager、registry、插件和容器；释放失败不得伪报成功。详见工程规范 §3。
- 新代码进入对应 feature；跨 feature UI 复用进 `zeta_ui`，不建宽泛顶层目录。各内部包的依赖限制见工程规范 §2。

### G7 · 敏感内容不进入 Zeta 存储

入口通过 `ZetaStorageBindings` 装配存储，业务层不拼本机路径。JSON 必须版本化、宽容解码；损坏或未知字段不能阻断恢复。

配置、索引、缓存、日志、指标和通知不得保存 prompt、回复正文、工具输出、文件变更正文、原始错误、会话文件路径、环境变量值、凭据、原始协议或路由位置参数（projectId、threadId、providerId、完整 URL、本机路径）。日志与指标只用既有端口和白名单；路由诊断必要时只落 route name。

读取助手私有数据限于明确功能，不自动获得写权限。Claude 按需登录续期仅更新已选中的原 CLI 凭据存储：锁内重读、保留无关字段、校验写回，不迁移或另存副本；取消与审批不受续期阻塞。

### G8 · UI 使用设计系统和文案目录

使用 Graphite token 与 `zeta_ui` 的 Ide 控件；`shadcn_flutter` 仅 `as sf` 导入。禁止硬编码颜色、阴影、圆角，以及直接拼装已有 Ide 封装的控件。

控件高度由内容和 token 内边距撑开，图标过 `IdeIconBox`；容器用足够的 `minHeight`。避免溢出，补键盘、语义标签与文字放大验证。时间线禁止布局后测高再 `setState` 的反馈环。

Zeta 文案走 `context.l10n` 或不可变文本目录；Flutter Locale/l10n 不下沉。新增 ARB key 同步中英文、description 和 String placeholder。面向用户的文档用日常语言，内部实现标识符留在开发文档。

## 完成检查

| 改动 | 检查 |
| --- | --- |
| Dart 文件 | `dart format .` |
| 代码 | `flutter analyze` |
| 行为变化 | `bash tool/test_affected.sh`，补相关回归 |
| 内部包 | `bash tool/test_packages.sh --only <package>` |
| 代码重构、发版、测试基础设施 | `bash tool/test_full.sh`；不得删改业务断言来换取通过 |
| Zeta 界面文案 | `dart run tool/check_localized_ui_strings.dart --check` |
| 纯文档 | 链接、标题锚点、中英文一致性、事实与读者视角自查；不要求 Flutter 测试 |

开发循环用定向测试，不反复跑全量；`dart_test.yaml` 并发保持 2。真实 CLI/平台验收不能由 fake 测试替代，未执行须写明原因。CI 跑全部分片和内部包。

不提交生成噪音、日志或构建产物。用户可感知变化记入 `CHANGELOG.md`，写法遵循[更新日志规范](docs/zh/development/documentation.md#更新日志规范)；架构变化更新对应现行文档，工作记录只保留决策、验证证据和未完成事项。不要复制规则到 `CLAUDE.md`。

回复说明改动、验证和未完成项；最后附【Git 提交信息】，用独立 `sh` 代码块给出 Conventional Commit，摘要不超过 50 字符。不自动提交代码。
