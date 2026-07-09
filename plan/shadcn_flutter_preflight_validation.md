# Zeta `shadcn_flutter` 迁移前验证结论

> 日期：2026-07-09  
> 范围：阶段 0 预验证，仅做盘点与最小原型，不做正式业务替换  
> 目标平台：Windows

## 1. 验证产物

- scratch 包：`plan/shadcn_flutter_preflight/`
- 已执行命令：
  - `flutter analyze`
  - `flutter test`
- 结果：
  - `flutter analyze` 通过
  - `flutter test` 通过

该 scratch 包只验证以下四类替代路径的最小可行性：

1. `ShadApp` -> `sf.ShadcnApp`
2. `showShadDialog` / `ShadDialog` -> `showDialog` + `sf.AlertDialog`
3. `ShadPopoverController` / `ShadPopover` -> `sf.showPopover` + `sf.MenuPopup`
4. `ShadTextarea` / `ShadSelect` / `ShadOption` -> `sf.TextArea` / `sf.Select` / `sf.SelectPopup`

## 2. 当前使用面盘点

截至 2026-07-09，本仓库内命中 `package:shadcn_ui/shadcn_ui.dart`、`showShadDialog`、`Shad*` 的文件共有 `20` 个。

- 直接 `import 'package:shadcn_ui/shadcn_ui.dart'` 的文件：`15` 个
- `lib/src/ui/core/` 内直接耦合旧库的核心文件：`7` 个

按命中次数排序的高风险文件：

| 命中数 | 文件 |
|---|---|
| 21 | `lib/src/ui/features/ide/views/project_list_pane.dart` |
| 17 | `lib/src/features/agent/presentation/widgets/agent_pane_cards.dart` |
| 15 | `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart` |
| 14 | `lib/src/ui/core/app_theme.dart` |
| 11 | `lib/src/features/agent/presentation/widgets/agent_pane_messages.dart` |
| 10 | `lib/src/ui/core/ide_colors.dart` |
| 9 | `lib/src/ui/core/window_frame.dart` |
| 8 | `lib/src/features/settings/presentation/settings_page.dart` |
| 8 | `lib/src/ui/core/pane_widgets.dart` |
| 8 | `lib/src/ui/core/ide_text_styles.dart` |

文件级风险结论：

- `lib/src/ui/core/app_theme.dart`
  - 根主题装配强依赖 `ShadThemeData`、`ShadButtonTheme`、`ShadOptionTheme`、`ShadPopoverTheme`、`ShadDialogTheme`、`ShadToastTheme`
- `lib/src/ui/core/ide_colors.dart`
  - `IdeColors.of(context)` 运行时先从 `ShadTheme` 回读，和“Graphite token 成为项目真源”的目标直接冲突
- `lib/src/ui/core/ide_text_styles.dart`
  - `IdeTextStyles.of(context)` 也通过 `ShadTheme` 回读，且用 `ShadTextTheme.custom` 透传自定义语义字号
- `lib/src/ui/core/window_frame.dart`
  - 标题栏菜单直接依赖 `ShadPopoverController`、`ShadPopover`、`ShadAnchorAuto`
- `lib/src/ui/features/ide/views/project_list_pane.dart`
  - 同时覆盖项目更多菜单、线程更多菜单、rename/delete dialog，是 overlay 风险最集中的业务文件
- `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart`
  - `ShadTextarea`、`ShadSelect`、`ShadOption`、mention dialog、ghost icon button 全都集中在这里，是本轮最大业务风险点
- `lib/src/features/settings/presentation/settings_page.dart`
  - 字体选择弹窗使用旧 dialog shell，复杂度高于简单确认弹窗
- `lib/src/ui/features/ide/views/ide_home.dart`
  - 仍依赖 `ShadSonner` / `ShadToast`

## 3. 原型结论

### 3.1 `ShadApp` -> `sf.ShadcnApp`

结论：`可行`

原型结论：

- `sf.ShadcnApp` 可直接作为应用根组件
- Graphite token 可以通过项目自有 scope 下发，再单向投影到 `sf.ThemeData`
- `ShadSonner` 不需要保留兼容层；`sf.ShadcnApp` 根层已自带 overlay / toast 基础设施

必须修正的计划假设：

- `shadcn_flutter` 定义的是 `sf.ThemeMode`，不是 Flutter Material 的 `ThemeMode`
- 正式迁移时必须统一使用 `import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;`
- Windows 目标下应显式以 Windows 平台语义验证 overlay 行为，避免误走移动端 sheet handler

建议实现方式：

- 新建项目自有 `IdeThemeScope`，让 Graphite token 留在项目侧
- 新主题函数只负责把 Graphite token 投影到 `sf.ThemeData`
- `MainApp` 根部切换到 `sf.ShadcnApp` 后，再逐步清理 `ShadSonner` 入口和旧 theme builder

### 3.2 `showShadDialog` / `ShadDialog` -> `showDialog` + `sf.AlertDialog`

结论：`可行，但不是 1:1 替换`

原型结论：

- 简单确认弹窗、确认/取消 action、`Navigator.pop` 返回值路径可正常工作
- `showDialog` + `sf.AlertDialog` 适合 rename/delete/confirm 这类短流程弹窗

主要风险：

- `sf.AlertDialog` 没有旧 `ShadDialog` 那种现成的 `closeIconData`、`description`、`constraints`、`scrollable` 组合壳
- `settings_page.dart` 的字体搜索弹窗不是纯 alert 形态，落地时需要自己在 `content` 里搭一个更完整的布局

建议实现方式：

- 简单确认/危险操作：统一改成 `showDialog` + `sf.AlertDialog`
- 复杂表单弹窗：仍走 `showDialog`，但把布局和关闭按钮自己拼在 `sf.AlertDialog.content` / `trailing` 中

### 3.3 `ShadPopoverController` / `ShadPopover` -> `sf.showPopover` + `sf.MenuPopup`

结论：`可行，但计划假设需要修正`

原型结论：

- `sf.showPopover` 在 Windows 语义下可正常弹出菜单
- `sf.MenuPopup` 能作为弹层容器使用

必须修正的计划假设：

- `sf.MenuPopup` 不是“把 `MenuButton` 直接塞进去”就能工作；完整菜单通常需要 `sf.MenuGroup(... builder: ... => sf.MenuPopup(...))`
- `shadcn_flutter` 仍然提供原生 `sf.PopoverController`
  - 不是旧 `ShadPopoverController`
  - 但它是新库自己的 API，可以直接使用，不属于兼容层
  - 公开状态是 `hasOpenPopover` / `openPopovers`，不是旧的 `isOpen`

主要风险：

- `project_list_pane.dart` 和 `window_frame.dart` 目前都把“按钮 hover 展示”与“popover 是否打开”绑在一起
- 如果完全改成一次性 `showPopover(...)`，需要自己同步 `_menuOpen` 状态
- 这类场景用新库原生 `sf.PopoverController` 可能更稳

建议实现方式：

- 一次性菜单、无开关状态依赖：用 `sf.showPopover`
- 需要监听打开/关闭状态的标题栏菜单、更多菜单：优先评估原生 `sf.PopoverController`
- 菜单体统一用 `sf.MenuGroup` + `sf.MenuPopup`

### 3.4 `ShadTextarea` / `ShadSelect` / `ShadOption` -> `sf.TextArea` / `sf.Select` / `sf.SelectPopup`

结论：`部分可行，其中 Select 是最大风险`

#### `sf.TextArea`

结论：`可行`

原型结论：

- `sf.TextArea` 可正常构建、输入、提交文本
- `minLines` / `maxLines` 适合替换 composer 的多行输入基本行为

主要差异：

- 没有旧 `ShadTextarea` 那种 `ShadDecoration.none` / `inputPadding` / `resizable: false` 组合形态
- 需要靠外层容器和项目 token 自己收口视觉样式

建议实现方式：

- composer 外框继续用项目自己的 `PanelCard` / token 容器
- `sf.TextArea` 只承担文本输入行为

#### `sf.Select` / `sf.SelectPopup`

结论：`可行，但不能按当前 _SelectorSelect<T> 直接平移`

必须修正的计划假设：

- `sf.Select` 是受控组件
  - 当前值：`value`
  - 变更回调：`onChanged`
  - 已选值渲染：`itemBuilder`
  - 弹层内容：`popup`
- 旧 `_SelectorSelect<T>` 依赖的这组 API 在新库里不存在：
  - `initialValue`
  - `selectedOptionBuilder`
  - `options`
  - `trailing` 自定义去掉默认箭头

关键风险：

- `sf.Select` 自带固定的 chevron trigger 区
- 当前业务用的是紧凑 `IdeChip` 触发器，这和 `sf.Select` 的默认 field 外壳不是 1:1 同构
- scratch 中尝试把 chip 直接塞给 `sf.Select` 时出现了布局压缩/溢出问题，说明正式迁移不能机械替换

建议实现方式：

- 如果接受 UI 变化：直接用 `sf.Select`
- 如果必须保留当前紧凑 chip 触发器：
  - 用项目自定义 trigger
  - 弹层内容复用 `sf.SelectPopup`
  - 外层由 `sf.showPopover` 或原生 `sf.PopoverController` 管理

结论上，`agent_pane_composer.dart` 的 selector 区必须单独设计，不应在阶段 4 批量替换时边改边试。

## 4. 对主计划的修正建议

主计划当前需要吸收以下修正：

1. 使用面统计更新为 `20` 个文件，不是 `19`
2. `ShadcnApp` 使用 `sf.ThemeMode`
3. `MenuPopup` 的实际落地模式应写成 `MenuGroup + MenuPopup`
4. `shadcn_flutter` 仍有原生 `sf.PopoverController`，可作为标题栏/更多菜单的直接新实现
5. `sf.Select` 不是旧 `ShadSelect` 的平移 API，`_SelectorSelect<T>` 必须重写
6. `sf.Select` 默认 trigger 带 chevron，不适合直接承接当前 `IdeChip` 方案

## 5. 建议的正式迁移顺序

建议在主计划顺序基础上，进一步明确以下优先级：

1. `pubspec.yaml`、`lib/src/app/app.dart`
2. `lib/src/ui/core/app_theme.dart`
3. `lib/src/ui/core/ide_colors.dart`
4. `lib/src/ui/core/ide_text_styles.dart`
5. `lib/src/ui/core/pane_widgets.dart`
6. `lib/src/ui/core/window_frame.dart`
7. `lib/src/ui/core/ide_context_menu.dart`
8. `lib/src/features/settings/presentation/settings_page.dart`
9. `lib/src/ui/features/ide/views/project_list_pane.dart`
10. `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart`
11. 其余 `agent_pane` part 文件
12. `lib/src/ui/features/ide/views/ide_home.dart`
13. widget tests

调整理由：

- 先完成 token 真源与 root theme 解耦，否则越往后改越容易重复返工
- `window_frame` / `ide_context_menu` / `project_list_pane` 都依赖新的 popover/menu 策略，应该连续推进
- `agent_pane_composer.dart` 单独压后，避免在 selector 策略没冻结前开始批量替换 agent 面板

## 6. 是否可以进入阶段 1

结论：`可以，但必须带着本文件中的修正进入`

理由：

- 四类关键 API 已经有可执行的新实现路径
- root app、dialog、popover 的不确定项已经被原型消除
- 最大风险点 `Select` 也已经被定位，不再是“未知”，而是“需要按自定义 trigger + popup 或接受新样式二选一”

进入阶段 1 前必须先冻结三项决定：

1. `sf.ThemeMode` + `sf` alias 规范
2. popover 菜单到底采用 `sf.showPopover` 还是原生 `sf.PopoverController`
3. composer selector 是否接受 `sf.Select` 默认 trigger；如果不接受，直接按“自定义 trigger + `sf.SelectPopup`”实现
