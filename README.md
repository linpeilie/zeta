<div align="center">

<img src="assets/branding/zeta_logo.svg" alt="Zeta" width="96" />

# Zeta

**给命令行 AI 编码助手，配一个看得清、管得住的桌面工作台。**

macOS · Windows · Linux ｜ 本地运行 ｜ 开源

[![CI](https://github.com/linpeilie/zeta/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/linpeilie/zeta/actions/workflows/ci.yml)
[![Release](https://github.com/linpeilie/zeta/actions/workflows/release.yml/badge.svg)](https://github.com/linpeilie/zeta/actions/workflows/release.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

中文 ｜ [English](README.en.md)

<!-- 截图待补：拍摄规格见 docs/images/README.md
<img src="docs/images/hero.png" alt="Zeta 三栏工作台" width="900" />
-->

</div>

---

## Zeta 是什么

Codex、Claude Code、Grok 这些命令行 AI 助手能力很强，但都住在一个终端窗口里：

- 它到底改了哪些文件？要往回翻几百行日志。
- 它想执行一条命令，你只有一次「y / n」的机会，来不及看清楚。
- 昨天那次对话讲到哪了？关掉终端就没了。
- 任务跑了五分钟，你切去做别的，回来才发现它十分钟前就在等你确认。

Zeta 把这些搬进一个桌面应用。左边是项目和历史会话，中间是完整的工作时间线，右边是文件树。AI 做的每一步——说了什么、想了什么、调用了什么工具、改了哪几行——都按顺序摊在你面前，可以随时往回翻。

它不替代你的代码编辑器，也不上传你的代码。它只做一件事：**让你看清楚 AI 在你的电脑上做了什么，并且随时能叫停。**

## 主要能力

**完整的工作时间线**
回复、推理过程、工具调用、这一回合的代码 diff，全部在一条连续时间线上，带语法高亮。连续的命令和文件编辑会自动分组，不会刷屏。

**该问你的时候一定会问**
执行命令、写文件、访问网络，默认都要你点头。审批卡片固定在输入框上方，不会被新消息挤走。Zeta 从不替你自动授权。

**先看计划，再动手**
可以让 AI 先出方案，你读完确认它才开始执行——而且接受计划**不等于**授权计划里的命令，那些仍然一条条单独请求。中途还能让它继续改计划。

**跑完了会叫你**
任务结束、需要审批、AI 有问题要问——只要你没在盯着那个会话，就会收到系统通知，任务栏或 Dock 也会提醒。点通知直接跳回对应对话。通知里只写「任务已完成」这类类别，不含你的代码或提示词。

**关了还能接着聊**
项目列表、当前项目、文件树展开状态、选中的文件、面板宽度、历史会话，重启后原样恢复。

**用了多少一目了然**
内置使用统计：按时间、项目、模型筛选，看调用次数、成功率、Token 消耗和响应速度，也能看到套餐的用量窗口和重置时间。数据只取助手真实返回的，不做估算。

**顺手的输入框**
粘贴截图直接当输入，`@` 引用项目文件，`$` 插入 Skill，`/` 打开命令菜单。上下键选择，回车确认。

**两套主题，桌面级密度**
深浅两套主题，面板宽度可拖拽，三栏可按需折叠，窄窗口改用浮层，一样能用。界面字体和代码字体分别可调。

## 支持的 AI 助手

| 助手 | 出品方 | 说明 |
| --- | --- | --- |
| **Codex** | OpenAI | 支持最完整：会话恢复、归档、分叉、计划模式、Skills、图片输入、模型与思考程度切换、用量统计 |
| **Grok** | xAI | 支持计划模式与计划审批、对话模式切换、Skills、文件引用；归档与分叉暂不支持 |
| **Claude Code** | Anthropic | 支持计划模式与计划审批、四档权限模式、上下文压缩、订阅额度明细；文件引用与 Skills 暂不支持 |

Zeta 按能力渲染界面：某个助手不支持的功能，界面上直接不出现，而不是点了没反应。完整对照表见[连接 AI 助手](docs/zh/guide/agents.md#各自支持到什么程度)。

> Cursor 曾被支持，现已退役。Zeta 不会启动 Cursor，也不读写 `~/.cursor` 下的任何数据。

## 你的数据在哪

- **代码不出本机。** Zeta 只把项目路径和你选中的文件路径交给本地 AI 命令行工具，自己不上传任何东西，也没有账号体系和遥测。
- **助手的配置保持原位。** 除非你在 Zeta 的配置编辑器里主动保存，否则 Zeta 不动 `~/.codex`、`~/.grok`、`~/.claude` 里的文件。
- **Zeta 自己的数据**放在系统文档目录下的 `.zeta` 文件夹里（设置、会话状态、日志、缓存），都是明文 JSON，随时可以查看或删除。
- **统计索引只存必要字段**：会话 ID、时间、项目、模型、状态、耗时、Token 数。不保存提示词、AI 回复正文、工具输出和原始错误文本。

逐个文件的说明和清理方法见[数据与隐私](docs/zh/guide/data-and-privacy.md)。

## 快速上手

**1. 先装一个 AI 助手**

Zeta 不含模型。先安装并登录 [Codex CLI](https://github.com/openai/codex)、Claude Code 或 Grok CLI，确认在终端里能正常使用。

**2. 装上 Zeta**

到 [Releases 页面](https://github.com/linpeilie/zeta/releases) 下载对应平台的包。安装包目前未做代码签名，首次打开需要在系统提示里放行一次（macOS 右键「打开」，Windows SmartScreen 点「仍要运行」）。

**3. 打开项目，开始对话**

启动 Zeta → 「打开项目文件夹」→ 选一个本地代码仓库 → 在输入框里描述你要做的事，回车发送。想让它先规划再动手，输入 `/` 选 `Plan`。

没检测到助手？打开「设置 → Agent 管理」，那里会显示它卡在哪一步。连接测试只做握手，不调用模型，不产生费用。

完整步骤见[安装与上手](docs/zh/guide/getting-started.md)。

## 文档

**用户文档**（[中文](docs/zh/README.md) ｜ [English](docs/en/README.md)）

- [安装与上手](docs/zh/guide/getting-started.md) · [界面导览](docs/zh/guide/workbench.md) · [对话与时间线](docs/zh/guide/conversations.md)
- [审批、提问与计划](docs/zh/guide/approvals.md) · [连接 AI 助手](docs/zh/guide/agents.md) · [通知与提醒](docs/zh/guide/notifications.md)
- [使用统计](docs/zh/guide/usage-statistics.md) · [设置](docs/zh/guide/settings.md) · [数据与隐私](docs/zh/guide/data-and-privacy.md)
- [故障排查](docs/zh/guide/troubleshooting.md)

**项目文档**

- [更新日志](CHANGELOG.md) · [贡献指南](CONTRIBUTING.md) · [安全策略](SECURITY.md) · [行为准则](CODE_OF_CONDUCT.md)
- [架构总览](docs/zh/architecture/overview.md) · [术语表](docs/zh/development/glossary.md) · [开发者文档](docs/zh/development/developer_guide.md)

## 参与开发

欢迎贡献。动手前请先读 **[贡献指南](CONTRIBUTING.md)**——本项目有一批必须遵守的架构约束，违反的 PR 无论功能是否正确都不会合并。

Zeta 是 Flutter Desktop 应用，Dart SDK `^3.12.2`，CI 使用 Flutter stable 3.44.4。

```sh
flutter pub get
flutter run -d macos    # 或 -d windows / -d linux
```

提交前依次运行：

```sh
dart format .
flutter analyze
bash tool/test_affected.sh   # 只跑受本次改动影响的测试
```

不要在开发循环里跑全量——全量的强制点在 CI。完整档位表见 [`AGENTS.md` §0](AGENTS.md#0-收尾协议每次改完代码必做)。

## 当前不包含

Zeta 定位是 Agent 协作面板，不是完整 IDE。以下能力目前没有，也不在近期计划中：

内置代码编辑器 · 编辑器内 diff 与文件编辑 · 远程仓库与云同步 · 账号体系 · 完整插件系统 · 移动端

## 许可

[GPL-3.0](LICENSE)。你可以自由使用、修改和分发本项目，但分发修改版时必须同样以 GPL-3.0 开源。
