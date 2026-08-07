---
name: codex-app-server-docs
description: Refresh, cache, retrieve, verify, explain, and apply current Codex App-Server documentation and version-matched schemas. Use when answering questions or changing code involving `codex app-server`, JSON-RPC/JSONL or WebSocket transports, initialization, thread/turn/item lifecycles, methods, notifications, server requests, approvals, authentication, configuration, skills/apps/MCP endpoints, schema generation, client integration, protocol migration, or App-Server troubleshooting.
---

# Codex App-Server 文档

以官方文档、目标 Codex CLI 生成的 schema 和官方源码为依据，查证并应用
App-Server 协议。不要凭记忆补全方法名、字段、事件顺序或稳定性等级。

## 每次启用先同步缓存

把以下命令作为使用本技能后的第一项操作：

```text
python <skill-dir>/scripts/sync_cache.py
```

将 `<skill-dir>` 替换为本技能目录。读取脚本输出的 JSON，再继续任务：

- `status` 为 `current` 或 `updated` 且 `schema_matches_installed` 为 `true` 时，优先读取缓存。
- `release_update_available` 为 `true` 时，说明官方 release 高于本机版本；不要自动升级 CLI，
  仍使用与本机版本匹配的 schema，并向用户说明版本差异。
- `status` 为 `degraded` 且 `cache_usable` 为 `true` 时，可以使用现有缓存，但必须披露
  `warnings`，并对可能过时的结论使用官方在线资料复核。
- 脚本非零退出或 `cache_usable` 为 `false` 时，不要把残缺缓存作为事实来源；改走官方
  在线资料，并说明缓存不可用。

脚本每次都会探测本机 `codex --version`，并对官方文档和 GitHub latest release 发起条件
请求。只有文档内容、release 或本机 CLI 版本变化时才写入缓存；不要把 `--force` 用作常规
启用参数。网络明确不可用时可运行 `--offline` 核对本机版本和已有缓存，但必须说明未完成
在线更新检查。

同步后先读取 [缓存 manifest](references/cache-manifest.json)，确认文档来源、哈希、最新
release 与 API schema 对应的 Codex 版本。

## 确定目标

先判断用户需要哪一种真相来源：

- 解释“当前 App-Server”时，查阅最新官方文档。
- 对接本机或指定版本时，使用同步输出中的本机版本，并以该版本生成的 schema 为准。
- 修改已有客户端时，同时确认项目锁定/实际启动的 Codex 版本和现有兼容策略。
- 分析日志或抓包时，把观测到的消息作为该运行实例的证据，但仍用 schema 判断其含义。

若版本未指定且结论依赖版本，先探测本机版本；无法探测时明确标注版本未知，
不要把最新版文档直接描述成用户运行版本的行为。

## 收集证据

按问题类型选择最小充分证据集：

1. 使用 [缓存文档](references/cached-app-server.md) 查找协议语义和生命周期。
2. 使用 [stable API schema](references/app-server-api.stable.schema.json) 核对默认协议；只有
   用户明确处理实验 API 或 capability 时才读取
   [experimental API schema](references/app-server-api.experimental.schema.json)。
3. 需要当前页面级引用、同步脚本处于 degraded 状态或缓存没有覆盖问题时，使用 OpenAI
   Docs MCP、官方 Codex 手册或 `https://developers.openai.com/codex/app-server` 复核。
4. Docs MCP 不可用时，只回退到 OpenAI 官方页面和 `openai/codex` 官方仓库。
5. 文档与目标版本 schema 不一致时，使用 schema 实现线上的目标版本，并说明文档差异。
6. schema 未解释运行语义时，再查官方 README、协议定义、实现和测试。

按需读取 [references/source-map.md](references/source-map.md)，从中选择入口、源码路径和
检索词。不要一次性加载或复述完整 App-Server 文档。

## 核验协议结论

对每个涉及的 API 建立一条简短证据记录：

- 确认消息方向：客户端请求、客户端通知、服务端通知或服务端请求。
- 确认精确的 `method`、参数、响应、错误和关联事件。
- 确认握手与生命周期前置条件，以及线程、轮次、条目之间的关联标识。
- 确认能力协商、稳定/实验性状态、弃用信息和版本边界。
- 确认传输的帧边界、并发/背压、取消、断连和重连语义。
- 确认审批、沙箱、文件/进程操作和远程连接的安全约束。

不要套用通用 JSON-RPC 客户端的默认假设。特别检查官方文档对线上的字段、省略项、
JSONL 分帧和服务端主动请求的说明。解码器应容忍未知字段、未知通知和未来新增的 item
类型；不要悄悄吞掉无法关联的响应或需要客户端回答的服务端请求。

## 应用到 zeta

修改本项目的 App-Server 集成前，先运行：

```text
codegraph explore "Codex app-server integration and the affected method or event"
```

保持协议细节位于 `lib/src/features/agent/data` 的 transport、App-Server client、codec 或
mapper 中。向 application/domain/presentation 暴露中立模型和事件，不要让原始 provider
payload 泄漏到 UI。复用现有 JSON-RPC peer、请求 id 关联、通知流和服务端请求通道；不要
另建并行 transport。

涉及行为变更时，添加或更新最窄的单元测试/fixture，至少覆盖正常响应、相关事件顺序、
错误响应以及本次兼容分支。完成 Dart 改动后执行格式化、`flutter analyze` 和相关测试。

## 排错

按层定位，不要从 UI 症状直接猜协议字段：

1. 核对可执行文件路径、`codex --version`、启动参数和 stderr。
2. 核对 transport 分帧、请求 id 关联、握手完成状态和连接关闭原因。
3. 核对目标方法在版本 schema 中是否存在，是否要求实验能力或其他 capability。
4. 核对线程/轮次状态、订阅关系、通知顺序和审批请求是否被消费。
5. 使用最小 JSON 消息或现有 transport 测试复现，再修改 mapper 或上层状态。

远程传输的成熟度和认证选项可能变化。每次提出非本机监听方案前重新查阅当前官方文档；
未经验证不要建议暴露无认证监听器，也不要把令牌写入命令行、日志或仓库。

## 输出要求

先给结论，再给必要的协议形状或代码改动。注明目标 Codex 版本、稳定/实验性状态和采用的
证据层级。若缓存发生更新、在线检查降级或发现更高 release，简要报告同步结果。浏览官方
资料时在相关结论旁提供直接链接；只使用本地 schema 时注明缓存 manifest 中的生成版本。
若官方文档、schema、源码或运行日志冲突，明确列出冲突并说明采用哪一项及原因。
