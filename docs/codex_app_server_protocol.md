# Codex app-server 协议版本锁定

最后更新：2026-07-09

## 1. 目的

Zeta 的默认 Agent provider（`CodexAppServerAgentProvider`）按 Codex CLI
`app-server` 的 JSON-RPC 协议适配。协议随 CLI 版本演进，字段名、通知方法和
请求 schema 都可能静默变化。

本仓库用 **pinned schema 快照** 固定适配基准：升级 Codex 时先 diff schema，
再改适配层，避免“本机 CLI 已升级、代码仍按旧协议解析”的漂移。

## 2. 当前锁定版本

| 项 | 值 |
| --- | --- |
| Pinned Codex CLI | **0.142.5**（见 `third_party/codex_app_server_schema/PINNED_VERSION`） |
| 导出命令 | `codex app-server generate-json-schema --out <dir>` |
| Schema 快照目录 | [`third_party/codex_app_server_schema/`](../third_party/codex_app_server_schema/) |
| 生成脚本 | [`tool/gen_codex_schema.sh`](../tool/gen_codex_schema.sh)、[`tool/gen_codex_schema.ps1`](../tool/gen_codex_schema.ps1) |
| 适配计划 | [`plan/codex_app_server_adaptation_plan.md`](../plan/codex_app_server_adaptation_plan.md) |

> 说明：适配审计最初对照 `0.142.3` 完成；仓库快照以本机可复现的
> `0.142.5` 导出为准。若需严格对齐 `0.142.3`，用该版本 CLI 重新生成并
> `--force` / `-Force` 覆盖 pin。

运行时仍通过 PATH / 安装目录解析 `codex`；**运行时 CLI 版本不必与 pin
完全一致**，但升级前应先做 schema diff，确认适配层仍覆盖关键方法。

## 3. Schema 快照内容

生成结果主要包括：

- 四个联合类型：`ClientRequest.json`、`ClientNotification.json`、
  `ServerNotification.json`、`ServerRequest.json`
- 聚合文件：`codex_app_server_protocol.schemas.json`
- 逐方法 schema：`v1/`、`v2/` 目录
- 元数据：`PINNED_VERSION`、`GENERATED.json`

> 注：CLI 导出的 `codex_app_server_protocol.v2.schemas.json` 的
> `definitions` 键序不稳定，脚本会主动排除；同等信息已在 `v2/*.json`
> 中按方法拆分保存。

不要手工编辑 JSON；一律通过生成脚本覆盖。

## 4. 重新生成

### macOS / Linux / Git Bash

```sh
./tool/gen_codex_schema.sh
```

### Windows PowerShell

```powershell
./tool/gen_codex_schema.ps1
```

常用选项：

| 选项 | 作用 |
| --- | --- |
| `--diff` / `-Diff` | 只对比当前 CLI 导出与已提交快照，不写入 |
| `--force` / `-Force` | 允许 CLI 版本与 `PINNED_VERSION` 不一致时覆盖快照 |
| `--experimental` / `-Experimental` | 附带实验性方法/字段 |
| `CODEX_BIN` / `-CodexBin` | 指定 Codex 可执行文件路径 |

Windows 上若 PATH 里的 npm 全局 `codex` 偏旧，脚本会优先尝试
`%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe`；也可显式传入：

```powershell
./tool/gen_codex_schema.ps1 -CodexBin "$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin\codex.exe"
```

## 5. 升级 Codex 协议的推荐流程

1. 安装目标版本 Codex CLI，确认 `codex --version`。
2. 运行生成脚本（版本变化时加 `--force` / `-Force`）。
3. `git diff --stat third_party/codex_app_server_schema`，重点看：
   - 四个联合类型的 method 增减
   - 已适配方法的 params / notification 字段变更
   - 服务端请求响应 schema（避免非法应答）
4. 按 diff 更新 `lib/src/features/agent` 适配层与测试。
5. 更新本文件的 pinned 版本说明，以及
   `plan/codex_app_server_adaptation_plan.md` 中的协议基准段落。
6. 用真实 `codex app-server --stdio` 做冒烟（发消息、中断、错误路径）。
   仓库脚本：`python tool/smoke_codex_app_server.py`（默认找本机 `0.142.x`）。

## 6. 与适配层的关系

- UI / domain 只消费中立 `AgentEvent` 等模型，不直接读 schema JSON。
- Schema 快照是 **人工与 CI 可 diff 的协议真相源**，不是运行时依赖。
- 未匹配通知的 fine 日志与诊断计数（A7）用于发现 pin 之外的新方法；
  一旦确认需要适配，应同步更新快照与 mapper。
