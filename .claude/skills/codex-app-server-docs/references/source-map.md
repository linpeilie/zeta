# App-Server 资料导航

只读取当前任务需要的入口。协议变化较快，不要把本文件当作字段清单。

## 本地缓存

每次启用技能后先运行 `scripts/sync_cache.py`，再按以下顺序读取：

1. [cache-manifest.json](cache-manifest.json)
   - 确认官方文档哈希、latest release、本机 Codex 版本和 schema 哈希。
2. [cached-app-server.md](cached-app-server.md)
   - 官方 `openai/codex` 仓库 App-Server README 的当前缓存。
3. [app-server-api.stable.schema.json](app-server-api.stable.schema.json)
   - 本机 Codex CLI 生成的稳定 V2 API 合并 schema。
4. [app-server-api.experimental.schema.json](app-server-api.experimental.schema.json)
   - 同一 CLI 版本使用 `--experimental` 生成；只在明确启用实验 API 时读取。

先搜索完整 method 或类型名，再读取相邻定义。例如：

```text
rg -n -F '"thread/start"' <skill-dir>/references/app-server-api.stable.schema.json
rg -n -F 'TurnStartParams' <skill-dir>/references/app-server-api.stable.schema.json
```

不要一次性加载两份 schema。manifest 中的 `api.codex_version` 与目标运行版本不一致时，
不要使用这些 schema 推断目标版本字段。

## 官方资料优先级

1. [Codex App Server 官方文档](https://developers.openai.com/codex/app-server)
   - 用于产品定位、传输、生命周期、API/事件概览、审批、认证和能力协商。
   - 回答“当前支持什么”或需要用户可访问引用时优先使用。
2. 目标 CLI 生成的 schema
   - `codex app-server generate-json-schema --out <temp-dir>`
   - `codex app-server generate-ts --out <temp-dir>`
   - 用于核对目标二进制版本的精确字段、枚举、可空性和消息方向。
   - 常规刷新由 `scripts/sync_cache.py` 完成；手工生成仅用于指定的其他 CLI 版本。
3. [官方 App-Server README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
   - 用于官方网页尚未覆盖的源码同步说明和实现语义。
4. [App-Server 实现](https://github.com/openai/codex/tree/main/codex-rs/app-server)
   与 [协议 crate](https://github.com/openai/codex/tree/main/codex-rs/app-server-protocol)
   - 用于解决文档/schema 无法说明的调度、兼容、错误和事件时序问题。
   - 优先阅读协议 crate 的 `schema/`、`src/` 和相关测试，再阅读 server handler。

若问题针对固定 Codex release，优先打开对应 tag/commit，不要用 `main` 推断旧版本。
缓存同步失败、缺少页面级引用或用户问的是未安装的新版本时，在线官方资料优先于缓存。

## 按主题检索

- 连接与握手：`initialize`、`initialized`、`clientInfo`、`capabilities`
- 传输与帧：`stdio`、`JSONL`、`websocket`、`unix socket`、`listen`、`proxy`
- 会话生命周期：`thread/start`、`thread/resume`、`thread/fork`、`turn/start`
- 流式输出：`item/started`、`item/completed`、`delta`、`turn/completed`
- 中途输入与取消：`turn/steer`、`turn/interrupt`
- 服务端请求：`approval`、`elicitation`、带 `id` 的 server request、client response
- 能力与兼容：`experimentalApi`、`capability`、`deprecated`
- 历史与分页：`thread/read`、`thread/list`、`cursor`、`itemsView`
- 配置与发现：`config`、`model/list`、`skills/list`、`apps/list`、`mcp`
- 身份与额度：`account`、`login`、`auth`、`rateLimits`
- 可靠性：`overloaded`、`backpressure`、`retry`、`unsubscribe`、`closed`
- 安全边界：`approvalPolicy`、`sandbox`、`permissions`、`command`、`process`、`fs/`

检索精确字段时，从生成 schema 搜索完整 method，再沿其 params/result/notification 类型追踪；
不要只凭 README 示例推断必填字段。

## zeta 项目定位

仓库存在 `.codegraph/`，先用 CodeGraph 定位调用链和影响面。常见入口为：

- `lib/src/features/agent/data/datasources/transport/`：JSON-RPC transport、请求关联和分帧。
- `lib/src/features/agent/data/datasources/app_server/`：App-Server client、provider 和协议映射。
- `test/src/features/agent/data/datasources/app_server/`：provider/client 协议测试。

推荐查询：

```text
codegraph explore "Where is <method-or-event> sent, received, mapped, and tested?"
codegraph explore "Call path from Codex app-server notification to domain event and UI"
```

修改前确认请求编码、响应解码、通知映射和领域事件四层是否都受影响。若只需回答文档问题，
保持只读，不改动产品代码。
