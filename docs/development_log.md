# 开发记录

## 2026-07-04

### 初始化项目文档

- 建立项目文档体系：产品需求文档、设计文档、开发者文档、开发记录和项目记忆。
- 梳理当前代码状态：Zeta 已从 Flutter 默认示例演进为桌面 Agent IDE 壳层。
- 记录当前核心能力：三栏 IDE 布局、本地项目文件树、Codex CLI provider、Agent thread 恢复、工具时间线、权限审批和会话持久化。
- 保留既有 Flutter AI 参考资料，并在文档首页中作为参考资料入口。

### 当前基线

- 应用入口：`lib/main.dart`。
- 根组件：`MainApp`。
- 核心界面：`IdeHome`。
- 默认 Agent provider：Codex CLI app-server。
- 会话状态版本：2。
- 支持平台目录：`linux`、`macos`、`windows`。

### 后续建议

- 将根 README 从默认 Flutter 文案更新为 Zeta 项目说明。
- 为 provider 配置管理明确产品范围。
- 决定是否增加内置文件预览或编辑器。
- 为关键用户流程补充 widget 测试或集成测试。
