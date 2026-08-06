# Flutter Create with AI 中文整理

来源入口：[Flutter Docs - Create with AI](https://docs.flutter.dev/ai/create-with-ai)  
整理日期：2026-07-03  
适用项目：`zeta`

## 文档范围

这份文档整理了 Flutter 官方 `Create with AI` 页面及其导航下的主要文档：

- [Create with AI](https://docs.flutter.dev/ai/create-with-ai)
- [Rules for Flutter and Dart](https://docs.flutter.dev/ai/ai-rules)
- [Agent skills](https://docs.flutter.dev/ai/agent-skills)
- [Dart and Flutter MCP server](https://docs.flutter.dev/ai/mcp-server)
- [AI Coding Assistants](https://docs.flutter.dev/ai/coding-assistants)
- [Google Antigravity](https://docs.flutter.dev/ai/antigravity)
- [Antigravity CLI](https://docs.flutter.dev/ai/antigravity-cli)
- [AI evaluations](https://docs.flutter.dev/ai/evals)
- [GenUI SDK for Flutter](https://docs.flutter.dev/ai/genui)
- [GenUI components](https://docs.flutter.dev/ai/genui/components)
- [GenUI get started](https://docs.flutter.dev/ai/genui/get-started)
- [GenUI input and events](https://docs.flutter.dev/ai/genui/input-events)
- [Flutter AI Toolkit](https://docs.flutter.dev/ai/ai-toolkit)
- [AI Toolkit user experience](https://docs.flutter.dev/ai/ai-toolkit/user-experience)
- [AI Toolkit feature integration](https://docs.flutter.dev/ai/ai-toolkit/feature-integration)
- [AI Toolkit custom LLM providers](https://docs.flutter.dev/ai/ai-toolkit/custom-llm-providers)
- [AI Toolkit chat client sample](https://docs.flutter.dev/ai/ai-toolkit/chat-client-sample)
- [Flutter AI best practices](https://docs.flutter.dev/ai/best-practices)
- [Prompting](https://docs.flutter.dev/ai/best-practices/prompting)
- [Structure & output](https://docs.flutter.dev/ai/best-practices/structure-output)
- [Tool calls](https://docs.flutter.dev/ai/best-practices/tool-calls)
- [Mode of interaction](https://docs.flutter.dev/ai/best-practices/mode-of-interaction)
- [Developer experience](https://docs.flutter.dev/ai/best-practices/developer-experience)

其中 `Developer experience` 已单独整理为
[flutter_ai_developer_experience_zh.md](flutter_ai_developer_experience_zh.md)，本文件只做总览和落地衔接。

## 总体图景

Flutter 官方把 AI 相关能力分成两大方向：

1. 在应用里构建 AI 功能：例如聊天、内容生成、自然语言理解、图像理解、动态 UI、工具调用等。
2. 用 AI 提升开发体验：例如 AI 编码代理、规则文件、Agent skills、MCP server、自动分析和测试等。

对 `zeta` 当前阶段来说，更推荐先完善“开发体验”这一侧：项目已经安装了 Dart/Flutter skills，也已经有 `AGENTS.md`。真正把 AI 功能接入应用时，再根据产品目标选择 Flutter AI Toolkit、GenUI、Firebase AI Logic 或 Genkit Dart。

## 一、开发工具链

### 规则文件

规则文件用于给 AI 编码助手提供默认行为和项目上下文。Flutter 官方提供了不同长度的规则模板，适配不同工具的上下文限制。

当前项目已经落地：

- 根目录：[AGENTS.md](../../AGENTS.md)
- 作用：约束 Flutter/Dart 风格、依赖策略、测试、布局、架构边界和项目清洁度。

后续当项目引入路由、状态管理、网络、资产、Firebase 或 AI 功能时，需要同步更新 `AGENTS.md`。

### Agent Skills

Agent skills 和规则文件不同：

- 规则文件是全局约束，影响所有任务。
- Skills 是面向具体任务的工作流说明，例如添加 widget test、实现 JSON 序列化、修复布局问题。

当前项目已经安装：

- `.agents/skills` 下的 Dart skills
- `.agents/skills` 下的 Flutter skills

建议用法：

```text
请查看 .agents/skills 中有哪些 skill 可以帮助当前任务，并选择最相关的一个执行。
```

适合触发 skill 的任务包括：

- 添加单元测试或 widget test
- 收集测试覆盖率
- 运行静态分析并修复问题
- 解决 pub 依赖冲突
- 实现响应式布局
- 配置路由、本地化、JSON 序列化
- 修复 Flutter 布局溢出

### Dart and Flutter MCP Server

MCP server 让 AI 工具能调用 Dart 和 Flutter 的开发工具能力。官方文档强调它目前仍是实验性能力，并且需要 Dart 3.9 或更高版本。

它能帮助 AI：

- 分析和修复代码错误。
- 查询符号、文档和签名信息。
- 查看运行中 Flutter 应用的 widget tree。
- 搜索 pub.dev 包并管理 `pubspec.yaml`。
- 运行测试并分析结果。
- 使用 Dart formatter 格式化代码。
- 触发热重载或重启。

官方给出的 Codex CLI 配置方式是：

```sh
codex mcp add dart -- dart mcp-server --force-roots-fallback
```

对当前 `zeta` 项目，要注意 `pubspec.yaml` 里 Dart SDK 是 `^3.12.2`，满足官方对 MCP 的版本要求。如果要启用 MCP，建议优先作为本机工具配置，而不是提交项目内配置文件，避免和不同开发者的工具环境互相干扰。

### AI Coding Assistants

官方将 AI 编码助手定位为开发流程加速工具，而不是替代工程判断的工具。它们适合：

- 生成样板代码。
- 解释 Flutter 或 Dart 概念。
- 协助调试错误。
- 执行多步骤重构。
- 运行测试并验证修改。

官方重点介绍了 Antigravity，也提到 Gemini CLI 已逐步成为旧方案。对当前项目而言，Codex 已经可以承担类似“agentic assistant”的角色，因此重点不是切换工具，而是把规则、skills、MCP、验证流程配好。

### Antigravity IDE 与 CLI

Antigravity 是 Google 的 agentic 开发工具套件，包括：

- Antigravity IDE：编辑器体验，带集成 agent 面板。
- Antigravity CLI：终端/TUI 体验，命令为 `agy`。

官方建议首次使用 Antigravity IDE 时选择 Review-driven development，让工具在执行命令前请求确认。这个理念和当前项目的权限策略一致：AI 可以主动工作，但危险动作和外部访问需要明确确认。

Antigravity CLI 支持本地规则文件，例如：

- `.agents/skills/`
- `AGENTS.md`
- 旧版兼容的 `GEMINI.md`

这说明当前项目使用 `AGENTS.md` 和 `.agents/skills` 是符合 Flutter 官方推荐方向的。

### AI Evaluations

Flutter 的 AI evals 是实验性评测体系，用来衡量 AI 工具在真实开发任务上的可靠性。官方强调，LLM 是非确定性的，传统单元测试不足以评估 agentic 行为，例如：

- 是否能正确浏览代码库。
- 是否能执行计划。
- 是否能合成正确代码。
- 是否能遵守安全、简洁和推理质量要求。

对 `zeta` 的启发是：如果以后大量依赖 AI 生成代码，不只要跑 `flutter analyze` 和 `flutter test`，还应保留人工 review、架构 review 和任务验收清单。

## 二、构建应用内 AI 功能

### 可选技术路径

Flutter 官方入口页给出几类方案：

- Firebase AI Logic：适合直接在 Flutter app 中接入 Gemini 或 Vertex AI，同时由 Firebase 管理相关配置。
- Genkit Dart：适合构建更结构化、可观测、可部署的 AI 后端或流程。
- GenUI SDK for Flutter：适合把文本对话转成动态、可交互的 Flutter UI。
- Flutter AI Toolkit：适合快速把 AI 聊天体验嵌入 Flutter app。

对当前项目的选择建议：

- 只是要一个聊天窗口：优先看 Flutter AI Toolkit。
- 需要 AI 生成表单、卡片、按钮等交互式 UI：研究 GenUI。
- 需要后端工作流、工具调用、可观测性、多 provider：看 Genkit Dart。
- 需要最直接接入 Gemini/Vertex：看 Firebase AI Logic。

当前 `zeta` 还没有 Android/iOS/Web 平台目录，只有 Linux/macOS/Windows 桌面目录。接入 Firebase、语音、相机、文件、图片等能力时，要先确认目标平台和权限配置。

## 三、GenUI SDK for Flutter

### 适用场景

GenUI 的目标是把文本式 AI 对话变成可操作的 UI。它不是让模型随意生成 Flutter 代码，而是让 AI 从应用允许的 widget catalog 中选择组件，并通过 JSON/A2UI 协议描述界面和事件。

典型场景：

- 用户要求规划旅行，AI 直接生成带日期、滑块、文本框的表单。
- 用户询问商品，AI 生成可点击的商品轮播。
- 用户和 agent 交互时，界面可以随对话动态更新。

官方提示 `genui` 仍处于 alpha 阶段，API 可能变化。因此生产项目采用前要单独做技术验证。

### 核心组件

GenUI 的核心概念包括：

- `Conversation`：主要入口，管理对话历史并协调生成式 UI 流程。
- `Catalog`：允许 AI 使用的 widget 清单。
- `CatalogItem`：一个可由 AI 引用的 widget，包含名称、数据 schema 和 builder。
- `DataModel`：集中管理动态 UI 状态。
- `SurfaceController`：处理 AI 发送的 UI 消息并维护 surface 状态。
- `Surface`：在 Flutter UI 中渲染某个生成出来的 surface。
- `A2uiTransportAdapter`：把 LLM 文本流解析成 A2UI 消息。
- `A2uiMessage`：AI 发给 UI 的命令，例如创建、更新、删除 surface 或更新数据模型。

### 工作流

GenUI 的交互循环可以理解为：

1. 用户输入 prompt。
2. `Conversation` 把用户消息发送给 LLM。
3. LLM 根据系统指令和 widget schema 返回 UI 指令。
4. `A2uiTransportAdapter` 解析文本流。
5. `SurfaceController` 更新 `DataModel` 和 surface 状态。
6. `Surface` widget 根据 surface ID 重新渲染。
7. 用户点击按钮、填写表单等事件被转回 AI。
8. AI 根据事件继续更新 UI 或生成响应。

### 接入步骤

官方 `get-started` 文档的重点可以整理为：

1. 选择 agent provider。
2. 添加 `genui` 和对应 provider 依赖。
3. 初始化 Firebase、A2A server 或自定义连接。
4. 创建 `Catalog` 和 `SurfaceController`。
5. 创建 `A2uiTransportAdapter`。
6. 创建 `Conversation`。
7. 在 UI 中用 `Surface` 渲染生成内容。
8. 为自定义组件定义 JSON schema 和 `CatalogItem`。
9. 用系统指令明确告诉 LLM 何时使用哪些组件。

如果用于 `zeta`，建议先做一个最小 proof of concept：

- 只开放一个或两个自定义 widget。
- 不让 AI 直接创建任意布局。
- 每个 widget 的 schema 保持小而稳定。
- 对所有 AI 传入数据做类型检查和默认值处理。
- 不把 GenUI 作为主应用导航或核心状态管理层。

### 数据绑定与事件

GenUI 用 `DataModel` 存储动态 UI 状态。组件可以绑定到数据路径，当路径上的值变化时，相关 widget 自动更新。

事件流大致是：

1. 用户点击或输入。
2. widget 通过 `dispatchEvent` 发出 `UiEvent`。
3. `Surface` 注入 `surfaceId`。
4. `SurfaceController` 把事件包装成协议消息。
5. `Conversation` 或 transport 把事件发送给 AI。
6. AI 返回新的 UI 更新、数据更新或后续动作。

设计自定义 GenUI widget 时，需要重点关注：

- 事件名称是否清晰。
- 事件 context 是否只包含必要数据。
- 数据路径是否稳定。
- 用户输入是否经过验证。
- AI 更新 UI 时是否可能造成误导或不可恢复状态。

## 四、Flutter AI Toolkit

### 定位

Flutter AI Toolkit 是一组聊天相关 widget，用来快速把 AI chat 界面放进 Flutter app。它围绕抽象的 `LlmProvider` 接口组织，因此底层模型 provider 可以替换。

内置能力包括：

- 多轮对话。
- 流式响应。
- Markdown 富文本显示。
- 语音输入。
- 图片、文件、链接等附件。
- function calling。
- 自定义样式。
- 会话序列化和反序列化。
- 自定义响应 widget。
- 自定义 LLM provider。
- Android、iOS、Web、macOS 跨平台支持。

当前 `zeta` 主要是桌面项目。如果要使用 AI Toolkit，需要先确认是否补齐 Android/iOS/Web 平台，或者只针对 macOS 桌面做验证。

### 基础接入

官方基础流程：

1. 添加 `flutter_ai_toolkit`、`firebase_ai`、`firebase_core` 等依赖。
2. 创建 Firebase 项目。
3. 用 FlutterFire CLI 把 Firebase 配置加入应用。
4. 初始化 Firebase。
5. 创建 provider，例如 Firebase provider。
6. 使用 `LlmChatView` 显示聊天界面。

安全注意：

- 如果客户端直接调用 Gemini 或 Vertex AI，不要把可滥用的配置公开提交到公开仓库。
- 生产环境更推荐把 AI 请求走后端，例如 Cloud Functions、Cloud Run 或自有服务。
- 对 `zeta` 这种当前没有后端的项目，接入前应先决定“客户端直连”还是“后端代理”。

### 用户体验能力

`LlmChatView` 默认提供很多交互能力：

- 多行输入：桌面和 Web 使用 `Shift+Enter` 换行，`Enter` 提交。
- 语音输入：无文本时显示麦克风入口。
- 多媒体输入：图片、拍照、文件、链接。
- 图片放大：点击缩略图查看大图。
- 复制消息：桌面/Web 选择文本或悬浮按钮，移动端长按。
- 编辑上一条 prompt：修改后重新提交。
- Material/Cupertino 适配：根据宿主 app 使用对应控件。

这对产品设计的启发是：如果只是需要标准聊天体验，不必从零实现聊天 UI。但如果只需要一个简单命令输入框，AI Toolkit 可能偏重。

### 功能集成点

AI Toolkit 支持许多集成参数：

- 欢迎消息：设置初始上下文。
- 建议 prompt：在空历史状态下引导用户提问。
- LLM system instructions：约束模型角色和输出风格。
- Function calling：让模型调用应用提供的工具。
- 禁用附件或语音：收窄 UI 能力。
- 自定义语音转文本。
- 自定义取消和错误处理。
- 管理历史：清空、替换、迁移 provider 时保留历史。
- 会话序列化：保存和恢复 `ChatMessage`。
- 自定义响应 widget：把模型输出渲染成业务 UI。
- 自定义样式：用 `LlmChatViewStyle` 对齐应用视觉。
- 无 UI 调用 provider：用于后台生成、辅助按钮、批处理。
- 重路由 prompt：用于日志、调试、RAG 或动态切 provider。

对 `zeta` 的建议：

- 先关闭不需要的附件和语音输入，降低权限复杂度。
- 先保留聊天历史在内存中，等产品需要再持久化。
- 自定义错误提示，避免把底层异常直接暴露给用户。
- 如果模型输出要驱动业务对象，优先要求 JSON/schema，并在 Flutter 端校验。

### 自定义 LLM Provider

AI Toolkit 的核心接口是 `LlmProvider`，它负责：

- 普通生成流。
- 会话型消息流。
- 管理聊天历史。
- 作为 `Listenable` 通知 UI 变化。

自定义 provider 时需要处理：

- 完整配置能力：把底层模型或客户端作为参数传入。
- 历史管理：支持读取、设置、初始化历史，并在变化时通知。
- 附件转换：把 Toolkit 的附件类型转换成 provider 支持的消息格式。
- 调用底层 LLM：实现流式输出。

如果 `zeta` 将来使用 OpenAI、自建模型、本地模型或公司内部网关，就可以通过自定义 provider 接到 `LlmChatView`，而不是绑定 Firebase provider。

### Chat Client Sample

官方 AI Chat sample 展示了更完整的聊天应用形态：

- 多聊天会话。
- 桌面和移动布局。
- Firebase AI Logic。
- Cloud Firestore 存储。
- 用户认证。
- 用 LLM 根据首轮对话自动生成聊天标题。

对当前项目而言，它更适合作为完整产品参考，而不是直接复制。`zeta` 若要做轻量 AI 功能，建议先实现单会话、内存历史、无认证的版本。

## 五、Flutter AI 最佳实践

### 基本原则

官方最佳实践的核心是：不要把 LLM 当成确定性函数。LLM 更像用户输入源，结果可能错误、部分正确或随机，因此应用必须有 guardrails。

Flutter 可以承担这些 guardrails：

- 输入校验。
- 结构化输出解析。
- UI 让用户确认和修正。
- 测试真实模型响应。
- 用传统代码处理确定性任务。
- 在关键决策点加入人工确认。

### Prompting

高质量 prompt 通常包含：

- 角色：模型应该以什么身份处理问题。
- 上下文：当前任务所需的最小信息。
- 查询：具体要模型完成什么。
- 约束：长度、格式、候选范围、业务规则。
- 输出格式：最好是可解析的 JSON 或 schema。

官方示例的关键经验是：不要把复杂、冗余的上下文全塞给模型。把输入压缩成模型真正需要的信息，通常更快、更稳、更便宜。

建议在 `zeta` 中这样管理 prompt：

```text
assets/prompts/
  feature_name/
    system.prompt
    user_task.prompt
```

等项目真的引入 AI 功能时，再把 prompt 作为资源加入 `pubspec.yaml`。生产项目应给 prompt 做版本管理和变更记录。

### 结构化输入与输出

给 LLM 结构化输入时，优先用 JSON、CSV、XML、Markdown 表格或清晰的分段文本。需要图像或 PDF 时，把二进制数据和 prompt 放进同一次请求。

结构化输出时，建议：

- 在模型配置里声明 `responseMimeType`。
- 提供 `responseSchema`。
- 在 system instruction 或 prompt 中重复说明 schema。
- 解析后进行类型校验、范围校验和业务校验。
- 不要假设“JSON 可解析”就代表“内容正确”。

对 Flutter 应用来说，可靠 JSON 是把 AI 结果接入 UI 和业务逻辑的最低门槛。

### Tool Calls

Tool calling 允许模型请求应用执行某个工具。工具通常包含：

- 名称。
- 描述。
- 输入 JSON schema。
- 应用侧实现。

适合用工具解决的问题：

- 查询私有或实时数据。
- 访问应用内部状态。
- 执行业务动作。
- 把最终结果通过工具返回为结构化数据。
- 在模型遇到冲突时请求用户介入。

实践建议：

- 工具数量保持少而专。
- 工具职责不要重叠。
- 每个工具都要验证参数。
- 对会改变数据或产生费用的工具加入确认。
- 工具结果也要当作不可信输入继续校验。

当同时需要 structured output 和 tool calls 时，有些 SDK 不能让模型直接返回 JSON。官方示例采用“returnResult 工具”的方式：让模型通过一个专门工具提交最终结构化结果，应用侧缓存并解析。

### Human in the Loop

当 AI 结果和已知约束冲突时，不要硬让模型自己决定。官方建议把用户放回循环中，让用户确认、修正或选择。

适合加入人工确认的场景：

- AI 结果影响用户数据。
- AI 结果和本地校验冲突。
- AI 要执行外部动作。
- AI 结果置信度低。
- AI 处理的是账单、安全、隐私、身份、文件删除等敏感事项。

Flutter 的优势是可以用对话框、表单、预览页、差异对比和确认按钮，把这些 guardrails 变成自然的产品体验。

### 交互模式：Ask vs Agent

官方强调，Ask 和 Agent 的区别不是模型，而是工具权限。

- Ask 模式：模型只回答或查询数据，不直接改变世界。
- Agent 模式：模型拥有执行工具的能力，例如读写文件、运行命令、调用 API、修改状态。

对应用内 AI 功能，默认应从 Ask 模式开始。只有当用户收益明显、工具边界清晰、验证充分时，才开放 Agent 模式。

对当前开发流程，Codex 作为 coding agent 已处于 agentic 工作方式，因此项目更需要：

- 清晰的 `AGENTS.md`。
- 可运行的分析和测试。
- 变更 review。
- 对危险操作保留确认。

### 代码还是 LLM

官方给出一个重要判断：如果传统代码能稳定、简单地完成任务，就优先写代码；如果任务需要语言理解、图像理解、开放式推理或生成，才考虑 LLM。

可以用下面的判断表：

| 任务类型 | 更适合代码 | 更适合 LLM |
| --- | --- | --- |
| 表单校验 | 是 | 否 |
| 状态流转 | 是 | 否 |
| 布局响应式规则 | 是 | 否 |
| 图片内容理解 | 否 | 是 |
| 自然语言总结 | 否 | 是 |
| 用户输入纠错 | 视情况 | 视情况 |
| 执行动作前确认 | 是 | 否 |
| 猜测用户意图 | 视情况 | 是 |

这个原则对 `zeta` 很重要：不要为了“AI 化”而把确定性逻辑交给模型。

## 六、对 zeta 的落地路线

当前项目状态：

- Flutter app 名称：`zeta`
- 入口：`lib/main.dart`
- 依赖：只有 Flutter SDK 和 `flutter_lints`
- 平台目录：Linux、macOS、Windows
- 已有项目规则：`AGENTS.md`
- 已安装 skills：Dart/Flutter skills

### 推荐阶段 0：开发体验打底

已完成：

- 安装 Dart skills。
- 安装 Flutter skills。
- 创建项目级 `AGENTS.md`。
- 整理 Flutter AI 开发体验文档。

可选下一步：

- 配置 Dart/Flutter MCP server。
- 为项目添加最小 widget test。
- 建立 `plans/requirements.md`、`plans/design.md`、`plans/tasks.md` 工作流。

### 推荐阶段 1：AI 功能探索

如果只是试验 AI chat：

1. 先决定目标平台：macOS 桌面、Web、移动端或全部。
2. 先做单页面原型，不接业务状态。
3. 优先关闭附件和语音，减少权限配置。
4. 用 `LlmChatView` 验证基本聊天体验。
5. 所有 key 和配置走安全方案，不把敏感配置提交到公开仓库。

如果要用 AI 生成结构化结果：

1. 先写 prompt 文档。
2. 定义 Dart 数据模型。
3. 定义 JSON schema。
4. 要求模型输出 JSON。
5. 解析后做严格校验。
6. 用 UI 让用户确认 AI 结果。

如果要用动态 UI：

1. 先建立一个很小的 widget catalog。
2. 每个 catalog item 都定义清楚 schema。
3. 每个事件都明确 action name 和 context。
4. GenUI 输出只作为局部 UI，不接管整个 app。
5. 等 alpha API 稳定性满足要求后再扩大使用。

### 推荐阶段 2：生产化 guardrails

当 AI 功能进入真实用户流程时，至少补上：

- 错误状态 UI。
- 取消请求能力。
- 请求超时。
- 结果校验。
- 用户确认。
- prompt 版本管理。
- 日志与调试开关。
- 测试样本集。
- 费用和速率限制策略。
- 隐私和数据保留策略。

## 七、实用提示词

### 选择 AI 技术方案

```text
请根据 docs/flutter_ai_create_with_ai_zh.md 和当前项目结构，帮我比较 Flutter AI Toolkit、GenUI、Firebase AI Logic 和 Genkit Dart 哪个更适合下面的功能。

功能描述：
[填写功能]

请输出：
- 推荐方案
- 不推荐方案及原因
- 最小原型步骤
- 需要新增的依赖
- 需要注意的平台和安全问题
```

### 设计应用内 AI 功能

```text
请为下面的 AI 功能创建 plans/requirements.md 和 plans/design.md。

要求遵守 AGENTS.md，并参考 docs/flutter_ai_create_with_ai_zh.md 的 guardrails。

功能描述：
[填写功能]

开始前请先提出澄清问题。
```

### 审查 AI 功能

```text
请审查当前 AI 功能实现。

重点关注：
- prompt 是否过宽或不稳定
- 输出是否有 schema
- 解析后是否校验
- 是否把确定性逻辑错误地交给 LLM
- 是否有用户确认环节
- 是否存在隐私、费用或权限风险
- 是否有测试或手动验证清单
```

## 八、结论

Flutter 官方的 AI 文档给出的不是单一方案，而是一套分层选择：

- 用规则、skills、MCP 和评测改善开发过程。
- 用 AI Toolkit 快速接入聊天体验。
- 用 GenUI 构建动态交互式 AI UI。
- 用 Firebase AI Logic 或 Genkit Dart 接入模型能力。
- 用 prompt、schema、tool calls、人机协作和测试构建 guardrails。

对 `zeta` 来说，最稳的路线是先保持项目轻量，继续把 AI 用在开发体验上；等产品功能明确后，再用规格驱动开发方式选择一个最小 AI 原型，而不是一开始就引入完整 AI 平台栈。
