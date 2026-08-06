<div align="center">

<img src="assets/branding/zeta_logo.svg" alt="Zeta" width="96" />

# Zeta

**给命令行 AI 编码助手，配一个看得懂、管得住的桌面工作台。**

macOS · Windows · Linux ｜ 本地运行 ｜ 开源

[![CI](https://github.com/linpeilie/zeta/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/linpeilie/zeta/actions/workflows/ci.yml)
[![Release](https://github.com/linpeilie/zeta/actions/workflows/release.yml/badge.svg)](https://github.com/linpeilie/zeta/actions/workflows/release.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

中文 ｜ [English](README.en.md)

<!-- 截图待补：拍摄规格见 docs/images/README.md，拍好后删掉这行注释符即可
<img src="docs/images/hero.png" alt="Zeta 三栏工作台" width="900" />
-->

</div>

---

## Zeta 是什么

现在的 AI 编码助手（Codex CLI、Grok 等）能力很强，但都住在一个黑漆漆的终端窗口里：

- 它到底改了哪些文件？要往回翻几百行日志。
- 它想执行一条命令，你只有一次「y / n」的机会，来不及看清楚。
- 昨天那次对话讲到哪了？关掉终端就没了。
- 任务跑了五分钟，你切去做别的，回来才发现它十分钟前就在等你确认。

**Zeta 把这一切搬进一个正经的桌面应用。** 左边是你的项目和历史对话，中间是 AI 的完整工作时间线，右边是项目文件树。AI 做的每一步——说了什么、想了什么、调用了什么工具、改了哪几行代码——都按时间顺序摊开在你面前，可以随时往回翻。

它不替你写代码编辑器，也不上传你的代码。它做的是一件事：**让你真正看清楚 AI 在你的电脑上做了什么，并且随时能叫停。**

## 为什么值得一试

**看得见的工作过程**
AI 的回复、推理过程、工具调用、这一回合改动的代码 diff，全部在一条连续时间线里，带语法高亮。不用再从滚动的终端日志里考古。

<!-- <img src="docs/images/timeline-tools.png" alt="工具调用与回合 diff" width="720" /> -->

**该问你的时候一定会问**
执行命令、写文件、访问网络，默认都要你点头。审批卡片固定在输入框上方，不会被新消息冲走。Zeta 从不替你自动授权。

<!-- <img src="docs/images/approval.png" alt="权限审批卡片" width="720" /> -->

**先看计划，再动手**
可以让 AI 先出一份行动计划，你读完确认，它才开始真正执行。中途还能让它继续修改计划。计划和执行是两个明确分开的动作。

**跑完了会叫你**
任务结束、需要审批、AI 有问题要问——只要你没在盯着那个会话，就会收到系统通知；任务栏闪烁（Windows）、Dock 角标（macOS）也会提醒。点通知直接跳回对应对话。通知里只写「任务已完成」这类分类信息，不会泄露你的代码或提示词。

**关了还能接着聊**
项目列表、当前项目、文件树展开状态、选中的文件、最近的会话，重启后原样恢复。每个项目下的历史会话可以随时翻出来继续。

**用了多少一目了然**
内置使用统计页：按时间、项目、模型筛选，看调用次数、成功率、Token 消耗和响应速度，也能看到当前套餐的用量窗口和重置时间——数据只取 Provider 真实返回的，不做估算。

<!-- <img src="docs/images/usage.png" alt="使用统计" width="720" /> -->

**顺手的输入框**
粘贴或选择截图直接当输入、输入 `$` 唤出 Skills、输入 `/` 唤出命令菜单、`@` 引用项目文件。上下键选择，回车确认。

**两套主题，桌面级密度**
深色 Graphite Night / 浅色 Graphite Day，面板宽度可拖拽，三栏可按需折叠成浮层，窄窗口一样能用。

## 支持的 AI 助手

| 助手 | 状态 | 说明 |
| --- | --- | --- |
| **Codex CLI** | ✅ 默认 | 完整支持：会话恢复、计划模式、Skills、模型切换、用量统计 |
| **Grok** | ✅ 支持 | 通过 ACP 协议接入，部分能力按握手结果自动降级 |

Zeta 采用能力协商机制：某个助手不支持的功能，界面上直接不会出现，而不是点了没反应。未来接入新的助手也不需要改动界面。

> Cursor 曾被支持，现已退役。Zeta 不会启动 Cursor、也不会读取或修改 `~/.cursor` 下的任何数据。

## 你的数据在哪

- **代码不出本机。** Zeta 只把项目路径和你选中的文件路径交给本地 AI CLI，本身不上传任何东西，也没有账号体系。
- **AI CLI 的配置保持原位。** Zeta 不会去动 `~/.codex`、`~/.grok` 里的文件。
- **Zeta 自己的数据放在 `~/.zeta/`**（设置、会话状态、日志、缓存），都是明文 JSON，随时可以查看或删除。
- **统计索引只存必要字段**：会话 ID、时间、项目、模型、状态、耗时、Token 数。不保存提示词、AI 回复正文、工具输出和原始错误文本。

逐个文件的说明和清理方法见[故障排查与数据说明](docs/product/troubleshooting.md#zeta-在你电脑上存了什么)。

## 下载与安装

前往 [Releases 页面](https://github.com/linpeilie/zeta/releases) 下载对应平台的安装包：

| 平台 | 安装包 | 免安装版 |
| --- | --- | --- |
| macOS（Intel / Apple Silicon 通用） | `zeta-<版本>-macos-universal.dmg` | `...-macos-universal.zip` |
| Windows x64 | `zeta-<版本>-windows-x64-setup.exe` | `...-windows-x64.zip` |
| Linux x64 | `zeta_<版本>_amd64.deb` | `zeta-<版本>-linux-x64.tar.gz` |

每个包都附带 `.sha256` 校验文件。

安装包目前**未做代码签名**，首次打开会看到系统提示：

- **macOS**：提示「无法打开，因为无法验证开发者」时，在「访达」中右键点击应用 →「打开」→ 再次确认；或到「系统设置 → 隐私与安全性」中点击「仍要打开」。
- **Windows**：SmartScreen 提示时点击「更多信息」→「仍要运行」。

## 快速上手三步

**1. 先装好一个 AI 助手 CLI**

Zeta 是壳层，本身不含模型。先安装并登录 [Codex CLI](https://github.com/openai/codex)（推荐）或 Grok CLI，确认在终端里能正常使用。

**2. 打开你的项目**

启动 Zeta → 左侧 Projects 面板点「打开目录」→ 选择本地代码仓库。右侧会加载文件树（`.git`、`node_modules`、`build` 这类目录会自动跳过）。

**3. 开始对话**

在中间输入框描述你的需求，回车发送。想让它先规划再动手，就输入 `/` 选择 `Plan`。

> 没检测到 CLI？打开「设置 → Agent 管理」，那里有身份、版本、登录状态和连接测试，能直接告诉你卡在哪一步。连接测试只做握手，不会产生任何模型调用费用。

## 遇到问题

**[故障排查与数据说明](docs/product/troubleshooting.md)** 覆盖了常见问题：安装被系统拦截、CLI 检测不到、审批卡片消失、通知不弹、文件树缺目录、统计数字对不上，以及 `~/.zeta/` 里每个文件存了什么、怎么清理和重置。

还是没解决就[提个 Issue](https://github.com/linpeilie/zeta/issues/new/choose)。

## 参与开发

欢迎贡献。动手前请先读 **[贡献指南](CONTRIBUTING.md)**——本项目有一批必须遵守的架构约束（Provider 隔离、事件管线不变量、权限模型），违反的 PR 无论功能是否正确都不会合并。

Zeta 是 Flutter Desktop 应用，Dart SDK `^3.12.2`，CI 使用 Flutter stable 3.44.4。

```sh
flutter pub get
flutter run -d macos    # 或 -d windows / -d linux
```

提交前请依次运行：

```sh
dart format .
flutter analyze
flutter test
```

架构约定、Provider 接入流程、事件管线不变量和评审门禁，见 [`docs/`](docs/README.md)：

- [**架构总览**](docs/architecture/overview.md) — 分层、事件管线、能力协商，第一次读代码从这里开始
- [**术语表**](docs/guides/glossary.md) — thread / turn / entryId / capability 等高频术语
- [贡献指南](CONTRIBUTING.md) — 环境、命令、提交格式与架构红线
- [更新日志](CHANGELOG.md) — 用户可感知的版本变化
- [安全策略](SECURITY.md) — 威胁模型与漏洞上报方式
- [行为准则](CODE_OF_CONDUCT.md)
- [产品需求文档](docs/product/product_requirements.md) — 目标用户、范围边界与用户流程
- [设计文档](docs/architecture/design_document.md) — 分层结构、UI 骨架、Provider 抽象
- [开发者文档](docs/guides/developer_guide.md) — 命令、事件管线、UI 开发细则
- [工程规范](docs/architecture/engineering_standards.md) — 架构评审规范
- [发版指南](docs/release/release_guide.md) — Tag 规则与发布流程
- [AGENTS.md](AGENTS.md) — AI 协作规则与提交格式

新增 Provider 的正常改动范围是：自有 data 文件 + 中立 domain 契约 + factory 组合 + 契约测试。共享层（decoder、事件管线、时间线 store）不允许出现任何 Provider 分支。

## 当前不包含

Zeta 定位是 Agent 协作面板，不是完整 IDE。以下能力目前**没有**，也不在近期计划中：

内置代码编辑器 · 文件内容读取与编辑器内 diff · 远程仓库与云同步 · 账号体系 · 完整插件系统 · 移动端

## 许可

[GPL-3.0](LICENSE)。你可以自由使用、修改和分发本项目，但分发修改版时必须同样以 GPL-3.0 开源。
