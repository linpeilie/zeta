# Cursor Agent 使用与排错指南

最后更新：2026-07-14

Zeta 通过 Cursor 官方 ACP v1 接入本地 Cursor CLI。该 provider 当前标记为 Beta、默认关闭，
不会改变 Codex/Grok 的默认选择。Zeta 不会自动安装、更新或登录 Cursor，也不会保存 Cursor
API key。

## 1. 支持范围

已支持：

- Windows 原生、macOS 和 Linux 桌面进程；WSL 仅在 Zeta 与 Cursor CLI 位于同一文件系统
  语义下使用，Windows Zeta 不会自动跨入 WSL 启动 Linux CLI。
- ACP `initialize` / `authenticate`、`session/new`、`session/load`、`session/prompt`、
  `session/update`、权限响应与 `session/cancel`。
- Zeta 创建或成功恢复过的 Cursor session 本地最小索引；若 Cursor 握手声明
  `session/list` / `session/delete`，再启用对应远端能力。
- 服务端动态返回的模型、模式、thought level 等 session config options。
- Cursor 提问、计划审批、todo、子任务和图片生成状态事件。
- 项目级 `.cursor/cli.json`、`.cursor/mcp.json`、`.cursor/rules` 与 `AGENTS.md` 由
  workspace-scoped Cursor 进程自行加载。

不支持或不承诺：

- Cursor Cloud Agent、Automations、远程任务接管和私有 Worker。
- 未经握手声明的归档、重命名、分叉、回滚、压缩、steer、session 列表或删除。
- 解析 Cursor 私有数据库、会话文件或磁盘日志。
- 在没有官方 usage 事件时估算费用或把 Cursor 纳入 Codex 使用统计。
- 由 Zeta 自动安装、自动更新 Cursor CLI，或在设置中保存 API key/token。

## 2. 安装与登录

按照 [Cursor CLI 安装文档](https://cursor.com/docs/cli/installation) 安装 CLI。2026 年起官方
主入口是 `agent`，`cursor-agent` 仍可能作为兼容别名存在。安装后验证：

```sh
agent --version
agent help acp
agent status
```

若 `agent --version` 显示 Grok 或其它产品，请不要把该路径配置给 Cursor。改用
`cursor-agent` 兼容别名，或在 Zeta 的 Agent 管理页选择 Cursor CLI 的绝对路径。

推荐使用浏览器登录：

```sh
agent login
agent status
```

自动化环境可按 [Cursor 认证文档](https://cursor.com/docs/cli/reference/authentication) 使用
`CURSOR_API_KEY` 环境变量。不要把 key 写入 Zeta provider 参数、项目文件、截图或问题日志。

## 3. 在 Zeta 中启用

1. 打开“设置 → Agent 管理 → Cursor Agent (Beta)”。
2. 点击检测；如存在同名命令冲突，选择已验证的 Cursor CLI 绝对路径后重新检测。
3. 确认版本、登录状态和 ACP 握手均成功。
4. 阅读一次性 Beta 兼容提示后启用 Cursor。
5. 打开项目，在 Agent 选择器中选择 Cursor；Cursor 只有获得绝对 workspace 后才启动。

禁用 Cursor 不会影响 Codex/Grok。已存在的 Cursor thread 仍可作为只读历史显示；重新启用后
才能继续发送消息。

## 4. 权限与数据边界

Zeta 只按 Cursor 在 `session/request_permission` 中返回的 option id 响应，不猜测权限含义。
建议在 Cursor 全局 `~/.cursor/cli-config.json` 或项目 `.cursor/cli.json` 中配置最小权限；
deny 规则优先。语法见 [Cursor 权限文档](https://cursor.com/docs/cli/reference/permissions)。

Zeta 会持久化：provider 启用状态、已验证 CLI 路径/非敏感检测摘要、Beta acknowledgement，
以及 session id、workspace、标题、时间和状态组成的最小索引。

Zeta 不会持久化：Cursor API key/auth token、prompt、回复正文、工具输出、完整 ACP payload、
完整 stderr 或 Cursor 私有会话数据。管理页诊断位于进程内 ring buffer，复制前仍应人工检查。

## 5. MCP 与项目规则

Cursor CLI 会读取项目 `.cursor/mcp.json` 和规则文件。Zeta 首版只展示这些文件是否存在，
不会读取、合并或改写它们。MCP 登录和状态请使用 Cursor CLI：

```sh
agent mcp list
agent mcp login <server-name>
```

项目切换时 Zeta 会关闭旧 Cursor ACP 进程，并在新项目目录重新启动，防止项目规则、MCP
配置或 session 状态跨 workspace 泄漏。

## 6. 真实 CLI 自检

仓库提供保守的跨平台 smoke 工具。它默认创建带中文和空格的临时 Git 项目、拒绝所有工具
权限、发送只读 prompt，并验证重启恢复；不会修改业务仓库：

```sh
python tool/smoke_cursor_acp.py
```

只验证定位、握手与登录，不产生模型请求：

```sh
python tool/smoke_cursor_acp.py --handshake-only
```

指定 CLI 或现有测试 workspace：

```sh
python tool/smoke_cursor_acp.py --cursor-bin "/absolute/path/to/agent"
python tool/smoke_cursor_acp.py --workspace "/absolute/path/to/temp-repo"
```

真实平台发布矩阵和记录规则见 [Cursor ACP 发布验收](./cursor_acp_release_validation.md)。

## 7. 常见问题

### 检测到 Grok，或提示同名 `agent` 冲突

运行 `Get-Command agent,cursor-agent`（PowerShell）或 `command -v agent cursor-agent`
（macOS/Linux）检查实际路径。在 Agent 管理页选择正确绝对路径并重新检测。Zeta 会组合
`--version`、`about --format json`、`help acp` 与 ACP `agentInfo` 二次验证。

### 未登录或 authenticate 失败

在同一用户环境运行 `agent login` 和 `agent status`。若从桌面图标启动 Zeta，确认桌面进程
继承了所需代理、证书和 `CURSOR_API_KEY` 环境；Zeta 不会从 shell 配置文件主动提取密钥。

### session/load 失败

确认 thread 属于当前项目、项目路径仍存在且 Cursor 版本没有发生不兼容变化。管理页复制
脱敏诊断，关注 `stage=session` 与 capability fingerprint；不要手工编辑本地 session 索引。

### MCP 在终端可用但 Zeta 中不可用

确认 `.cursor/mcp.json` 位于当前 workspace，且 Cursor 进程使用的用户账号已完成 MCP 登录。
切换项目或禁用后重新启用 Cursor，以强制 workspace peer 重建。

### 路径含空格、中文或脚本包装器时启动失败

优先选择真实 CLI 的绝对路径。Windows 支持 `.exe`、`.cmd`、`.bat`、`.ps1` 包装器；
PowerShell 脚本通过 `-File` 启动，不使用 shell 字符串拼接。运行 smoke 并保留脱敏摘要。

### CLI 更新后能力变化

在 Agent 管理页重新检测并复核能力。Zeta 不自动执行 `agent update`。发布前至少对两个目标
Cursor CLI 版本执行完整 smoke，再调整 Beta 展示层级。

## 8. 禁用与卸载

1. 在 Agent 管理页关闭 Cursor provider；必要时切回 Codex/Grok。
2. 若不再需要本地最小 session 列表，可在 UI 中仅从 Zeta 列表移除相应 thread；这不等于
   删除 Cursor 远端 session。
3. 使用 `agent logout` 清除 Cursor 登录态。
4. 按 Cursor 官方安装方式移除 CLI。Zeta 不代替 Cursor 删除账号、远端 session、MCP
   凭据或项目 `.cursor` 配置。

