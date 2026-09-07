<div align="center">

<img src="assets/branding/zeta_logo.svg" alt="Zeta" width="96" />

# Zeta

在一个桌面窗口里使用 AI 编码助手，查看对话、文件改动和等待确认的操作。

macOS · Windows · Linux

[![CI](https://github.com/linpeilie/zeta/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/linpeilie/zeta/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

中文 ｜ [English](README.en.md)

</div>

## 能做什么

Zeta 把本机的 Codex、Grok 或 Claude Code 接到桌面界面。打开项目后，左边选择项目和历史对话，中间与助手交谈，右边查看项目文件。

- 查看助手的回复、操作记录，以及它报告的文件改动。
- 在助手请求时确认权限、回答问题，或让它先写计划。
- 随时取消正在进行的任务；取消不会撤销已经修改的文件。
- 切换项目或打开设置后继续原来的对话，保留草稿和阅读位置。
- 在任务结束或需要回应时接收桌面通知。
- 查看各助手提供的使用量和套餐额度。

Zeta 不包含 AI 模型，也没有代码编辑器。你需要先安装并登录至少一个受支持的助手。不同助手可用的按钮有所不同，见[功能对照](docs/zh/guide/agents.md)。

## 开始使用

1. 准备好 Codex、Grok 或 Claude Code，并确认它能在电脑上正常使用。
2. 从 [Releases](https://github.com/linpeilie/zeta/releases) 下载与你的系统相符的安装包，按该版本的说明安装。
3. 启动 Zeta，选择「打开项目文件夹」，再在对话框中输入任务。

如果没有找到助手，打开「设置 → Agent 管理」，查看检测结果。详细步骤见[安装与上手](docs/zh/guide/getting-started.md)。

## 权限与数据

助手可以按你选择的权限读取或修改文件、运行命令、访问网络。Zeta 会显示助手发来的确认请求；选择自动允许某些操作后，这些操作可能不再逐次询问。接受计划也不会额外授权其中的操作。

Zeta 在本机保存设置和使用统计，没有自己的云端对话服务或遥测。**AI 助手仍可能把消息、图片和读取到的文件内容发送到其模型服务。** 使用前请确认所选助手和账号的数据处理方式。

助手的配置和历史记录由各助手保存。Zeta 会为连接、历史查看和统计读取相关数据；主动保存配置会写入配置文件。使用 Claude Code 时，还可能更新它已有的登录信息以维持登录。完整说明见[数据与隐私](docs/zh/guide/data-and-privacy.md)。

## 文档与反馈

- [使用指南](docs/zh/README.md)：安装、对话、审批、设置和故障排查
- [更新日志](CHANGELOG.md)
- [报告问题](https://github.com/linpeilie/zeta/issues/new/choose)
- [贡献指南](CONTRIBUTING.md)与[开发文档](docs/README.md)
- [安全策略](SECURITY.md)与[行为准则](CODE_OF_CONDUCT.md)

项目采用 [GPL-3.0 许可证](LICENSE)。
