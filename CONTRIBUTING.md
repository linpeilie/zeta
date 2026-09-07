# 贡献指南

中文 ｜ [English](CONTRIBUTING.en.md)

开发分支和 PR 目标使用 `dev`；正式发布从 `main` 创建 Tag。提交前阅读与改动有关的[工程规范](docs/zh/architecture/engineering_standards.md)。

## 准备环境

Flutter 版本以 [CI](.github/workflows/ci.yml) 为准，Dart 约束见 [pubspec.yaml](pubspec.yaml)。需要对应平台的 Flutter Desktop 构建环境。

```sh
flutter pub get --enforce-lockfile
flutter run -d windows
```

macOS 或 Linux 将设备名改为 `macos` 或 `linux`。Linux 构建依赖及其他命令见[开发者指南](docs/zh/development/developer_guide.md)。

开发助手连接功能时，需要安装并登录相应助手。纯文档和隔离测试不需要真实账号；测试使用 fake，不能意外访问本机凭据或发起付费对话。

## 修改与提交

1. 从 `dev` 创建分支。先检查已有改动，避免覆盖他人的工作。
2. 保持一个 PR 解决一个问题。新增 Provider 或大范围架构调整时，先明确范围、接口和验证方式。
3. 补充相关测试，更新对应现行文档；用户可感知变化写入 [CHANGELOG.md](CHANGELOG.md)。
4. 运行下面适用的检查，再提交 PR。描述实际变化、验证结果和未执行项。

提交使用 Conventional Commits，例如 `fix(agent): 修复历史会话标题丢失`。摘要不超过 50 字符；正文在需要时说明原因。

## 验证

```sh
dart format .                 # 修改 Dart 后
flutter analyze               # 代码改动收尾
bash tool/test_affected.sh     # 行为变化
```

- 内部包：`bash tool/test_packages.sh --only <package>`。
- 代码重构、发版、测试基础设施改动：`bash tool/test_full.sh`，包括内部包检查。
- 界面文案：`dart run tool/check_localized_ui_strings.dart --check`。
- 纯文档：核对链接、标题锚点、事实和中英文内容，按[文档维护](docs/zh/development/documentation.md)自查，无需 Flutter 测试。

开发循环先用单文件或受影响测试；并发保持 2。CI 执行所有分片和内部包。新增顶层测试目录须登记 `tool/test_shards.dart`；不要删改业务断言来让重构通过。

依赖锁文件使用 `https://pub.dev` 包源。提交前检查锁文件变化；不要混入本机镜像地址或意外升级。真实 CLI 和平台验收需单独记录，自动化通过不能替代实机结果。

## 架构红线

- 厂商协议只在各自插件的 data 层，UI 与共享内核消费中立契约。
- Provider 决定消息身份和文件变更证据；共享 Store 不猜 id，不读取原始协议。
- reducer 同步且无副作用；异步执行前后复核会话身份和生命周期。
- 不支持的能力隐藏入口并明确失败，不伪造成功。
- 权限、提问、Plan 审批、执行交接独立，接受计划不预授权操作。
- 状态由单一 application Notifier 拥有，业务资源不因页面退订而销毁。
- 敏感正文和凭据不进入 Zeta 的配置、统计、日志和通知；助手私有数据的读取不自动授权写入。
- UI 使用设计系统和文案目录，不在业务页面复制底层控件样式。

详细边界和例外只在[工程规范](docs/zh/architecture/engineering_standards.md)维护。AI 开发的简版约束见 [AGENTS.md](AGENTS.md)。

## 报告与许可

缺陷请提供复现步骤、版本和实际结果；安全问题按 [SECURITY.md](SECURITY.md) 私密上报。参与讨论须遵守[行为准则](CODE_OF_CONDUCT.md)。贡献内容使用项目的 [GPL-3.0 许可证](LICENSE)。
