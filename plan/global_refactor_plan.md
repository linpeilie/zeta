# Zeta Flutter 全局重构规划

基于当前代码库的 `lib/` 结构、`pubspec.yaml` 依赖、文件体量分布与已有测试，我建议对项目执行一次“按 feature 纵向拆分、feature 内再分层”的渐进式重构，而不是一次性重写或优先更换状态管理框架。

当前项目已经具备一定的演进基础：

- 已有 `AgentProvider` 抽象边界
- 已有 `JsonRpcStdioTransport` 传输层
- 已有覆盖主要行为的测试用例
- 当前复杂度集中在少数超大文件，适合通过拆分职责逐步降耦合

---

## 1. 现状诊断

### 1.1 代码异味最严重、耦合度最高的核心模块

#### 1. `lib/src/data/agent/codex_app_server_provider.dart`

- 文件体量最大，约 3185 行
- 同时承担了以下职责：
  - provider 生命周期管理
  - JSON-RPC 请求发送
  - 通知映射
  - 审批请求处理
  - 本地 JSONL 历史解析
  - 线程历史组装
  - 模型列表拉取与缓存
- 问题本质：
  - 基础设施协议层、数据映射层、历史构建层、运行时协调层全部糅合
  - 改动任意一部分都容易引发连锁影响

#### 2. `lib/src/ui/features/ide/view_models/agent_conversation_view_model.dart`

- 约 1862 行
- 同时承担了以下职责：
  - 会话切换与恢复
  - 历史分页窗口管理
  - turn 分组聚合
  - token 汇总
  - provider 事件处理
  - 模型选择与持久化联动
  - UI 刷新节流
  - 局部展示状态管理
- 问题本质：
  - ViewModel 已经演变成“应用服务 + 状态仓库 + 展示适配器”的混合体
  - 状态边界模糊，后续扩展极易继续膨胀

#### 3. `lib/src/ui/features/ide/views/agent_pane.dart`

- 约 2377 行
- 名义上是 View，实际上承载了：
  - 整体布局与滚动行为
  - timeline 渲染策略
  - Markdown 渲染
  - diff 预览
  - 工具卡片
  - 命令组卡片
  - 文件修改组卡片
  - 审批卡片
  - 历史事件卡片
- 问题本质：
  - 展示层过厚
  - 组件拆分粒度不足
  - 视觉状态与业务状态边界不清

#### 4. `lib/src/domain/agent/agent_models.dart`

- 约 1079 行
- 集中了：
  - provider 配置
  - thread
  - session
  - turn/history
  - message
  - tool
  - permission
  - model
  - event
- 问题本质：
  - 单文件承载整个 agent 子域的模型定义
  - 领域边界没有被实体化为模块
  - 可读性与可维护性持续下降

#### 5. `lib/src/ui/features/ide/views/ide_home.dart`

- 约 514 行
- 本应只是页面壳层，当前却同时负责：
  - 项目打开与目录加载
  - 文件树懒加载
  - IDE 会话恢复
  - 会话保存调度
  - 项目线程切换
  - Agent 上下文同步
  - 多个 ViewModel 协调
- 问题本质：
  - 页面层已经承担了应用编排职责
  - 形成了事实上的 God Widget

### 1.2 UI 与业务逻辑是否混杂

结论：混杂明显，且不是单点问题，而是系统性问题。

典型表现：

- `IdeHome` 同时处理 UI、I/O、会话恢复、状态联动
- `AgentPane` 同时处理视图渲染和复杂展示策略
- `file_tree_builder.dart` 位于 `data/`，却直接依赖 Flutter UI 和主题常量
- `codex_app_server_provider.dart` 把协议层、历史解析和领域映射全部放在同一实现中

这意味着当前项目虽然目录上存在 `app / core / data / domain / ui`，但很多边界只停留在命名层，未真正形成稳定的封装边界。

### 1.3 状态管理层面的缺陷

当前项目状态管理是以下方式的混合：

- `setState`
- `ChangeNotifier`
- `ValueNotifier`
- `StatefulWidget` 本地状态

存在的问题：

- 状态归属不统一，同一类状态可能同时出现在 ViewModel 和 Widget 本地状态中
- 页面层直接协调多个 ViewModel，而不是通过应用层服务或 use case 编排
- `AgentConversationViewModel` 中存在展开/折叠状态接口，但生产 UI 并未统一消费，说明状态所有权已经漂移
- provider 事件、页面状态、会话状态、展示状态没有清晰分层

结论：当前问题的核心不是“没用某个流行状态管理库”，而是“状态职责没有被稳定划分”。

---

## 2. 目标架构设计

### 2.1 重构后的标准化目录结构

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

### 2.2 各目录设计意图

#### `app/`

职责：

- 应用启动
- 依赖装配
- 桌面窗口初始化
- 菜单桥接
- Shell 级页面组合

约束：

- 不放业务规则
- 不放 feature 细节实现

#### `core/`

职责：

- 错误模型
- 通用结果包装
- 日志
- 通用工具函数

约束：

- 不允许依赖任何 feature 业务类型

#### `shared/`

职责：

- 公共主题
- 无业务语义的通用 Widget
- 展示格式化工具

约束：

- 不允许依赖 feature 层 ViewModel、Repository 或 domain service

#### `features/workspace/`

职责：

- 项目目录加载
- 文件树领域模型
- 文件树展示数据转换
- 工作区上下文管理

#### `features/project_threads/`

职责：

- 项目对应线程列表分页
- 项目展开态
- 线程选择态
- 线程摘要缓存

#### `features/agent/`

职责：

- Agent 会话
- turn/timeline
- 审批交互
- token 使用信息
- 模型选择
- provider 协议接入

这是本次重构的核心 feature。

#### `features/ide_session/`

职责：

- IDE 会话快照
- 会话编码/解码
- 会话恢复
- 会话持久化调度

它应从 `IdeHome` 中彻底下沉出来。

### 2.3 统一封装规范

#### 模块隐藏规则

- `data/datasources` 必须视为模块私有实现
- `data/mappers` 必须视为模块私有实现
- `presentation/widgets` 只能被 presentation 内部直接依赖
- `domain` 不允许 import Flutter UI 相关包
- `application` 不允许依赖具体存储实现和具体协议实现

#### 模块通信规则

模块之间只能通过以下方式通信：

- domain repository interface
- application facade / use case
- 明确的 service 接口

禁止方式：

- 页面直接调用另一个 feature 的 ViewModel 内部状态
- data 层直接 import presentation 类型
- 通过原始 `Map<String, Object?>` 横穿多个层级

#### 原始数据的终止边界

- JSON-RPC 原始消息必须终止于 `features/agent/data`
- JSONL 原始历史解析必须终止于 `features/agent/data`
- `shared_preferences` JSON 编解码必须终止于 `features/ide_session/data`
- `flutter_treeview` 节点构造必须终止于 `features/workspace/presentation`

#### 状态归属规则

- 跨页面或跨重建持久存在的状态，只允许有一个 owner
- 纯视觉临时状态可以保留在局部 Widget
- 业务状态不得同时由 ViewModel 和 Widget 各维护一份

### 2.4 状态管理策略建议

当前阶段建议：

- 第一阶段不优先替换状态管理库
- 优先统一状态边界与 owner
- 在边界稳定后，再评估是否迁移到 Riverpod 或保留 `ChangeNotifier`

原因：

- 当前核心痛点是职责耦合，不是框架选型
- 先换库会放大改动面，但不一定解决根因

---

## 3. 分步重构实施计划

以下任务按依赖顺序组织，支持逐步落地。

### Task 1. 建立新模块骨架与依赖规则

目标：

- 建立 `app / core / shared / features/*` 目录骨架
- 明确现有代码迁移目标位

Definition of Done:

- 新目录结构已创建
- 每个现有模块都有明确迁移归属
- 团队约定形成书面规则：UI 依赖方向、data 私有实现边界、模块通信方式

### Task 2. 拆分 Agent 领域模型

目标：

- 拆解 `agent_models.dart`

建议拆分方向：

- provider
- thread
- session
- turn_history
- message
- tool
- permission
- model_selection
- events

Definition of Done:

- 不再存在单个超大领域模型文件
- 每类模型有清晰语义归属
- 领域模型拆分后测试仍通过

### Task 3. 拆分 Workspace 与文件树模块

目标：

- 把目录扫描、树节点构造、UI 绑定解耦

建议拆分方向：

- `workspace/domain`: 文件节点、目录过滤规则
- `workspace/application`: 文件树构建 use case
- `workspace/presentation`: TreeView 节点映射器、Pane 组件

Definition of Done:

- `data` 层不再依赖 Flutter UI 和主题
- 文件树领域数据与 TreeView 表示分离
- 目录扫描逻辑可独立测试

### Task 4. 下沉 IDE 会话恢复与持久化

目标：

- 从 `IdeHome` 中抽离 session restore/save 逻辑

建议拆分方向：

- `ide_session/domain`: Session snapshot
- `ide_session/data`: shared_preferences store
- `ide_session/application`: restore/save coordinator

Definition of Done:

- `IdeHome` 不再直接拼装 `IdeSessionState`
- 会话恢复令牌、恢复时延迟保存、清理无效路径等逻辑迁入 application 层
- 会话恢复相关测试不依赖页面内部细节

### Task 5. 拆分 Codex App Server 基础设施层

目标：

- 拆解 `codex_app_server_provider.dart`

建议拆分方向：

- `app_server_client`
- `notification_mapper`
- `approval_mapper`
- `thread_history_reader`
- `jsonl_history_parser`
- `model_list_mapper`
- `agent_repository_impl`

Definition of Done:

- provider 主入口只负责对外协调
- JSON-RPC 请求、通知映射、历史解析不再堆在一个文件中
- `raw Map` 不再跨越 data 层边界

### Task 6. 收敛 Project Threads 模块

目标：

- 将项目线程分页、展开态、选择态从页面级协调中抽离成独立模块

Definition of Done:

- `ProjectThreadsViewModel` 只负责线程列表状态
- 会话恢复缓存与线程分页策略不再由页面直接编排
- 分页与选择逻辑具备独立测试入口

### Task 7. 拆分 Agent Conversation 应用层

目标：

- 把 `AgentConversationViewModel` 拆成多个职责单元

建议拆分方向：

- session lifecycle coordinator
- timeline assembler
- token usage aggregator
- model selection controller
- permission interaction controller
- thread history window controller

Definition of Done:

- 不再存在单个 ViewModel 同时管理 session、timeline、selection、UI tick
- 实时事件处理与展示状态处理分离
- 各子控制器职责可被单独测试

### Task 8. 拆分 Agent Pane 视图层

目标：

- 把厚重的 `AgentPane` 拆成页面壳 + 组件树

建议拆分方向：

- header
- composer
- timeline section
- markdown message
- command group card
- file edit group card
- diff preview
- permission card
- history event card

Definition of Done:

- `AgentPane` 仅保留布局与组合职责
- 各卡片组件相互独立、文件粒度合理
- 展开/收起状态归属统一，不再出现 ViewModel 与 Widget 双份状态

### Task 9. 收薄 IDE Shell 页面

目标：

- 将 `IdeHome` 收缩为 shell 级容器

保留职责：

- 三栏布局组合
- feature 级 coordinator 注入
- 简单 UI 事件转发

移除职责：

- 目录扫描
- 会话恢复
- 持久化调度
- Agent 线程恢复策略
- 文件树状态构造

Definition of Done:

- `IdeHome` 不再承担应用编排核心逻辑
- 绝大多数业务逻辑迁入各 feature/application
- 页面逻辑可通过简单组合阅读理解

### Task 10. 重整测试结构并建立回归基线

目标：

- 让测试结构跟随新架构，而不是继续围绕超大文件组织

建议测试结构：

- `test/src/features/workspace/...`
- `test/src/features/project_threads/...`
- `test/src/features/agent/...`
- `test/src/features/ide_session/...`
- `test/src/app/...`

Definition of Done:

- 测试目录与 feature 结构一致
- 关键行为具备模块级测试
- 超大 widget test 的职责被合理拆分

---

## 4. 实施优先级建议

如果按投入产出比排序，建议优先级如下：

1. `agent_models.dart`
2. `file_tree_builder.dart`
3. `ide_home.dart`
4. `codex_app_server_provider.dart`
5. `agent_conversation_view_model.dart`
6. `agent_pane.dart`

原因：

- 先拆模型和工作区边界，能快速降低横向依赖
- 再拆页面壳与基础设施，能建立新的分层骨架
- 最后拆最复杂的 agent 会话与视图层，风险更可控

---

## 5. 结论

本项目当前的主要问题，不是“目录不够多”，而是“少数核心对象承担了过多职责，导致状态、协议、展示和持久化边界相互渗透”。

本次重构的目标应当明确为：

- 从页面驱动转向应用层协调
- 从按技术目录浅分层转向按 feature 纵向封装
- 从单个超大类集中管理转向多模块各自守边界
- 从状态混用转向状态 owner 明确

在这个基础上，系统的高内聚、低耦合、可维护性和可演进性才会真正建立起来。
