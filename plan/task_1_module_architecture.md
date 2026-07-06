# Task 1 模块骨架与依赖规则

本文件是 `global_refactor_plan.md` 中 Task 1 的落地产物，目标是先固定未来重构的模块边界，再逐步迁移现有实现。当前阶段只建立目录骨架与书面约束，不搬迁业务代码。

## 1. 已创建的目标骨架

```text
lib/
├── main.dart
└── src/
    ├── app/
    │   ├── bootstrap/
    │   ├── composition/
    │   └── shell/
    ├── core/
    │   ├── error/
    │   ├── logging/
    │   ├── result/
    │   └── utils/
    ├── shared/
    │   ├── theme/
    │   ├── widgets/
    │   └── formatters/
    └── features/
        ├── workspace/
        │   ├── domain/
        │   ├── application/
        │   ├── data/
        │   └── presentation/
        ├── project_threads/
        │   ├── domain/
        │   ├── application/
        │   ├── data/
        │   └── presentation/
        ├── agent/
        │   ├── domain/
        │   ├── application/
        │   ├── data/
        │   │   ├── datasources/app_server/
        │   │   ├── datasources/local_history/
        │   │   ├── datasources/transport/
        │   │   ├── mappers/
        │   │   └── repositories/
        │   └── presentation/
        └── ide_session/
            ├── domain/
            ├── application/
            └── data/
```

## 2. 依赖方向规则

### 2.1 顶层依赖方向

- `app` 可以依赖 `features`、`shared`、`core`，但只负责启动、装配和 shell 组合。
- `features/*` 只能向内依赖本 feature 的 `domain/application/data/presentation`，以及向下依赖 `shared`、`core`。
- `shared` 只能依赖 `core`，不能依赖任何 feature。
- `core` 不允许依赖 `app`、`shared` 或任何 feature。

### 2.2 feature 内部分层规则

- `presentation` 可以依赖同 feature 的 `application`、`domain`，也可以依赖 `shared`、`core`。
- `application` 可以依赖同 feature 的 `domain`，也可以依赖 `core`；默认不直接依赖其他 feature 的具体实现。
- `data` 可以依赖同 feature 的 `domain` 与 `core`，但不能依赖 `presentation` 或 `app`。
- `domain` 不允许依赖 Flutter UI 包，不允许依赖具体存储和协议实现。

### 2.3 模块通信规则

- 跨 feature 通信只允许通过 `domain` 接口、`application facade/use case` 或显式 service 接口。
- 禁止页面直接读取另一个 feature 的内部 ViewModel 状态。
- 禁止 `data` 层直接 import `presentation` 类型。
- 禁止原始 `Map<String, Object?>` 跨越多个层级传播到 `application` 或 `presentation`。

### 2.4 原始数据终止边界

- JSON-RPC 原始消息必须终止在 `features/agent/data`。
- JSONL 历史解析必须终止在 `features/agent/data`。
- `shared_preferences` 的 JSON 编解码必须终止在 `features/ide_session/data`。
- `flutter_treeview` 的节点构造必须终止在 `features/workspace/presentation`。

### 2.5 状态归属规则

- 跨页面、跨重建仍需保留的业务状态，只允许有一个 owner。
- 临时视觉状态可以留在局部 Widget，但不得复制业务状态。
- 同一份业务状态不能同时由 ViewModel 和 Widget 本地状态各维护一份。

## 3. 现有文件迁移归属

下表只定义迁移目标，不代表当前任务已完成代码移动。后续各 Task 必须以此映射为准落地。

| 当前文件 | 当前主要职责 | 迁移目标 | 迁移说明 |
| --- | --- | --- | --- |
| `lib/main.dart` | 应用入口、全局错误处理、窗口初始化触发 | `lib/main.dart` + `lib/src/app/bootstrap/` | 保留入口文件，逐步把启动编排下沉到 `app/bootstrap`。 |
| `lib/src/app/app.dart` | `MaterialApp` 装配、依赖注入、首页绑定 | `lib/src/app/shell/` + `lib/src/app/composition/` | UI 壳留在 `shell`，依赖创建逻辑迁到 `composition`。 |
| `lib/src/app/app_constants.dart` | 应用级壳层常量 | `lib/src/app/shell/` | 仅保留与应用壳相关的常量。 |
| `lib/src/app/menu_action_bridge.dart` | 原生菜单桥接 | `lib/src/app/bootstrap/` | 属于宿主集成，不进入 feature。 |
| `lib/src/app/window_bootstrap.dart` | 桌面窗口初始化 | `lib/src/app/bootstrap/` | 属于启动期基础设施。 |
| `lib/src/core/logging/app_logging.dart` | 全局日志能力 | `lib/src/core/logging/` | 保持在 `core`，作为跨模块底层能力。 |
| `lib/src/ui/core/app_theme.dart` | 通用主题与视觉 token | `lib/src/shared/theme/` | UI 公共能力，应脱离当前 `ui/core` 命名。 |
| `lib/src/ui/core/pane_widgets.dart` | 通用 pane/card 组件 | `lib/src/shared/widgets/` | 无业务语义，归入 `shared/widgets`。 |
| `lib/src/ui/core/window_frame.dart` | 桌面窗口框架组件 | `lib/src/shared/widgets/` | 复用型 UI 组件，不属于单一 feature。 |
| `lib/src/data/file_system/path_utils.dart` | 路径展示与命名辅助 | `lib/src/core/utils/` | 与具体 feature 无关，归入基础工具层。 |
| `lib/src/data/file_system/file_node_data.dart` | TreeView 节点附加数据 | `lib/src/features/workspace/presentation/` | 该类型直接服务 `flutter_treeview`，应停留在展示层。 |
| `lib/src/data/file_system/file_tree_builder.dart` | 目录扫描、忽略规则、排序、TreeView 节点构造 | `lib/src/features/workspace/domain/` + `lib/src/features/workspace/application/` + `lib/src/features/workspace/presentation/` | 按职责拆分：过滤/排序规则到 `domain`，构建流程到 `application`，TreeView 节点映射到 `presentation`。 |
| `lib/src/data/session/ide_session_state.dart` | 会话快照模型与 JSON 编解码 | `lib/src/features/ide_session/domain/` + `lib/src/features/ide_session/data/` | 快照模型进入 `domain`，JSON codec 留在 `data`。 |
| `lib/src/data/session/ide_session_store.dart` | 会话持久化仓库 | `lib/src/features/ide_session/data/` | `shared_preferences` 访问边界固定在 `ide_session/data`。 |
| `lib/src/domain/agent/agent_provider.dart` | Agent provider 统一能力接口 | `lib/src/features/agent/domain/` | 保持为 feature 的核心领域接口。 |
| `lib/src/domain/agent/agent_models.dart` | Agent 子域全部模型定义 | `lib/src/features/agent/domain/` | Task 2 拆成 provider、thread、session、history、message、tool、permission、model、event 等子模块。 |
| `lib/src/data/agent/json_rpc_stdio_transport.dart` | stdio JSON-RPC 传输 | `lib/src/features/agent/data/datasources/transport/` | 作为协议传输基础设施保留在 data。 |
| `lib/src/data/agent/codex_app_server_provider.dart` | app-server provider、历史解析、通知映射、审批处理 | `lib/src/features/agent/data/datasources/app_server/` + `lib/src/features/agent/data/datasources/local_history/` + `lib/src/features/agent/data/mappers/` + `lib/src/features/agent/data/repositories/` | Task 5 重点拆分对象；主入口最终只保留对外协调。 |
| `lib/src/data/agent/default_agent_provider_factory.dart` | 默认 provider 工厂 | `lib/src/app/composition/` | 属于依赖装配逻辑，不应留在具体 data 目录。 |
| `lib/src/data/agent/agent_provider_config_store.dart` | 全局 provider 配置读写 | `lib/src/features/agent/data/` | 属于 agent 配置持久化边界。 |
| `lib/src/ui/features/ide/view_models/active_agent_provider_controller.dart` | active provider 生命周期协调 | `lib/src/features/agent/application/` | 这是应用编排职责，不是单纯展示状态。 |
| `lib/src/ui/features/ide/view_models/agent_conversation_view_model.dart` | 会话、timeline、token、权限、模型选择等混合状态 | `lib/src/features/agent/presentation/` + `lib/src/features/agent/application/` | 短期保留 ViewModel 对外接口，后续拆分出多个 application controller。 |
| `lib/src/ui/features/ide/views/agent_timeline_grouping.dart` | 时间线渲染块与分组策略 | `lib/src/features/agent/presentation/` | 当前逻辑直接面向渲染块，先归入展示层。 |
| `lib/src/ui/features/ide/views/agent_pane.dart` | Agent 面板布局、timeline、diff、卡片渲染 | `lib/src/features/agent/presentation/` | Task 8 再继续拆成页面壳与组件树。 |
| `lib/src/ui/features/ide/view_models/project_threads_view_model.dart` | 项目线程分页、展开态、选择态 | `lib/src/features/project_threads/presentation/` + `lib/src/features/project_threads/application/` | 对外展示状态保留在 `presentation`，分页与恢复编排逐步沉到 `application`。 |
| `lib/src/ui/features/ide/views/project_list_pane.dart` | 项目列表与线程列表展示 | `lib/src/features/project_threads/presentation/` | 项目壳层交互由 `app/shell` 注入，组件自身归属 project_threads。 |
| `lib/src/ui/features/ide/views/file_tree_pane.dart` | 文件树 pane 视图 | `lib/src/features/workspace/presentation/` | 仅负责展示和交互转发。 |
| `lib/src/ui/features/ide/views/ide_home.dart` | 三栏 shell、项目加载、会话恢复、文件树、Agent 协调 | `lib/src/app/shell/` + `lib/src/features/workspace/` + `lib/src/features/project_threads/` + `lib/src/features/agent/` + `lib/src/features/ide_session/` | 最终保留为 shell 级容器，业务编排逐步拆回各 feature。 |

## 4. Task 1 结束标准确认

- [x] 新目录骨架已创建并纳入版本控制。
- [x] 每个当前 `lib/` 文件都已有明确迁移归属。
- [x] 依赖方向、通信方式、原始数据边界和状态 owner 规则已形成书面约束。
