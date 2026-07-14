# Cursor ACP 发布验收

最后更新：2026-07-14

本文记录 Cursor Beta 的可重复质量门禁。单元测试可验证跨平台参数和错误分支，但不能替代
各目标系统上的真实 Cursor CLI smoke。

## 1. 自动化门禁

每个发布候选必须执行：

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
python -m py_compile tool/smoke_cursor_acp.py
```

真实 CLI 已安装但没有账号/凭据的环境运行：

```sh
python tool/smoke_cursor_acp.py --handshake-only
```

具备测试账号的人工发布环境运行：

```sh
python tool/smoke_cursor_acp.py
```

smoke 默认在临时 Git 项目中执行，覆盖定位、身份、initialize/authenticate、session/new、
只读 prompt 流、进程重启、session/load replay、cancel，以及握手后声明的 list/delete。
所有工具权限均拒绝，输出只包含脱敏摘要。

## 2. 平台矩阵

| 平台 | 架构/运行形态 | 状态 | 证据 |
| --- | --- | --- | --- |
| Windows 原生 | x64，`.cmd` 包装器 | 通过 | 2026-07-14，Cursor `2026.07.09-a3815c0`，完整 smoke 10/10 |
| Windows 原生 | x64，`.exe/.bat/.ps1` | 自动化参数测试；待真实 CLI | `cursor_cli_locator_test.dart`、`cursor_process_starter_test.dart` |
| WSL | WSL2 Linux | 当前机器未安装发行版 | 需在 WSL 内独立运行 Flutter/CLI smoke |
| macOS | arm64 | 待真实设备 | 发布前必测 |
| macOS | x64 | 待真实设备或受控 CI runner | 发布前必测 |
| Linux | x64 | 待真实设备或受控 CI runner | 发布前必测 |

状态只允许使用“通过 / 失败 / 阻塞 / 待执行”。没有真实设备或凭据时不得用单元测试推断
“通过”。每条通过记录必须包含日期、OS/架构、Cursor CLI 版本、入口路径类型和 smoke 汇总，
不得包含用户名、home 路径、session id、prompt、token 或原始 stderr。

## 3. 路径与环境用例

每个平台至少覆盖：

- 临时 workspace 路径含空格与中文；
- 用户选择的绝对 CLI 路径；
- 受限 PATH，且 PATH 中存在同名非 Cursor `agent`；
- HOME/USERPROFILE 缺失时仍可从显式路径或 PATH 启动；
- 符号链接或包装器可用；损坏链接/目录/错误脚本会跳过；
- 工作区切换后旧进程关闭，新进程 cwd 与 session cwd 一致；
- 凭据缺失时明确失败，日志不泄漏环境变量值。

Windows 额外覆盖 `.exe/.cmd/.bat/.ps1`；macOS/Linux 额外覆盖可执行位、symlink 和
`~/.local/bin`。Windows 原生与 WSL 必须分别记录，不能互相替代。

## 4. 发布判定

Cursor 保持默认禁用的 Beta，直到以下条件全部满足：

- `flutter analyze` 与全量 `flutter test` 通过；
- Windows 原生、macOS arm64/x64、Linux 与声明支持的 WSL 形态均有真实 smoke 记录；
- 至少两个 Cursor CLI 版本完成核心回归；
- 未知通知可安全忽略，未知服务端 request 返回 method-not-supported；
- 初始化、session/load 与权限/取消失败均能在脱敏诊断中区分阶段；
- 禁用 Cursor 后 Codex/Grok 创建、恢复和对话回归不受影响。

若当前发布无法获得某个平台或第二个 CLI 版本证据，只能继续作为有限 Beta，不得提升默认
展示层级或改为默认启用。

## 5. Beta 观察

每个候选版本按脱敏诊断人工汇总以下计数：

- 未知 `session/update` / `cursor/*` 通知与未知服务端 request 方法计数；
- Cursor 定位、initialize、authenticate 的失败数和失败阶段；
- `session/new` / `session/load` 失败数；
- CLI 版本或 capability fingerprint 变化次数；
- 因 timeout、cancel、workspace 切换或进程退出而收尾的阻塞请求数。

只记录计数、版本和错误分类，不收集 prompt、响应正文、工具参数、session id、用户目录或
凭据。若未知阻塞 request 增加、初始化失败率显著上升或 session/load 出现回归，保持默认
禁用并回退到上一已验证 CLI/适配版本。
