# Zeta `shadcn_ui` -> `shadcn_flutter` 一次性替换落地计划

> 日期：2026-07-09  
> 适用范围：`lib/` UI 层、测试 harness、设计系统文档  
> 验收平台：Windows  
> 迁移策略：单分支一次性切换，无过渡期兼容层，不向主线分阶段释放

## 0. 文档定位

- 本文档是当前项目“将 `shadcn_ui` 替换为 `shadcn_flutter`”的唯一执行计划。
- 阶段 0 的实际原型验证结论与已修正假设，见：`plan/shadcn_flutter_preflight_validation.md`。
- `plan/shadcn_migration_plan.md` 是“从 Material 迁移到 `shadcn_ui`”的历史文档，不适用于本次目标，应保留为历史记录但不再作为当前迁移基线。
- 本计划默认在单独分支中完成全部改造，直到最后一轮验证通过后再合并；主线不经历“新旧两套 UI 库并存”的阶段。

## 1. 已确认边界

- 本次不是单纯换依赖，而是连同设计 token、主题封装、基础组件层一起重构。
- 不允许过渡期兼容层，不做 adapter 去模拟旧 `Shad*` API。
- 迁移目标不止“能跑”，还要顺手优化 UI 架构，降低未来再次换库时的耦合成本。
- 只要求 Windows 平台验收；macOS/Linux 本轮不做人工验收。
- 计划里必须包含：
  - 可直接开工的任务拆分
  - 分阶段 checklist
  - 验收标准
  - 风险与回滚方案
  - 现有组件 / 主题 API 到 `shadcn_flutter` 的映射表

## 2. 外部基线与版本决策

### 2.1 当前仓库基线

- `pubspec.yaml` 当前依赖：`shadcn_ui: ^0.55.0`
- Dart SDK 约束：`^3.12.2`
- 当前设计系统说明文件仍写明“UI 基于 `shadcn_ui` + 自建 token”

### 2.2 `shadcn_flutter` 外部信息（2026-07-09 核对）

- `pub.dev` 当前可安装稳定版：`0.0.52`
- `pub.dev` 安装方式：`flutter pub add shadcn_flutter`
- `pub.dev` 标明支持：Android、iOS、Linux、macOS、Windows
- `GitHub` 仓库首页可见的 latest release 仍显示 `0.0.51`（2026-02-14），说明 GitHub release 标签与 pub.dev 发布节奏不完全同步
- `pub.dev` changelog 显示 `0.0.48` 到 `0.0.51` 存在多次 breaking changes，尤其是导航、密度、输入等 API 调整

### 2.3 版本策略

- 迁移首版不要使用范围版本，直接固定：
  - `shadcn_flutter: 0.0.52`
- 原因：
  - 本次是大面积一次性切换
  - 目标库仍处于快速演进阶段
  - 固定版本更利于重现问题、稳定测试与后续回滚
- 稳定运行一轮后，再单独评估是否放宽为 `^0.0.52`

## 3. 现状盘点

### 3.1 影响面统计

- 含 `Shad*` / `showShadDialog` / `LucideIcons` 依赖的源码与测试文件：`19` 个
- 直接 `import 'package:shadcn_ui/shadcn_ui.dart'` 的文件：`15` 个
- `lib/src/ui/core/` 中直接耦合 `shadcn_ui` 的核心文件：`7` 个

### 3.2 关键耦合点

#### 根入口与主题

- `lib/src/app/app.dart`
  - 使用 `ShadApp`
  - 根部包裹 `ShadSonner`
  - 通过 `buildShadTheme()` 构建 light/dark theme
- `lib/src/ui/core/app_theme.dart`
  - 直接依赖 `ShadThemeData`
  - 全局定制 `ShadButtonTheme` / `ShadOptionTheme` / `ShadPopoverTheme` / `ShadDialogTheme` / `ShadToastTheme`

#### Token 与运行时取值

- `lib/src/ui/core/ide_colors.dart`
  - 当前 `IdeColors.of(context)` 优先从 `ShadTheme` 回读
  - 通过 `ShadColorScheme.custom` 透传 Graphite 扩展语义
- `lib/src/ui/core/ide_text_styles.dart`
  - 当前 `IdeTextStyles.of(context)` 依赖 `ShadTheme`
  - 通过 `ShadTextTheme.custom` 透传语义字号

#### 核心 primitives

- `lib/src/ui/core/pane_widgets.dart`
  - `IdeTooltip` -> `ShadTooltip`
  - `IdeLoadingIndicator` -> `ShadProgress`
  - `PanelCard` / `Pane` / `PaneInteractiveSurface` 使用 `ShadTheme.of(context)`
- `lib/src/ui/core/ide_context_menu.dart`
  - 视觉是自定义的，但明暗判断依赖 `ShadTheme`
- `lib/src/ui/core/window_frame.dart`
  - 依赖 `ShadPopover`、`ShadPopoverController`、`ShadAnchorAuto`、`ShadButton.ghost`、`ShadIconButton.ghost`
- `lib/src/ui/core/ide_chip.dart`
  - 明暗判断依赖 `ShadTheme`

#### 高风险业务区

- `lib/src/ui/features/ide/views/project_list_pane.dart`
  - `ShadPopoverController`
  - `showShadDialog`
  - `ShadDialog` / `ShadInput` / `ShadButton*`
  - 自定义伪 context menu
- `lib/src/features/agent/presentation/agent_pane.dart`
  - `part` 文件共享同一个 `shadcn_ui` import，实际影响面大于 import 统计
- `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart`
  - `ShadTextarea`
  - `ShadSelect` + `ShadOption`
  - `showShadDialog`
  - 多个紧凑 `ShadIconButton.ghost`
- `lib/src/ui/features/ide/views/ide_home.dart`
  - 使用 `ShadSonner.maybeOf(context)` 与 `ShadToast`
- `lib/src/features/settings/presentation/settings_page.dart`
  - 使用 `showShadDialog` / `ShadInput` / `ShadToast`

### 3.3 当前迁移不应顺手做的事

- 不在本轮顺手重写文件树数据结构；`FileTreePane` 当前只是自定义扁平展开逻辑，不是必须改成 `TreeView`
- 不做全量图标体系替换；现有 Material `Icons.*` 保持可用
- 不在本轮引入新的状态管理方案
- 不在本轮扩大到 macOS/Linux 专项优化

## 4. 目标架构

### 4.1 架构原则

- Graphite 设计 token 继续存在，但不再绑定某个 UI 库的 theme 实现
- `shadcn_flutter` 只作为“渲染组件库”，不是设计系统真源
- `ui/core` 继续是共享 primitives 的唯一入口，feature 页面不直接散落大量库特定写法
- 所有 `shadcn_flutter` API 统一走 import alias，避免与 Flutter Material 命名冲突

### 4.2 目标分层

### A. 设计系统真源

- 保留并整理：
  - `IdeColors`
  - `IdeSpacing`
  - `IdeRadius`
  - `IdeEffects`
  - `IdeMotion`
  - `IdeTextStyles`
  - `IdeCodeFontScope`
- 新增：
  - `IdeThemeScope` 或 `IdeThemeData`（项目自有）

目标：`IdeColors.of(context)`、`IdeTextStyles.of(context)` 不再从第三方库 theme 回读，而是从项目自有 theme scope 解析。

### B. 第三方主题投影层

- 新建或重命名主题构造入口，例如：
  - `buildGraphiteShadcnThemeData()`
- 职责：
  - 把 Graphite token 映射到 `shadcn_flutter` 的 `ThemeData`
  - 配置 color scheme、typography、density、scaling、radius、component theme

目标：第三方 theme 由 Graphite token 推导，不反向成为 token 来源。

### C. 共享基础组件层

- 继续保留项目 wrapper，但实现改为基于 `shadcn_flutter`：
  - `Pane`
  - `PanelCard`
  - `PaneInteractiveSurface`
  - `IdeTooltip`
  - `IdeLoadingIndicator`
  - `IdeChip`
  - `IdeContextMenu`
  - `IdeStatusCard`
  - `IdeCollapsibleCard`
  - `WindowFrame`

目标：feature 页面尽量继续消费项目 primitives，而不是直接消费底层库细节。

### 4.3 import 规范

本次迁移必须统一采用：

```dart
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
```

理由：

- `shadcn_flutter` 存在大量与 Flutter Material 同名类型：
  - `ThemeData`
  - `Theme`
  - `TextField`
  - `IconButton`
  - `Card`
  - `Tooltip`
  - `Scaffold`
  - `AlertDialog`
  - `TextButton`
- 不加 alias，后续代码将长期处于命名冲突与可读性下降状态

执行规则：

- 第三方库一律用 `sf.` 前缀
- 业务项目 token / wrapper 不带前缀
- 禁止在迁移完成后保留“有的文件 alias、有的文件裸导入”的混用状态

### 4.4 无兼容层的切换策略

- 主线不允许：
  - 旧 `Shad*` API 与新 `sf.*` API 并行长期存在
  - 建立“仿旧 API”的桥接层
  - 让 `IdeColors` 继续依赖 `ShadTheme`
- 允许：
  - 在单独 cutover 分支中分提交推进
  - 先做本地/分支内 prototype 验证再批量改造
- 最终合并条件：
  - `shadcn_ui` 依赖已移除
  - `lib/` 与 `test/` 中不再存在 `Shad*`、`showShadDialog`、`package:shadcn_ui/shadcn_ui.dart`

## 5. 分阶段执行计划

### 阶段 0：预切换准备与原型验证

目标：先消灭 API 未知项，再开始正式 cutover。

### 5.0.1 建立 cutover 分支

- 建议分支名：`codex/shadcn-flutter-cutover`
- 迁移期间不向主线拆小 PR

### 5.0.2 记录视觉基线

- 在 Windows 上保存以下页面的 light/dark 截图：
  - 主界面空态
  - 文件树
  - 项目/线程列表
  - 线程更多菜单
  - 设置页与字体选择弹窗
  - Agent pane（header / timeline / composer / diff / plan card）
  - toast 提示
  - 窗口标题栏与菜单
- 保存位置建议：`docs/migration_baselines/shadcn_flutter/`

### 5.0.3 做四个原型验证

- 原型 A：`sf.ShadcnApp` + 自定义 `sf.ThemeData`
  - 验证 Graphite light/dark theme 是否可无 Material ThemeExtension 存活
- 原型 B：`showDialog` + `sf.AlertDialog`
  - 验证 rename/delete/settings 三类弹窗都能覆盖
- 原型 C：`sf.showPopover` / `MenuPopup`
  - 验证是否能替换 `ShadPopoverController` 场景
- 原型 D：`sf.Select` + `sf.TextArea`
  - 验证 Agent composer 里“chip 触发器 + 下拉列表 + 多行输入”是否可等价落地

### 5.0.4 冻结三项核心决策

- 主题真源：`IdeThemeScope`
- import 规范：`sf` alias
- 版本策略：`shadcn_flutter: 0.0.52` 固定版本

### 阶段 0 checklist

- [ ] 创建 cutover 分支
- [ ] 保存 Windows UI baseline 截图
- [ ] 原型 A 通过
- [ ] 原型 B 通过
- [ ] 原型 C 通过
- [ ] 原型 D 通过
- [ ] 冻结主题、alias、版本策略

### 阶段 0 退出标准

- 所有高风险 API 都有明确替代方案
- 不再存在“边改边猜组件 API”的不确定状态

### 阶段 1：依赖切换与根入口重建

目标：把应用根和第三方依赖切到 `shadcn_flutter`，并确保项目重新可编译。

### 5.1.1 依赖替换

- 执行：
  - `flutter pub remove shadcn_ui`
  - `flutter pub add shadcn_flutter:0.0.52`
- 检查 transitive 依赖变化，记录到最终说明

### 5.1.2 重建根入口

修改文件：

- `pubspec.yaml`
- `lib/src/app/app.dart`

具体动作：

- `ShadApp` -> `sf.ShadcnApp`
- 删除根部 `ShadSonner`
- 保留 `AppearanceSettingsController` 的职责不变
- 保持 themeMode / code font / ui font 的现有业务逻辑

### 5.1.3 建立新的主题装配入口

修改文件：

- `lib/src/ui/core/app_theme.dart`
- 新增 `lib/src/ui/core/ide_theme.dart` 或等价文件

具体动作：

- 把 `buildShadTheme()` 替换为新构造函数
- 不再返回 `ShadThemeData`
- 改为返回 `sf.ThemeData`
- 明确设置：
  - `colorScheme`
  - `typography`
  - `radius`
  - `density`
  - `scaling`

### 5.1.4 先让测试 harness 可启动

修改文件：

- `test/src/app/ide_settings_widget_test.dart`
- `test/src/features/agent/presentation/agent_pane_pr3_test.dart`

具体动作：

- `ShadApp` -> `sf.ShadcnApp`
- 替换旧 theme builder

### 阶段 1 checklist

- [ ] `shadcn_ui` 已从 `pubspec.yaml` 删除
- [ ] `shadcn_flutter: 0.0.52` 已固定
- [ ] `MainApp` 已切到 `sf.ShadcnApp`
- [ ] 根部不再使用 `ShadSonner`
- [ ] widget test harness 可启动

### 阶段 1 退出标准

- `flutter pub get` 成功
- 项目重新进入“可编译”状态

### 阶段 2：设计 token 与主题解耦

目标：把 Graphite token 从旧 `ShadTheme` 回读模式中彻底拆出来，变成项目自有真源。

### 5.2.1 重构 `IdeColors`

修改文件：

- `lib/src/ui/core/ide_colors.dart`

具体动作：

- 删除：
  - `shadColorSchemeFromIdeColors(...)`
  - `ideColorsFromShadTheme(...)`
  - `ideColorsFromShadColorScheme(...)`
  - 对 `ShadColorScheme.custom` 的依赖
- `IdeColors.of(context)` 改为：
  - 先读 `IdeThemeScope`
  - 不再依赖 `ShadTheme`
  - 不再保留 Material ThemeExtension fallback

### 5.2.2 重构 `IdeTextStyles`

修改文件：

- `lib/src/ui/core/ide_text_styles.dart`
- `lib/src/ui/core/app_theme.dart`

具体动作：

- 删除对 `ShadThemeData` / `ShadTextTheme` 的读写依赖
- `IdeTextStyles.of(context)` 改为直接基于 `IdeThemeScope` + `IdeCodeFontScope`
- 保留代码字体与 UI 字体分离

### 5.2.3 确定 radius / density / scaling 标尺

要解决的点：

- `shadcn_flutter` 用乘数型 radius token，不是当前项目的固定像素 `BorderRadius`
- 当前 Graphite 关键半径为：
  - small = 6
  - medium = 8
  - large = 12
  - composer = 16

执行策略：

- `IdeRadius` 继续保留为项目精确真源
- `sf.ThemeData.radius` 只作为第三方组件的全局近似基准
- shell 关键容器（Pane / PanelCard / composer / context menu）继续显式使用 `IdeRadius`
- 不把第三方 radius 反向当作 Graphite 真值

### 5.2.4 建立导入与 theme 调用规范

- 所有迁移后的文件统一改成 `sf.Theme.of(context)` 读取第三方 tokens
- 项目语义 token 一律走：
  - `IdeColors.of(context)`
  - `IdeTextStyles.of(context)`
  - `IdeSpacing`
  - `IdeRadius`
  - `IdeEffects`
  - `IdeMotion`

### 阶段 2 checklist

- [ ] `IdeColors` 不再依赖 `ShadTheme`
- [ ] `IdeTextStyles` 不再依赖 `ShadTheme`
- [ ] `IdeThemeScope` 已成为 token 真源
- [ ] 代码字体策略保留
- [ ] radius / density / scaling 基准已冻结

### 阶段 2 退出标准

- 主题切换只依赖项目自有 token scope
- 再次换第三方库时，无需重写 `IdeColors` / `IdeTextStyles` 语义层

### 阶段 3：重写 `ui/core` 基础组件层

目标：优先把壳层 primitives 迁完，再改 feature 页面。

### 5.3.1 `pane_widgets.dart`

修改文件：

- `lib/src/ui/core/pane_widgets.dart`

具体动作：

- `IdeTooltip`：`ShadTooltip` -> `sf.Tooltip` + `TooltipContainer`
- `IdeLoadingIndicator`：`ShadProgress` -> `sf.Progress`
- `PaneInteractiveSurface`：继续保留自绘，不依赖旧 theme API
- `PanelCard` / `Pane`：改用 `IdeThemeScope` + `sf.Theme.of(context)` 读取必要通用参数

### 5.3.2 `ide_chip.dart`

修改文件：

- `lib/src/ui/core/ide_chip.dart`

具体动作：

- 评估两种实现：
  - 基于 `sf.Chip`
  - 保留项目自绘胶囊样式
- 推荐：
  - 若 `sf.Chip` 无法精确满足当前密度与配色，保留 `IdeChip` 自绘，只借助 `sf` 的按钮交互基类或 token

### 5.3.3 `ide_context_menu.dart`

修改文件：

- `lib/src/ui/core/ide_context_menu.dart`

具体动作：

- 不直接把它替换成 `sf.ContextMenu`
- 原因：当前主要用于“更多”按钮弹出的显式菜单，不是右键触发语义
- 推荐实现：
  - `sf.showPopover` + `sf.MenuPopup`
  - 或保持 `PanelCard` + `PaneInteractiveSurface` 的项目自绘菜单内容

### 5.3.4 `window_frame.dart`

修改文件：

- `lib/src/ui/core/window_frame.dart`

具体动作：

- 去掉 `ShadPopoverController`
- 重新实现菜单栏弹层
- 优先方案：
  - `sf.showPopover` + `MenuPopup`
- 标题栏按钮：
  - `ShadIconButton.ghost` -> `sf.IconButton.ghost`
- 保持：
  - `window_manager` 行为
  - Windows 最小化 / 最大化 / 关闭逻辑

### 阶段 3 checklist

- [ ] `pane_widgets.dart` 已去除旧库依赖
- [ ] `ide_chip.dart` 已切到新实现
- [ ] `ide_context_menu.dart` 已脱离旧库
- [ ] `window_frame.dart` 已脱离 `ShadPopoverController`
- [ ] `ui/core` 中不再有 `package:shadcn_ui/shadcn_ui.dart`

### 阶段 3 退出标准

- `ui/core` 已成为稳定的可复用迁移底座

### 阶段 4：分功能面切换业务页面

目标：按业务面拆分替换，避免在一个超大文件里同时处理所有风险。

### 5.4.A 项目列表与文件树

修改文件：

- `lib/src/ui/features/ide/views/project_list_pane.dart`
- `lib/src/features/workspace/presentation/file_tree_pane.dart`

具体动作：

- `showShadDialog` -> `showDialog` + `sf.AlertDialog`
- `ShadInput` -> `sf.TextField`
- `ShadButton*` -> `sf.PrimaryButton` / `sf.OutlineButton` / `sf.GhostButton` / `sf.DestructiveButton`
- `ShadIconButton.ghost` -> `sf.IconButton.ghost`
- 项目线程更多菜单：
  - 改为 `IdeContextMenu` 新实现
- 文件树：
  - 保留现有扁平展开模型
  - 仅替换按钮与 icon 引用

### 5.4.B 设置页

修改文件：

- `lib/src/features/settings/presentation/settings_page.dart`

具体动作：

- 字体选择弹窗改成 `showDialog` + `sf.AlertDialog`
- 字体搜索框改成 `sf.TextField`
- 错误反馈改成 `sf.showToast`

### 5.4.C Agent pane

修改文件：

- `lib/src/features/agent/presentation/agent_pane.dart`
- `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart`
- `lib/src/features/agent/presentation/widgets/agent_pane_messages.dart`
- `lib/src/features/agent/presentation/widgets/agent_pane_cards.dart`
- `lib/src/features/agent/presentation/widgets/agent_pane_sections.dart`
- `lib/src/features/agent/presentation/widgets/agent_pane_header.dart`

具体动作：

- `agent_pane.dart` 顶层 import 改成 `sf` alias，所有 `part` 文件随之切换
- composer：
  - `ShadTextarea` -> `sf.TextArea`
  - `ShadSelect` / `ShadOption` -> `sf.Select` / `sf.SelectPopup` / `sf.SelectItemButton`
  - mention dialog -> `sf.AlertDialog`
  - 多个 icon ghost button -> `sf.IconButton.ghost`
- messages / cards / sections / header：
  - `ShadButton*` 全量替换
  - `ShadSeparator.horizontal` -> `sf.Divider`
  - 删除 `showShadDialog` 依赖

高风险提醒：

- `_SelectorSelect<T>` 是整个 agent composer 的关键节点，必须在阶段 0 原型跑通之后再批量替换

### 5.4.D IDE home 与 toast

修改文件：

- `lib/src/ui/features/ide/views/ide_home.dart`

具体动作：

- 删除 `ShadSonner.maybeOf(context)` 逻辑
- 使用 `sf.showToast` 统一封装 IDE 通知入口
- 把 toast UI 用 `PanelCard` / `sf.Card` / `sf.SurfaceCard` 表达

### 阶段 4 checklist

- [ ] `project_list_pane.dart` 完成
- [ ] `file_tree_pane.dart` 完成
- [ ] `settings_page.dart` 完成
- [ ] `agent_pane.dart` 及全部 `part` 文件完成
- [ ] `ide_home.dart` 的 toast 迁移完成

### 阶段 4 退出标准

- 所有业务页面都已切到 `shadcn_flutter` 或项目 primitives

### 阶段 5：测试、文档、清理

目标：移除残留、补齐规范文件、把迁移结果固化为团队约束。

### 5.5.1 清理旧 API 残留

必须清零的 grep：

```sh
rg -n "package:shadcn_ui/shadcn_ui.dart|showShadDialog|\\bShad[A-Z]" lib test
```

说明：

- 迁移完成后，上述命令结果应为 `0`
- `ShadcnApp` 不会被这条正则误报

### 5.5.2 更新测试

检查并修正：

- dialog 打开/关闭行为
- thread 菜单操作
- settings 字体对话框
- agent composer selector 与发送区交互

必要时补充 widget test，优先覆盖：

- 线程更多菜单
- agent composer 选择器
- toast 触发

### 5.5.3 更新仓库内规范文件

必须同步更新：

- `AGENTS.md`
- `docs/engineering_standards.md`
- `docs/developer_guide.md`
- `docs/design_document.md`

更新内容至少包括：

- 设计系统底层由 `shadcn_ui` 改为 `shadcn_flutter`
- 主题取值入口说明
- import alias 规范
- 不再允许使用旧 `Shad*` API

### 阶段 5 checklist

- [ ] 旧 API grep 清零
- [ ] 关键 widget test 通过
- [ ] 设计系统 skill 已更新
- [ ] AGENTS 与工程文档已同步

### 阶段 5 退出标准

- 代码、测试、文档三者一致

### 阶段 6：最终验收与交付

目标：在 Windows 上完成一次性切换后的发布前验收。

### 5.6.1 必跑命令

```sh
dart format .
flutter analyze
flutter test
flutter run -d windows
```

如时间允许，再补：

```sh
flutter build windows --debug
flutter build windows --release
```

### 5.6.2 Windows 手工冒烟清单

- [ ] 应用冷启动正常
- [ ] 深浅主题切换正常
- [ ] 文件树展开/折叠/选中正常
- [ ] 项目列表搜索、切换、load more 正常
- [ ] thread 的 rename / archive / unarchive / fork / delete 正常
- [ ] 设置页字体搜索与选择弹窗正常
- [ ] Agent composer 输入正常
- [ ] Agent composer 发送正常
- [ ] Agent composer 取消正常
- [ ] Agent composer mention file 正常
- [ ] Agent composer attach image 正常
- [ ] Agent composer model / reasoning / service tier / permission preset selector 正常
- [ ] toast 位置、样式、关闭行为正常
- [ ] Windows 标题栏菜单、最小化、最大化、恢复、关闭正常

### 5.6.3 完成交付判定

- `flutter analyze` 无 error
- `flutter test` 全通过
- Windows 冒烟清单通过
- 设计系统文档完成同步
- `shadcn_ui` 已从依赖和源码中完全移除

## 6. 组件 / API 映射表

| 当前实现 | 目标实现 | 主要落点 | 迁移说明 |
|---|---|---|---|
| `ShadApp` | `sf.ShadcnApp` | `app.dart`、测试 harness | 根入口直接替换 |
| `ShadThemeData` | `sf.ThemeData` | `app_theme.dart` | 返回类型整体切换 |
| `ShadTheme.of(context)` | `sf.Theme.of(context)` + `IdeThemeScope.of(context)` | 全项目 | 第三方通用 token 走 `sf.Theme`，Graphite 语义 token 走项目 scope |
| `ShadColorScheme.custom` | 删除，改为 `IdeThemeScope` | `ide_colors.dart` | 不再借第三方 color scheme 传自定义语义 |
| `ShadTextTheme.custom` | 删除，改为 `IdeTextStyles` 自解析 | `ide_text_styles.dart` | 保留代码字体独立策略 |
| `ShadSonner` / `ShadToast` | `sf.showToast` + 自定义 builder | `app.dart`、`ide_home.dart`、`settings_page.dart` | 由 root 容器模式改为显式 toast 调用 |
| `showShadDialog` | `showDialog` | project/settings/agent | Dialog 展示入口统一回到 Flutter |
| `ShadDialog` / `ShadDialog.alert` | `sf.AlertDialog` | project/settings/agent | 弹窗内容与 action 样式同步改写 |
| `ShadPopover` + `ShadPopoverController` | `sf.showPopover` / `MenuPopup` | `window_frame.dart`、project list | 菜单/弹层从 controller 模式改为 overlay/弹出模式 |
| `ShadAnchorAuto` | `showPopover` 对齐参数 | `window_frame.dart` | 先在阶段 0 原型验证具体 anchor 写法 |
| `ShadButton` | `sf.PrimaryButton` 或 `sf.Button` | 全项目 | 需要结合当前视觉语义选择具体 variant |
| `ShadButton.outline` | `sf.OutlineButton` | 全项目 | 直接映射 |
| `ShadButton.ghost` | `sf.GhostButton` | 全项目 | 直接映射 |
| `ShadButton.destructive` | `sf.DestructiveButton` | 全项目 | 直接映射 |
| `ShadButtonSize.sm` | `sf.ButtonSize.small` | 全项目 | 枚举值语义映射 |
| `ShadIconButton.ghost` | `sf.IconButton.ghost` | 全项目 | 需统一 import alias 避免与 Flutter `IconButton` 冲突 |
| `ShadInput` | `sf.TextField` | project/settings/agent | 新库命名与 Material 冲突，必须走 `sf.TextField` |
| `ShadTextarea` | `sf.TextArea` | `agent_pane_composer.dart` | 需重点验证多行输入与尺寸限制 |
| `ShadSelect<T>` | `sf.Select<T>` | `agent_pane_composer.dart` | 需重写 `_SelectorSelect<T>` |
| `ShadOption<T>` | `sf.SelectItemButton` | `agent_pane_composer.dart` | 选项内容 builder 改写 |
| `ShadSeparator.horizontal` | `sf.Divider` | `agent_pane_messages.dart` | 直接替换 |
| `ShadTooltip` | `sf.Tooltip` + `TooltipContainer` | `pane_widgets.dart` | wrapper 内统一收口 |
| `ShadProgress` | `sf.Progress` | `pane_widgets.dart` | 加载条迁移 |
| `LucideIcons.*` | 优先沿用 `shadcn_flutter` 导出的 icon 集 | `file_tree_pane.dart` 等 | 先不做全量图标重构 |

## 7. 文件级执行顺序

建议严格按下面顺序推进，避免后面的 feature 页面重复返工：

1. `pubspec.yaml`
2. `lib/src/app/app.dart`
3. `lib/src/ui/core/app_theme.dart`
4. `lib/src/ui/core/ide_colors.dart`
5. `lib/src/ui/core/ide_text_styles.dart`
6. `lib/src/ui/core/pane_widgets.dart`
7. `lib/src/ui/core/ide_chip.dart`
8. `lib/src/ui/core/ide_context_menu.dart`
9. `lib/src/ui/core/window_frame.dart`
10. `lib/src/ui/features/ide/views/project_list_pane.dart`
11. `lib/src/features/workspace/presentation/file_tree_pane.dart`
12. `lib/src/features/settings/presentation/settings_page.dart`
13. `lib/src/features/agent/presentation/agent_pane.dart` 及全部 `part` 文件
14. `lib/src/ui/features/ide/views/ide_home.dart`
15. `test/src/app/ide_settings_widget_test.dart`
16. `test/src/features/agent/presentation/agent_pane_pr3_test.dart`
17. `AGENTS.md` / `.cursor/skills/...` / `docs/*.md`

## 8. 风险清单与应对

| 风险 | 表现 | 应对 |
|---|---|---|
| 命名冲突 | `ThemeData` / `TextField` / `IconButton` / `Card` / `Tooltip` 与 Flutter Material 冲突 | 全面采用 `import ... as sf;` |
| Token 反向依赖第三方库 | 再次换库时又要重写设计系统 | 先做 `IdeThemeScope`，让 Graphite 成为真源 |
| Popover 模型变化 | `ShadPopoverController` 不再适用 | 先做 prototype，再改 `window_frame` 与 thread 菜单 |
| Select API 差异 | Agent composer selector 风险最大 | 单独重写 `_SelectorSelect<T>`，优先完成 |
| radius/density 视觉漂移 | 切库后界面变松散、圆角变味 | 冻结 Graphite 精确 token，不让第三方默认值主导 shell 视觉 |
| Toast 机制变化 | 旧通知入口失效 | 在 `ide_home.dart` 建新的统一 toast helper |
| 文档不同步 | 代码迁完，规范还在要求 `shadcn_ui` | 把 AGENTS、设计系统 skill、工程文档纳入必做项 |

## 9. 回滚方案

- 由于本次不做兼容层，回滚策略不是 feature flag，而是整分支回滚。
- 推荐做法：
  - 切换前在主线保留一个明确可回退的 green commit
  - cutover 全程在单独分支完成
  - 只有在阶段 6 全通过后才合并
- 如果最终验收失败：
  - 直接关闭 / 回滚整个 cutover 分支
  - 不把半迁移状态带入主线

## 10. 完成定义

以下条件同时满足，才算本次替换完成：

- `shadcn_ui` 依赖已移除
- `lib/`、`test/` 中旧 `Shad*` / `showShadDialog` 调用已清零
- Graphite token 已脱离对旧库 theme 的反向依赖
- `ui/core` 已全部迁到新实现
- 业务页面全部迁移完成
- Windows 冒烟通过
- 文档与 skill 已同步更新

## 11. 参考链接

- `shadcn_flutter` pub.dev: https://pub.dev/packages/shadcn_flutter
- `shadcn_flutter` 安装页: https://pub.dev/packages/shadcn_flutter/install
- `shadcn_flutter` changelog: https://pub.dev/packages/shadcn_flutter/changelog
- `shadcn_flutter` GitHub: https://github.com/sunarya-thito/shadcn_flutter
