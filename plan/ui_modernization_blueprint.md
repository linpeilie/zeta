# Zeta IDE — 全局 UI/UX 现代化重构规划

> **版本**: v1.0  
> **日期**: 2026-07-08  
> **状态**: 待确认  
> **风格基调**: High-tech Minimalist · 长时间使用友好 · 桌面工具类应用

---

## A. 项目现状诊断

### A.1 技术栈概览

| 维度 | 当前状态 |
|------|----------|
| Flutter SDK | ≥ 3.12.2（现代版本，null-safe） |
| UI 组件库 | `shadcn_ui: ^0.55.0`（主力组件库） |
| 主题系统 | `IdeColors` ThemeExtension + `ShadThemeData` 双轨并行 |
| Markdown | `mixin_markdown_widget: 0.3.1` |
| 代码高亮 | `flutter_highlight: ^0.7.0` |
| 布局 | `multi_split_view: ^3.6.2`（已引入但未在主界面使用） |
| 窗口管理 | `window_manager: ^0.5.1` + `macos_window_utils: ^1.9.1` |
| 状态管理 | Flutter 内置（`ValueNotifier` / `ListenableBuilder`） |
| 路由 | 无框架，手动 `setState` 页面切换 |

**结论**: 技术栈现代，`shadcn_ui` 提供了良好的组件基础，适合在此之上构建统一的设计系统。无需引入额外依赖即可完成 UI 重构。

### A.2 核心问题诊断

#### 问题 1: 设计 Token 分散，缺少统一的间距/排版/动效规范

**代码证据**:

- `lib/src/ui/core/app_theme.dart` 中定义了全局常量 `idePanelGap = 8`、`idePanelRadius = 6`，但这仅是面板级间距。
- `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart` 中的圆角 `BorderRadius.circular(18)`、阴影 `blurRadius: 18`、内边距 `EdgeInsets.fromLTRB(14, 10, 8, 8)` 等均为行内硬编码。
- `lib/src/features/agent/presentation/widgets/agent_pane_cards.dart` 中 `BorderRadius.circular(8)`、`padding: EdgeInsets.all(10)` 等与其他位置不一致。
- `lib/src/ui/features/ide/views/project_list_pane.dart` 中 `_actionHitSize = 18`、`_actionIconSize = 16`、`_actionIconGap = 6` 以类内常量散落。
- `TextStyle` 散布全项目，`fontSize: 11`、`fontSize: 12`、`fontSize: 13` 等缺乏语义命名。
- 动画时长 `Duration(milliseconds: 120)`、`140`、`180` 各自为政，缺乏统一的 motion token。

**影响**: 视觉不一致，维护时容易引入偏差，新增页面需要反复查找"其他地方用了什么值"。

#### 问题 2: 公共组件抽象不完整，业务页面存在重复模式

**代码证据**:

- `lib/src/ui/core/pane_widgets.dart` 提供了 `PanelCard`、`Pane`、`EmptyState`、`StateLabel`、`PaneInteractiveSurface` 等基础组件——**这是良好的基础**。
- 但 `lib/src/ui/features/ide/views/ide_home.dart` 中的 `_RoundedPanel` 与 `PanelCard` 功能高度重叠，仅多了一个 `color` 回退逻辑。
- `_ActivityRail`、`_ActionIcon` 是 `ide_home.dart` 的私有组件，但其交互模式（图标 + 选中态 + hover）在多处出现。
- `_HorizontalResizeHandle`、`_VerticalResizeHandle` 是通用的可拖拽分隔条，应提升为公共组件。
- `agent_pane_composer.dart` 中的 `_SelectorChip` 是紧凑胶囊按钮，但被限制在 `part` 文件中不可复用。
- 上下文菜单在 `project_list_pane.dart` 中手工拼装 `DecoratedBox` + `BoxShadow` + `Column` 实现，没有使用统一的下拉菜单组件。

**影响**: 新功能开发时容易"再造轮子"，修改圆角/间距/hover 样式时需要多处同步。

#### 问题 3: 颜色系统虽有 ThemeExtension，但语义层级不够完整

**代码证据**:

- `lib/src/ui/core/ide_colors.dart` 定义了 `IdeColors` 包含 12 个语义色值，深色/浅色各一套——**基础良好**。
- 但缺少以下高频语义色: `error`（当前仅有 `warning`）、`success`、`info`、`surfaceElevated`（多层叠加表面）、`textSecondary`（与 `mutedText` 有别）。
- 业务代码中大量使用 `.withValues(alpha: 0.xx)` 进行运行时透明度计算（`agent_pane_cards.dart` 中出现 20+ 处），这些应该预计算为语义 token。
- `shadColorSchemeFromIdeColors` 将 `IdeColors` 映射到 `ShadColorScheme`，但 custom map 中的字符串 key（`'frame'`、`'surface'` 等）缺乏类型安全。

**影响**: 当需要新增颜色（如 `error` 红色、`info` 蓝色）或微调 alpha 层级时，需要逐文件搜索替换。

---

## B. 现代设计系统定义

### B.1 色彩系统

> 风格: 低饱和、高信息密度、长时间注视友好。强调色克制使用。

#### 深色主题 (Dark)

| Token | Hex | 用途 |
|-------|-----|------|
| `background` | `#131313` | 窗口最外层 / scaffold |
| `surface` | `#1A1A1A` | 卡片、浮层底色 |
| `surfaceElevated` | `#222222` | 面板、编辑器底色 |
| `surfaceOverlay` | `#282828` | 弹出层、对话框底色 |
| `border` | `#2E2E2E` | 常规边框 / 分隔线 |
| `borderSubtle` | `#252525` | 低对比边框 |
| `primary` | `#4FB286` | 主强调色 (保持现有绿色) |
| `primaryMuted` | `#4FB286` @ 18% | 选中态背景 |
| `secondary` | `#5B9BD5` | 信息色 / 辅助强调 |
| `textPrimary` | `#E8E8E8` | 主文本 |
| `textSecondary` | `#9DA3A6` | 次要文本 / 标签 |
| `textTertiary` | `#6B7280` | 占位符 / 禁用态 |
| `error` | `#E06C75` | 错误状态 |
| `warning` | `#E6B450` | 警告 / 待审批 (保持现有) |
| `success` | `#4FB286` | 成功 / 完成态 |
| `info` | `#5B9BD5` | 信息提示 |

#### 浅色主题 (Light)

| Token | Hex | 用途 |
|-------|-----|------|
| `background` | `#F5F6F8` | 窗口最外层 |
| `surface` | `#FFFFFF` | 卡片底色 |
| `surfaceElevated` | `#FBFBFC` | 面板底色 |
| `surfaceOverlay` | `#FFFFFF` | 弹出层底色 |
| `border` | `#E4E6EB` | 常规边框 |
| `borderSubtle` | `#ECEEF2` | 低对比边框 |
| `primary` | `#1E9E58` | 主强调色 (保持现有) |
| `primaryMuted` | `#1E9E58` @ 10% | 选中态背景 |
| `secondary` | `#2B7AC5` | 信息色 |
| `textPrimary` | `#111827` | 主文本 |
| `textSecondary` | `#6B7280` | 次要文本 |
| `textTertiary` | `#9CA3AF` | 占位符 |
| `error` | `#DC2626` | 错误 |
| `warning` | `#B45309` | 警告 (保持现有) |
| `success` | `#1E9E58` | 成功 |
| `info` | `#2B7AC5` | 信息 |

### B.2 排版系统

> 基于 4px 基线网格，密集但可读。UI 字体跟随用户设置；代码字体默认 JetBrainsMono。

| 语义名称 | 字号 | 行高 | 字重 | 用途 |
|----------|------|------|------|------|
| `displayLarge` | 18px | 1.3 | w700 | 顶级页面标题（极少用） |
| `displaySmall` | 15px | 1.35 | w700 | 区域标题 / 设置分区 |
| `titleLarge` | 13px | 1.35 | w700 | 面板标题 / Thread 标题 |
| `titleSmall` | 12px | 1.35 | w600 | 行标题 / 工具调用摘要 |
| `bodyMedium` | 12px | 1.42 | w400 | 正文 / 消息内容 |
| `bodySmall` | 11px | 1.35 | w400 | 辅助信息 / 时间标签 |
| `caption` | 10px | 1.3 | w500 | 极小辅助标签 / token 统计 |
| `codeMedium` | 12px | 1.35 | w500 | 代码块正文 |
| `codeSmall` | 11px | 1.35 | w400 | 工具输出 / diff 内容 |

### B.3 间距系统

> 以 4px 为基础步进，8px 为标准间距单位。

| Token | 值 | 用途 |
|-------|------|------|
| `space2` | 2px | 图标与微标签间距 |
| `space4` | 4px | 紧凑内边距、行间距 |
| `space6` | 6px | 组件内元素间距 |
| `space8` | 8px | 标准组件间距、面板间 gap |
| `space10` | 10px | 卡片内边距 |
| `space12` | 12px | 区块标题与内容间距 |
| `space16` | 16px | 区域级间距 |
| `space20` | 20px | 页面边距 |
| `space24` | 24px | 大区块分隔 |
| `space32` | 32px | 页面级大间距 |

### B.4 组件形态规范

| 维度 | 规范 |
|------|------|
| 圆角（小） | 4px — 小按钮、胶囊标签 |
| 圆角（中） | 6px — 面板、卡片、输入框 (保持现有 `idePanelRadius`) |
| 圆角（大） | 12px — 对话框、弹出层 |
| 圆角（特大） | 18px — 输入面板（Composer）|
| 边框宽度 | 1px，颜色使用 `border` token |
| 阴影 | 仅弹出层使用，`0 4px 12px rgba(0,0,0,0.12)` 深色 / `0 4px 12px rgba(0,0,0,0.06)` 浅色 |
| Hover 态 | `border` @ 18% alpha（深色）/ 30% alpha（浅色），120ms ease-out |
| Pressed 态 | `border` @ 28% alpha（深色）/ 40% alpha（浅色），60ms |
| Selected 态 | `primary` @ 18% alpha（深色）/ 10% alpha（浅色）|
| Focus 态 | `primary` ring @ 70% alpha，2px offset |
| 动画标准时长 | fast: 100ms, normal: 160ms, slow: 260ms |
| 动画曲线 | 默认 `Curves.easeOut`，弹出 `Curves.easeOutCubic` |

---

## C. Atomic Design 基础组件抽离清单

### C.1 `IdeSpacing` — 间距常量类

> **解决的问题**: 间距值散落在各文件中，`const EdgeInsets.all(10)` / `const SizedBox(width: 8)` 等无语义。  
> **统一属性**: 所有 4px 步进间距值、页面级/区块级/组件级 padding 预设。  
> **替换目标**: 全项目中的硬编码 `EdgeInsets` 和 `SizedBox` 间距。

### C.2 `IdeTextStyles` — 排版工厂

> **解决的问题**: `shadTheme.textTheme.h4.copyWith(fontWeight: FontWeight.w700)` 模式在 20+ 处重复出现。  
> **统一属性**: 基于 B.2 定义的语义排版，接受 `BuildContext` 自动解析当前主题色。  
> **替换目标**: 所有 `shadTheme.textTheme.xx.copyWith(...)` 内联样式。

### C.3 `IdeResizeHandle` — 可拖拽分隔条

> **解决的问题**: `_HorizontalResizeHandle` 和 `_VerticalResizeHandle` 在 `ide_home.dart` 中是私有组件。  
> **统一属性**: 方向（水平/垂直）、光标、命中区域宽度、hover 高亮色。  
> **替换目标**: `ide_home.dart` 中两个私有 resize handle 类。

### C.4 `IdeActivityRail` — 图标活动栏

> **解决的问题**: `_ActivityRail` + `_ActionIcon` 组合模式在 `ide_home.dart` 中以私有类形式存在，不可复用。  
> **统一属性**: 图标列表、选中态（中性 `selectedSurface` + `accentForeground`，无侧边指示条）、hover 反馈、tooltip、语义标签、紧凑尺寸。  
> **替换目标**: `ide_home.dart` 中的 `_ActivityRail` 和 `_ActionIcon`。

### C.5 `IdeContextMenu` — 上下文菜单

> **解决的问题**: `project_list_pane.dart` 中手工拼装 `DecoratedBox` + `BoxShadow` + `Column` 构建菜单弹层。  
> **统一属性**: 背景色、圆角、阴影、边框、菜单项高度、hover 样式、分隔线。  
> **替换目标**: `_ProjectTileState` 中 `_moreMenuController.isOpen` 对应的手工弹层。

### C.6 `IdeChip` — 胶囊标签/选择器

> **解决的问题**: `_SelectorChip` 在 `agent_pane_composer.dart` 的 `part` 文件中，无法被其他页面引用。  
> **统一属性**: 前置图标、标签文本、下拉箭头、尺寸、底色、边框。  
> **替换目标**: Composer 区域的 `_SelectorChip` 及其他潜在使用场景。

### C.7 `IdeCollapsibleCard` — 可折叠信息卡片

> **解决的问题**: 命令组卡片、文件编辑组卡片、计划消息卡片都各自实现了"标题行 + 展开/折叠"模式。  
> **统一属性**: 标题行布局（图标 + 文本 + 摘要 + 展开箭头）、展开/折叠动画、hover 区域、RepaintBoundary。  
> **替换目标**: `_AgentCommandGroupCard`、`_AgentFileEditGroupCard`、`_AgentPlanMessageCard` 的外壳结构。

### C.8 `IdeStatusCard` — 语义状态卡片

> **解决的问题**: 审批卡片、历史事件卡片都各自硬编码 `BoxDecoration` + 语义色 + padding。  
> **统一属性**: 语义级别（info/warning/error/success）、图标、标题行、描述区、操作区。  
> **替换目标**: `_AgentPermissionCard`、`_AgentHistoryEventCard` 的装饰壳。

---

## D. 分步实施路径

### Phase 1: 基础设施建设（预估 2-3 轮对话）

**目标**: 建立 Design Token 层，确保后续组件和页面重构有统一规范可依赖。

| # | 任务 | 涉及文件 | 说明 |
|---|------|----------|------|
| 1.1 | 扩展 `IdeColors` 语义色值 | `lib/src/ui/core/ide_colors.dart` | 新增 `error`, `success`, `info`, `surfaceElevated`, `surfaceOverlay`, `borderSubtle`, `textSecondary`, `textTertiary` 等 token |
| 1.2 | 更新 `shadColorSchemeFromIdeColors` 映射 | `lib/src/ui/core/ide_colors.dart` | 将新 token 正确映射到 ShadColorScheme |
| 1.3 | 新建 `IdeSpacing` 常量类 | `lib/src/ui/core/ide_spacing.dart` *(新)* | 4px 步进间距 + 常用 EdgeInsets 预设 |
| 1.4 | 新建 `IdeTextStyles` 排版工厂 | `lib/src/ui/core/ide_text_styles.dart` *(新)* | 基于上表的语义排版，替代零散 `.copyWith()` |
| 1.5 | 新建 `IdeMotion` 动效常量 | `lib/src/ui/core/ide_motion.dart` *(新)* | `durationFast`, `durationNormal`, `durationSlow`, `curveDefault`, `curvePopup` |
| 1.6 | 更新 `buildShadTheme` 使用新 Token | `lib/src/ui/core/app_theme.dart` | 将硬编码字号/字重替换为 Token 引用 |
| 1.7 | `dart format .` + `flutter analyze` | — | 确保无破坏性变更 |

**验收标准**: 现有页面外观不变，新 Token 可在后续 Phase 使用。

### Phase 2: 核心骨架重构（预估 3-4 轮对话）

**目标**: 将 `ide_home.dart` 中的私有布局组件提升为公共组件，统一应用骨架。

| # | 任务 | 涉及文件 | 说明 |
|---|------|----------|------|
| 2.1 | 提取 `IdeResizeHandle` | `lib/src/ui/core/ide_resize_handle.dart` *(新)* | 替换 `_HorizontalResizeHandle` / `_VerticalResizeHandle` |
| 2.2 | 提取 `IdeActivityRail` + `IdeRailAction` | `lib/src/ui/core/ide_activity_rail.dart` *(新)* | 替换 `_ActivityRail` / `_ActionIcon` |
| 2.3 | 统一 `PanelCard` 消除 `_RoundedPanel` 冗余 | `lib/src/ui/core/pane_widgets.dart`, `ide_home.dart` | 合并为一个组件 |
| 2.4 | 提取 `IdeContextMenu` | `lib/src/ui/core/ide_context_menu.dart` *(新)* | 替换 `project_list_pane.dart` 手工弹层 |
| 2.5 | 将 `ide_home.dart` 的布局逻辑简化 | `lib/src/ui/features/ide/views/ide_home.dart` | 使用新公共组件，减少文件内私有类数量 |
| 2.6 | 提取 `IdeChip` | `lib/src/ui/core/ide_chip.dart` *(新)* | 替换 `_SelectorChip` |
| 2.7 | 响应式布局审查 | `ide_home.dart`, `settings_page.dart` | 确保窄窗口下面板折叠正确、overlay 模式可用 |
| 2.8 | `dart format .` + `flutter analyze` + `flutter test` | — | 确保行为不变 |

**验收标准**: `ide_home.dart` 从 ~810 行缩减至 ~400 行，所有私有布局组件已公共化。

### Phase 3: 业务页面渐进替换（预估 3-5 轮对话）

**目标**: 以 Agent 面板和设置页为样板，用新设计系统替换硬编码样式。

| # | 任务 | 涉及文件 | 说明 |
|---|------|----------|------|
| 3.1 | 提取 `IdeCollapsibleCard` | `lib/src/ui/core/ide_collapsible_card.dart` *(新)* | 统一折叠卡片模式 |
| 3.2 | 提取 `IdeStatusCard` | `lib/src/ui/core/ide_status_card.dart` *(新)* | 统一语义状态卡片 |
| 3.3 | 重构 `agent_pane_cards.dart` | `lib/src/features/agent/presentation/widgets/agent_pane_cards.dart` | 使用 `IdeCollapsibleCard`、`IdeStatusCard`、`IdeTextStyles` |
| 3.4 | 重构 `agent_pane_messages.dart` | `lib/src/features/agent/presentation/widgets/agent_pane_messages.dart` | 替换硬编码 `TextStyle`、`EdgeInsets`、`BoxDecoration` |
| 3.5 | 重构 `agent_pane_composer.dart` | `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart` | 使用 `IdeChip`、`IdeSpacing`、`IdeMotion` |
| 3.6 | 重构 `agent_pane_styles.dart` | `lib/src/features/agent/presentation/widgets/agent_pane_styles.dart` | Markdown 主题和代码样式改用 `IdeTextStyles` 驱动 |
| 3.7 | 重构 `project_list_pane.dart` | `lib/src/ui/features/ide/views/project_list_pane.dart` | 使用 `IdeContextMenu`、统一间距和样式 Token |
| 3.8 | 重构 `file_tree_pane.dart` | `lib/src/features/workspace/presentation/file_tree_pane.dart` | 统一样式 Token、行高常量 |
| 3.9 | 重构 `settings_page.dart` | `lib/src/features/settings/presentation/settings_page.dart` | 使用新 Token 和公共组件 |
| 3.10 | 全局审计：消除剩余硬编码样式 | 全项目 | 搜索 `TextStyle(`、`EdgeInsets.` 等模式，替换为 Token 引用 |
| 3.11 | `dart format .` + `flutter analyze` + `flutter test` | — | 最终验证 |

**验收标准**: 全项目无直接硬编码 `TextStyle`（语义排版以外），间距统一使用 `IdeSpacing`，颜色统一使用 `IdeColors` 扩展 Token。

---

## E. 性能与可维护性要求

### E.1 渲染性能

| 要求 | 具体做法 | 现有状态 |
|------|----------|----------|
| 长列表懒加载 | `ListView.builder` | **已满足** — `project_list_pane.dart`、`file_tree_pane.dart` 均使用 builder |
| 流式消息滚动 | `SingleChildScrollView` + `Column` | **当前方案可接受** — Agent 面板注释说明了选择理由（避免 SliverList 导致的 maxScrollExtent 跳动） |
| RepaintBoundary | 重量级区域隔离 | **部分已有** — `agent_pane_cards.dart` 中展开区域已添加；应扩展到 Markdown 渲染区和代码高亮区 |
| ValueKey | 列表行稳定标识 | **已满足** — 全项目列表行均使用 `ValueKey` |

### E.2 状态管理

| 要求 | 具体做法 | 现有状态 |
|------|----------|----------|
| 避免大范围 rebuild | 局部 `ListenableBuilder` + `ValueListenableBuilder` | **已满足** — `agent_pane.dart` 中 header、history、live turn、composer 各自独立监听 |
| `const` 构造器 | 尽可能标记 `const` | **大部分已满足**，部分新组件可进一步优化 |
| disposed 检查 | 异步完成前检查 `mounted` | **已满足** — 关键位置均有 `mounted` 守卫 |

### E.3 可维护性

| 要求 | 做法 |
|------|------|
| 主题集中管理 | 所有色值、排版、间距、动效通过 `lib/src/ui/core/` 下的 Token 类管理，**禁止新代码中出现裸 `Color(0xFFxxxxxx)`** |
| 组件可测试 | 公共组件提供 `Key` 参数和语义标签，支持 widget test |
| 文档对齐 | Phase 1 完成后更新 `docs/design_document.md` 中的设计系统章节 |
| 桌面可用性 | 所有交互组件支持 hover、focus、keyboard navigation；`FocusableActionDetector` 模式已在 `PaneInteractiveSurface` 中就绪 |

### E.4 迁移安全

| 原则 | 说明 |
|------|------|
| 渐进替换 | 每个 Phase 完成后运行 `flutter analyze` + `flutter test`，确保不破坏现有行为 |
| 向后兼容 | `IdeColors.dark` / `IdeColors.light` 的旧 const 字段保留，新增字段使用默认值回退 |
| 废弃标记 | 被替换的旧常量/类标记 `@Deprecated`，留存 1-2 个版本后清理 |
| 不引入新依赖 | 全部基于 Flutter 内置 + 已有 `shadcn_ui` 完成 |

---

## F. 新增文件规划汇总

```
lib/src/ui/core/
├── app_theme.dart              # (已有) 更新 Token 引用
├── ide_colors.dart             # (已有) 扩展语义色值
├── ide_spacing.dart            # (新) 间距常量
├── ide_text_styles.dart        # (新) 排版工厂
├── ide_motion.dart             # (新) 动效常量
├── ide_resize_handle.dart      # (新) 可拖拽分隔条
├── ide_activity_rail.dart      # (新) 图标活动栏
├── ide_context_menu.dart       # (新) 上下文菜单
├── ide_chip.dart               # (新) 胶囊标签
├── ide_collapsible_card.dart   # (新) 可折叠卡片
├── ide_status_card.dart        # (新) 语义状态卡片
├── pane_widgets.dart           # (已有) 统一 PanelCard
└── window_frame.dart           # (已有) 保持不变
```

---

## G. 建议下一步

1. **确认本规划的范围和优先级** — 如果对色值、排版、间距有具体偏好，请在此时提出。
2. **进入 Phase 1** — 从 Design Token 基础设施开始，新建 `IdeSpacing`、`IdeTextStyles`、`IdeMotion`，扩展 `IdeColors`。
3. Phase 1 完成后运行 `flutter analyze` + `flutter test` 验证，再进入 Phase 2。

> **等待您的确认后开始实施。**
