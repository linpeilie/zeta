# Zeta 项目 shadcn_ui 全量迁移规划书

> **版本**：v1.0  
> **日期**：2026-07-08  
> **适用范围**：`lib/` 全部 UI 层代码，约 15 个含 `import 'package:flutter/material.dart'` 的文件  
> **目标框架**：`shadcn_ui ^0.55.0` + `macos_window_utils ^1.9.1`  
> **迁移策略**：增量五阶段，每阶段结束须通过编译验证 + 运行时冒烟测试

---

## 〇、现状快照

### 0.1 项目概况

| 维度 | 现状 |
|---|---|
| 入口 | `MaterialApp`（`lib/src/app/app.dart`），通过 `ValueListenableBuilder<AppearanceSettings>` 响应主题模式切换 |
| 主题体系 | `buildIdeTheme()` 构造 `ThemeData`（M3），注册 `IdeColors` + `IdeTypography` 两个 `ThemeExtension` |
| 调色板 | `IdeColors`（12 色：frame / surface / panel / editor / border / mutedText / accent / warning / accentForeground / windowHover / windowIcon / closeHover），深浅各一套 |
| 窗口管理 | `window_manager ^0.5.1`：隐藏标题栏、启动尺寸、最小化/最大化/关闭 |
| 布局结构 | `WindowFrame` → `IdeHome`（五列：左 ActivityRail、左面板、Agent 主编辑区、右面板、右 ActivityRail） |
| 平台适配 | macOS 保留交通灯按钮；Windows/Linux 自绘最小化/最大化/关闭按钮 |
| 文件树 | `third_party/flutter_treeview`（本地 fork）→ 本次迁移中用 shadcn 重写 |
| Agent 对话渲染 | `mixin_markdown_widget` + `flutter_highlight` → 不纳入本次迁移范围，后续单独处理 |

### 0.2 Material 组件使用清单（需迁移）

| Material 组件 | 出现位置 | 数量 | 目标 shadcn 组件 |
|---|---|---|---|
| `MaterialApp` | `app.dart` | 1 | `ShadApp` |
| `Scaffold` | `ide_home.dart` | 1 | 移除（纯 ShadApp 不需要） |
| `TextButton` / `TextButton.icon` | `project_list_pane.dart`、`agent_pane_sections.dart`、`agent_pane_cards.dart`、`agent_pane_messages.dart` | 7 | `ShadButton.ghost` / `ShadButton.link` |
| `FilledButton.icon` | `agent_pane_cards.dart` | 1 | `ShadButton` (primary) |
| `TextField` | `settings_page.dart`（字体搜索）、`agent_pane_composer.dart`（消息输入） | 2 | `ShadInput` / `ShadTextArea`（多行场景） |
| `PopupMenuButton` | `agent_pane_composer.dart`（3 处）、`window_frame.dart`（1 处） | 4 | `ShadSelect` / `ShadPopover` |
| `showDialog` / `Dialog` | `settings_page.dart`（字体选择器） | 1 | `showShadDialog` / `ShadDialog` |
| `ListTile` | `settings_page.dart`（字体列表项） | 1 | 自定义 `InkWell` 行或 `ShadButton.ghost` |
| `IconButton` | 多处（6+） | 6+ | `ShadIconButton` |
| `CircularProgressIndicator` | `settings_page.dart`、`file_tree_pane.dart`、`agent_pane_sections.dart`、`project_list_pane.dart` | 4 | `ShadProgress` 或保留（shadcn 无 spinner 则自绘） |
| `Divider` | `agent_pane_messages.dart` | 2 | `ShadSeparator` |
| `SnackBar` / `ScaffoldMessenger` | `ide_home.dart`、`settings_page.dart` | 3 | `ShadSonner`（Toast 系统） |
| `InkWell` + `Material(color: transparent)` | 多处自绘交互面（ActionIcon、SettingsNavItem 等） | 15+ | 用 `ShadButton` 变体或保留自绘（仅换色） |

### 0.3 不需要迁移的部分

- **领域层 / 数据层 / 应用层**：`lib/src/features/*/domain`、`data`、`application` 完全不含 UI 引用，零改动。
- **Agent 对话渲染**：`mixin_markdown_widget` / `flutter_highlight` 渲染管线后续独立处理。
- **平台原生目录**：`macos/`、`windows/`、`linux/` 除 macOS Info.plist 最低部署版本外不改动。

---

## 一、阶段一：依赖与环境准备

### 1.1 核心改造任务

#### 1.1.1 引入新依赖

```yaml
# pubspec.yaml dependencies 新增
shadcn_ui: ^0.55.0
macos_window_utils: ^1.9.1
```

执行：

```sh
flutter pub add shadcn_ui
flutter pub add macos_window_utils
```

#### 1.1.2 检查 SDK 约束

`shadcn_ui 0.55.0` 要求 Dart SDK ≥ 3.11，`macos_window_utils 1.9.1` 要求 Flutter SDK ≥ 3.27.0。当前项目 `sdk: ^3.12.2` 满足。确认本地 Flutter channel 版本 ≥ 3.32（stable 2026 年 7 月已到 3.32+），无需降级。

#### 1.1.3 macOS 最低部署目标

`macos_window_utils` 要求 macOS deployment target ≥ 10.14.6。检查并更新 `macos/Runner.xcodeproj/project.pbxproj` 中的 `MACOSX_DEPLOYMENT_TARGET`（Flutter 默认通常已满足 ≥ 10.14，但需要确认）。

#### 1.1.4 依赖冲突排查

以下现有依赖需要逐一检查与 `shadcn_ui` 的兼容性：

| 现有依赖 | 风险点 | 处置策略 |
|---|---|---|
| `window_manager ^0.5.1` | 与 `macos_window_utils` 同时操作 NSWindow，初始化顺序敏感 | 共存：先 `window_manager.ensureInitialized()` 再 `WindowManipulator.initialize()` |
| `multi_split_view ^3.6.2` | 目前未在 UI 中使用（grep 无引用） | 确认是否可移除；若保留则不影响 |
| `flutter_treeview`（本地 fork） | 内部使用 Material `Theme.of(context)` | 阶段五重写时移除 |
| `mixin_markdown_widget 0.3.1` | 可能依赖 Material widgets | 本次不迁移，仅确保不因 ShadApp 缺少 Scaffold 而崩溃 |
| `flutter_highlight ^0.7.0` | 依赖 Material `Theme` 取色 | 同上，确保回退色可用 |
| `system_fonts ^1.0.1` | 纯 dart:ffi，无 UI 依赖 | 无冲突 |

#### 1.1.5 Lucide Icons 准备

`shadcn_ui` 内置 `lucide_icons` 作为图标体系。项目当前使用 `Icons.*`（Material Icons）。阶段一**不替换图标**，仅确认 `lucide_icons` 可正常导入。图标全量替换放在阶段三。

#### 1.1.6 创建迁移兼容辅助层

在 `lib/src/ui/core/` 下新建 `shad_theme_bridge.dart`，作为过渡期的主题桥接：

```dart
/// 迁移过渡桥接：将 ShadColorScheme 映射回 IdeColors 语义，
/// 使尚未迁移的组件仍可通过 IdeColors.of(context) 取色。
/// 全量迁移完成后此文件删除。
```

该桥接层让旧组件和新组件在过渡期内共享同一套颜色值，避免出现"半新半旧"的视觉撕裂。

### 1.2 验证标准

| 检查项 | 通过标准 |
|---|---|
| `flutter pub get` | 零错误退出 |
| `flutter analyze` | 零 error（允许现有 warning / info） |
| `flutter build macos --debug` | 编译成功 |
| `flutter build windows --debug` | 编译成功 |
| `flutter build linux --debug` | 编译成功 |
| `flutter test` | 现有测试全部通过 |
| 运行时 | 应用启动无崩溃，UI 外观不变（新依赖未使用） |

### 1.3 涉及文件

| 文件 | 改动类型 |
|---|---|
| `pubspec.yaml` | 新增依赖 |
| `macos/Runner.xcodeproj/project.pbxproj` | 更新 deployment target（如需） |
| `lib/src/ui/core/shad_theme_bridge.dart` | 新建桥接工具 |

### 1.4 回滚方案

移除 `shadcn_ui` 和 `macos_window_utils` 依赖，`flutter pub get` 即可回滚。

---

## 二、阶段二：全局入口与多平台主题适配

### 2.1 核心改造任务

#### 2.1.1 构造 ShadThemeData 双主题

将当前 `IdeColors.dark` / `IdeColors.light` 的 12 色映射为 `ShadColorScheme`。shadcn 的 `ShadSlateColorScheme` 提供了一套 Zinc/Slate/Gray 等预设，但 zeta 有自己的品牌调色板（以 `#4FB286` 绿色为强调色），因此需要自定义 `ShadColorScheme`。

**颜色映射表**（核心字段）：

| IdeColors 字段 | ShadColorScheme 字段 | 深色值 | 浅色值 |
|---|---|---|---|
| `frame` | `background` | `#171717` | `#F5F6F8` |
| `surface` | `card` | `#1F1F1F` | `#FFFFFF` |
| `panel` | `popover` | `#242424` | `#FFFFFF` |
| `editor` | `muted` | `#191919` | `#FBFBFC` |
| `border` | `border` | `#343434` | `#E4E6EB` |
| `mutedText` | `mutedForeground` | `#9DA3A6` | `#6B7280` |
| `accent` | `primary` / `ring` | `#4FB286` | `#1E9E58` |
| `warning` | `destructive`（或扩展） | `#E6B450` | `#B45309` |

```dart
ShadThemeData(
  brightness: Brightness.dark,
  colorScheme: ShadColorScheme(
    background: Color(0xFF171717),
    foreground: Color(0xFFE8E8E8),
    card: Color(0xFF1F1F1F),
    cardForeground: Color(0xFFE8E8E8),
    popover: Color(0xFF242424),
    popoverForeground: Color(0xFFE8E8E8),
    primary: Color(0xFF4FB286),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFF2A2A2A),
    secondaryForeground: Color(0xFFE8E8E8),
    muted: Color(0xFF191919),
    mutedForeground: Color(0xFF9DA3A6),
    accent: Color(0xFF4FB286),
    accentForeground: Color(0xFFFFFFFF),
    destructive: Color(0xFFD84E4E),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFF343434),
    input: Color(0xFF343434),
    ring: Color(0xFF4FB286),
    selection: Color(0xFF4FB286).withOpacity(0.18),
  ),
)
```

#### 2.1.2 替换 MaterialApp 为 ShadApp

`lib/src/app/app.dart` 的 `build` 方法从：

```dart
return MaterialApp(
  debugShowCheckedModeBanner: false,
  title: appTitle,
  theme: buildIdeTheme(brightness: Brightness.light, ...),
  darkTheme: buildIdeTheme(brightness: Brightness.dark, ...),
  themeMode: settings.themeMode,
  home: IdeHome(...),
);
```

改为：

```dart
return ShadApp(
  debugShowCheckedModeBanner: false,
  title: appTitle,
  theme: _buildShadTheme(Brightness.light, settings),
  darkTheme: _buildShadTheme(Brightness.dark, settings),
  themeMode: settings.themeMode,
  home: IdeHome(...),
);
```

> **关键风险**：纯 `ShadApp` 不内置 `Scaffold`、`ScaffoldMessenger`、`DefaultTextStyle` 等 Material scaffold。当前 `IdeHome.build()` 中 `return Scaffold(body: body)` 以及 `ScaffoldMessenger.of(context).showSnackBar(...)` 都将失效。
>
> **处置**：
> - 移除 `Scaffold`，直接用 `ColoredBox` / `DecoratedBox` 包裹主体（shadcn 的 `ShadApp` 已提供 `backgroundColor`）。
> - 将 `SnackBar` / `ScaffoldMessenger` 替换为 shadcn 的 `ShadSonner` toast 体系（可放到阶段四，此处先临时包一层 `Material` widget 以不报错）。

#### 2.1.3 桥接 IdeColors 到 ShadColorScheme

在 `shad_theme_bridge.dart` 中实现双向桥接，使尚未迁移到 shadcn 的组件仍可通过旧 API 取色：

```dart
/// 从 ShadTheme 中提取颜色，构造出等价的 IdeColors。
/// 在过渡期间，旧组件通过 IdeColors.of(context) 取色仍然有效；
/// 当全部组件迁移完成后，删除此桥接和 IdeColors 类。
IdeColors ideColorsFromShadTheme(ShadThemeData theme) { ... }
```

同时在 `ShadApp` 的 builder 中通过 `Theme` widget 注入 `IdeColors` 扩展，保持向下兼容。

#### 2.1.4 macOS 毛玻璃初始化

在 `lib/src/app/window_bootstrap.dart` 中，针对 macOS 平台追加 vibrancy 初始化：

```dart
if (Platform.isMacOS) {
  await WindowManipulator.initialize(enableWindowDelegate: true);
  // 窗口全透明，Flutter 内容浮于系统毛玻璃之上
  await WindowManipulator.makeWindowFullyTransparent();
  // 使内容延伸至标题栏区域
  await WindowManipulator.makeTitlebarTransparent();
  await WindowManipulator.enableFullSizeContentView();
  // 隐藏标题文字（由 Flutter 自绘）
  await WindowManipulator.hideTitle();
  // 设置毛玻璃材质
  await WindowManipulator.setMaterial(
    NSVisualEffectViewMaterial.sidebar,
  );
}
```

#### 2.1.5 多平台背景策略

| 平台 | 背景策略 |
|---|---|
| **macOS** | 窗口全透明 → 系统 NSVisualEffectView 负责毛玻璃 → Flutter 各面板使用**半透明**背景色叠加（`panel.withOpacity(0.65)`），透出底层毛玻璃质感 |
| **Windows** | `ShadApp.backgroundColor` 设为 `ShadColorScheme.background`，不透明纯色 |
| **Linux** | 同 Windows，不透明纯色 |

需要在主题构建中为 macOS 提供一套带透明度的面板色变体：

```dart
/// macOS 毛玻璃模式下面板使用半透明背景
Color panelColor(BuildContext context) {
  if (Platform.isMacOS) {
    return ShadTheme.of(context).colorScheme.popover.withOpacity(0.65);
  }
  return ShadTheme.of(context).colorScheme.popover;
}
```

#### 2.1.6 VisualDensity 与桌面端排版紧凑度

当前 `buildIdeTheme` 设置了 `visualDensity: VisualDensity.compact`。在 ShadApp 中需要通过 `ShadThemeData` 的排版参数保持同等紧凑度：

- 基础文字 `bodyMedium: 12px`、`bodySmall: 11px` → 映射到 `ShadTextTheme` 的 `p` / `small` / `muted`
- `IdeTypography.codeFontFamily` → 继续通过 `ThemeExtension` 挂载（shadcn 不管理代码字体）

### 2.2 验证标准

| 检查项 | 通过标准 |
|---|---|
| `flutter pub get` | 零错误 |
| `flutter analyze` | 零 error |
| 三平台编译 | 均成功 |
| macOS 运行 | 窗口启动后可见系统桌面壁纸透出的毛玻璃效果；面板浮于毛玻璃之上 |
| Windows / Linux 运行 | 窗口背景为 shadcn slate 暗色 / 亮色纯色，无透明 |
| 主题切换 | 浅色↔深色↔跟随系统 三种模式均正常，颜色无断裂 |
| 字体设置 | 界面字体 / 代码字体切换仍正常生效 |
| 旧组件取色 | 通过 `IdeColors.of(context)` 取色仍返回正确值（桥接生效） |

### 2.3 涉及文件

| 文件 | 改动类型 |
|---|---|
| `lib/src/app/app.dart` | 重构：`MaterialApp` → `ShadApp`，注入双主题 |
| `lib/src/ui/core/app_theme.dart` | 重构：新增 `buildShadTheme()` 函数，保留 `buildIdeTheme()` 标记 `@Deprecated` |
| `lib/src/ui/core/ide_colors.dart` | 修改：`of()` 回退逻辑增加从 `ShadTheme` 桥接 |
| `lib/src/ui/core/shad_theme_bridge.dart` | 实现桥接逻辑 |
| `lib/src/app/window_bootstrap.dart` | 新增 macOS vibrancy 初始化 |
| `lib/src/ui/features/ide/views/ide_home.dart` | 移除 `Scaffold` 外壳（或临时保留 Material 包装） |
| `lib/src/ui/core/window_frame.dart` | 调整背景色取色路径 |

### 2.4 回滚方案

还原 `app.dart` 使用 `MaterialApp`；删除 `window_bootstrap.dart` 中 macOS vibrancy 代码；删除 `shad_theme_bridge.dart`。

---

## 三、阶段三：基础原子组件的全局批量替换

### 3.1 核心改造任务

#### 3.1.1 按钮类组件替换

**映射规则**：

| 原 Material 组件 | → shadcn 组件 | 视觉等价 |
|---|---|---|
| `TextButton` | `ShadButton.ghost` | 无背景，仅文字 + hover 态 |
| `TextButton.icon` | `ShadButton.ghost` + `icon` 参数 | 带图标的 ghost 按钮 |
| `FilledButton.icon` | `ShadButton` (primary variant) + `icon` | 实心主色按钮 |
| `IconButton` | `ShadIconButton` | 图标按钮 |
| `InkWell` + `Material(transparent)` 自绘按钮 | `ShadButton.ghost` / `ShadButton.outline` 或保持自绘 | 视情况 |

**逐文件改造清单**：

| 文件 | 组件 | 改动说明 |
|---|---|---|
| `project_list_pane.dart:576` | `TextButton.icon`（加载更多） | → `ShadButton.ghost(icon: ..., child: ...)` |
| `agent_pane_sections.dart:241` | `TextButton.icon`（重试按钮） | → `ShadButton.ghost(icon: ..., child: ...)` |
| `agent_pane_cards.dart:380` | `TextButton`（批准按钮） | → `ShadButton.outline(child: ...)` |
| `agent_pane_cards.dart:600` | `TextButton.icon` | → `ShadButton.ghost(...)` |
| `agent_pane_cards.dart:606` | `FilledButton.icon`（执行按钮） | → `ShadButton(icon: ..., child: ...)` |
| `agent_pane_messages.dart:311` | `TextButton.icon`（收起/展开） | → `ShadButton.ghost(...)` |
| `settings_page.dart:100` | `IconButton`（返回） | → `ShadIconButton(icon: ...)` |
| `settings_page.dart:658` | `IconButton`（关闭对话框） | → `ShadIconButton(icon: ...)` |
| `agent_pane_composer.dart:141,158` | `IconButton`（取消/发送） | → `ShadIconButton` |
| `project_list_pane.dart:48,550` | `IconButton`（打开文件夹等） | → `ShadIconButton` |
| `agent_pane_messages.dart:410` | `IconButton`（复制） | → `ShadIconButton` |

**注意事项**：

- `ShadButton` 的 `size` 参数控制紧凑度，桌面端应使用 `ShadButtonSize.sm` 保持紧凑。
- 部分按钮当前通过 `TextButton.styleFrom(padding: ..., minimumSize: ...)` 自定义尺寸，迁移后通过 `ShadButtonTheme` 统一管理。
- shadcn 按钮默认使用 Lucide 图标。在本阶段中，可以先用 `Icon(Icons.xxx)` 传入 Material Icons，阶段五统一替换为 Lucide Icons。

#### 3.1.2 文本输入框替换

| 文件 | 场景 | 改动说明 |
|---|---|---|
| `settings_page.dart:667` | 字体搜索框（单行） | `TextField` → `ShadInput(placeholder: Text('搜索字体'))` |
| `agent_pane_composer.dart:86` | Agent 消息输入（多行 3~10 行） | `TextField(minLines:3, maxLines:10)` → 方案见下 |

**Agent 消息输入特殊处理**：

shadcn 的 `ShadInput` 是单行输入框；多行输入需使用 `ShadTextArea`（如果可用）或包装原生 `EditableText`。当前 Composer 的多行输入在 IDE 中非常核心，需要保留：
- 方案 A：使用 `ShadInput` 的 `minLines` / `maxLines` 参数（如果支持）
- 方案 B：保留底层 `TextField` 但去除 Material `InputDecoration`，外层用 shadcn 风格的 `DecoratedBox` 包裹，视觉上统一
- 方案 C：等 shadcn 的 `ShadTextArea` 组件

**推荐方案 B**：Composer 输入框的交互逻辑（`onSubmitted`、`textInputAction: TextInputAction.send`、焦点管理）高度定制化，硬换 `ShadInput` 可能引入行为回归。保留 `TextField` 核心，仅替换外观装饰为 shadcn 风格。

#### 3.1.3 分隔线替换

| 文件 | 改动 |
|---|---|
| `agent_pane_messages.dart:54,111` | `Divider(height:1, thickness:1, color: colors.border)` → `ShadSeparator()` |

#### 3.1.4 CircularProgressIndicator 处理

shadcn_ui 提供 `ShadProgress`（线性进度条），但不提供 spinner。处置策略：

- **保留** `CircularProgressIndicator` 但调整颜色使其与 shadcn 主题一致（通过 `valueColor` 设为 `ShadTheme.of(context).colorScheme.primary`）
- 或：自绘一个简洁的 shimmer / pulse 动画替代

推荐保留 `CircularProgressIndicator` 并通过主题色适配，因为它是低风险、低可见度组件。

### 3.2 验证标准

| 检查项 | 通过标准 |
|---|---|
| 全文搜索 `TextButton` / `FilledButton` | 零残留（`lib/` 范围） |
| 全文搜索 `IconButton`（Material 版） | 零残留（`lib/` 范围），全部替换为 `ShadIconButton` |
| 全文搜索 `TextField`（字体搜索处） | 已替换为 `ShadInput` |
| `flutter analyze` | 零 error |
| 三平台编译运行 | 成功 |
| 功能验证：点击所有按钮 | 回调正常触发，无 crash |
| 功能验证：Agent 输入框 | 多行输入、回车发送、取消按钮均正常 |
| 功能验证：字体搜索框 | 输入过滤正常 |
| 视觉验证 | 按钮风格统一为 shadcn ghost/outline/primary 风，无 Material ripple 残留 |

### 3.3 涉及文件

| 文件 | 改动类型 |
|---|---|
| `lib/src/features/agent/presentation/widgets/agent_pane_cards.dart` | 按钮替换 |
| `lib/src/features/agent/presentation/widgets/agent_pane_sections.dart` | 按钮替换 |
| `lib/src/features/agent/presentation/widgets/agent_pane_messages.dart` | 按钮 + 分隔线替换 |
| `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart` | 输入框 + 按钮替换 |
| `lib/src/features/settings/presentation/settings_page.dart` | 输入框 + 按钮替换 |
| `lib/src/ui/features/ide/views/project_list_pane.dart` | 按钮替换 |

### 3.4 回滚方案

按文件 `git checkout` 回退对应的 presentation 文件。

---

## 四、阶段四：复杂交互与弹出层组件重构

### 4.1 核心改造任务

#### 4.1.1 PopupMenuButton → ShadSelect / ShadPopover

**Composer 区域（3 处 PopupMenuButton）**：

| 组件 | 现状 | 目标 |
|---|---|---|
| `_ModelSelectorButton` | `PopupMenuButton<String>` 弹出模型列表 | `ShadSelect<String>` 带 check 标记 |
| `_ReasoningEffortButton` | `PopupMenuButton<String?>` 弹出推理深度列表 | `ShadSelect<String?>` |
| `_ServiceTierButton` | `PopupMenuButton<String?>` 弹出速率档位列表 | `ShadSelect<String?>` |

`ShadSelect` 的使用方式：

```dart
ShadSelect<String>(
  selectedOptionBuilder: (context, value) => Text(value),
  options: [
    for (final model in models)
      ShadOption(value: model.id, child: Text(model.displayName)),
  ],
  onChanged: onSelect,
)
```

外观需包裹为当前的 `_SelectorChip` 胶囊样式。`ShadSelect` 支持 `selectedOptionBuilder` 自定义触发器外观，可完美适配。

**窗口菜单栏（1 处 PopupMenuButton）**：

`_WindowMenuButton` 中的 `PopupMenuButton<WindowMenuItem>` 负责 Windows/Linux 下的顶部菜单栏。这是一个"菜单"语义而非"选择"语义，更适合迁移为 `ShadPopover` + 自定义菜单列表：

```dart
ShadPopover(
  controller: popoverController,
  popover: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final item in menu.items)
        ShadButton.ghost(
          onPressed: () { item.onPressed?.call(); popoverController.hide(); },
          child: Text(item.label),
        ),
    ],
  ),
  child: _MenuTrigger(label: menu.label),
)
```

**项目列表右键菜单**：

`project_list_pane.dart` 中通过 `showMenu` 手动弹出的右键上下文菜单也需迁移为 `ShadPopover` 或 `ShadContextMenu`（如果 shadcn 提供该组件）。

#### 4.1.2 showDialog / Dialog → showShadDialog / ShadDialog

当前仅有一处 `showDialog`：`settings_page.dart` 中的字体选择器弹窗。

改造要点：

```dart
// 旧：
showDialog<AppearanceFontChoice>(
  context: context,
  builder: (context) => _FontChoiceDialog(...),
);

// 新：
showShadDialog<AppearanceFontChoice>(
  context: context,
  builder: (context) => ShadDialog(
    title: Text(title),
    child: _FontChoiceDialogContent(...),
  ),
);
```

内部的 `_FontChoiceDialog` 需要拆解：
- 标题行 → `ShadDialog.title`
- 搜索框 → `ShadInput`（已在阶段三替换）
- 字体列表 `ListView.builder` + `ListTile` → `ListView.builder` + `ShadButton.ghost` 行
- 关闭按钮 → `ShadDialog` 自带关闭（或 `ShadIconButton`）

#### 4.1.3 SnackBar / ScaffoldMessenger → ShadSonner (Toast)

当前 3 处使用 `ScaffoldMessenger.of(context).showSnackBar()`：

| 文件 | 场景 | 改造方式 |
|---|---|---|
| `ide_home.dart:573` | 状态提示（如"项目已打开"） | `ShadSonner.of(context).show(...)` |
| `settings_page.dart:778` | 字体选择错误提示 | `ShadSonner.of(context).show(...)` |

需要在 `ShadApp` 层级注入 `ShadSonner` 提供者。`ShadApp` v0.55 内置了 Sonner 支持，只需要在 widget tree 中放置 `ShadSonner`。

#### 4.1.4 macOS 毛玻璃下的弹出层适配

在 macOS 毛玻璃模式下，`ShadSelect` / `ShadDialog` / `ShadPopover` 的弹出浮层也需要考虑透明度问题：

- 弹出层应使用**不透明**或**高 opacity**背景，避免毛玻璃穿透导致文字不可读
- 通过 `ShadThemeData` 的 `popoverDecoration` / `selectDecoration` 设置弹出层背景色为不透明的 `popover` 色

### 4.2 验证标准

| 检查项 | 通过标准 |
|---|---|
| 全文搜索 `PopupMenuButton` | 零残留 |
| 全文搜索 `showDialog` / `AlertDialog` | 零残留 |
| 全文搜索 `ScaffoldMessenger` / `SnackBar` | 零残留 |
| Composer 模型选择 | 弹出列表展示正确，选中态有 check，选择后回调正常 |
| Composer 推理深度选择 | 同上 |
| Composer 速率档位选择 | 同上 |
| 窗口菜单栏 | Windows/Linux 下菜单弹出、选中、关闭均正常 |
| 字体选择对话框 | 打开、搜索、选择、关闭均正常 |
| Toast 提示 | 状态消息和错误消息正常弹出并自动消失 |
| macOS 弹出层 | 弹出层文字清晰可读，不被毛玻璃干扰 |

### 4.3 涉及文件

| 文件 | 改动类型 |
|---|---|
| `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart` | PopupMenuButton → ShadSelect |
| `lib/src/ui/core/window_frame.dart` | PopupMenuButton → ShadPopover |
| `lib/src/features/settings/presentation/settings_page.dart` | Dialog → ShadDialog；ListTile → ShadButton.ghost |
| `lib/src/ui/features/ide/views/ide_home.dart` | SnackBar → ShadSonner |
| `lib/src/ui/features/ide/views/project_list_pane.dart` | 右键菜单迁移 |

### 4.4 回滚方案

逐文件回退 presentation 文件；如 ShadSonner 引入了 widget tree 层级变动，回退 `app.dart` 和 `ide_home.dart`。

---

## 五、阶段五：页面级大布局调优与细节走查

### 5.1 核心改造任务

#### 5.1.1 文件树组件重写

移除 `third_party/flutter_treeview` 依赖，用 shadcn 组件 + Flutter 内置的递归 `ListView` 重写文件树：

- 使用 `ShadAccordion` 或纯 `ExpansionTile` 风格的自绘折叠节点
- 图标使用 Lucide Icons（`LucideIcons.folder`、`LucideIcons.file` 等）
- 选中态使用 `ShadTheme.of(context).colorScheme.accent` + 低 opacity 背景
- 保持稳定 `ValueKey` 用于性能优化

**涉及文件**：
- `lib/src/features/workspace/presentation/file_tree_pane.dart`
- `lib/src/features/workspace/presentation/tree_view_file_node_mapper.dart`
- `lib/src/features/workspace/presentation/file_node_data.dart`
- `pubspec.yaml`（移除 `flutter_treeview` 依赖）

#### 5.1.2 Material Icons → Lucide Icons 全量替换

全项目中约 50+ 处使用 `Icons.*`（Material Icons）。逐一替换为 Lucide Icons 等价物：

| Material Icon | Lucide Icon |
|---|---|
| `Icons.account_tree_rounded` | `LucideIcons.gitBranch` |
| `Icons.folder_rounded` | `LucideIcons.folder` |
| `Icons.create_new_folder_outlined` | `LucideIcons.folderPlus` |
| `Icons.settings_rounded` | `LucideIcons.settings` |
| `Icons.arrow_back_rounded` | `LucideIcons.arrowLeft` |
| `Icons.close_rounded` | `LucideIcons.x` |
| `Icons.search_rounded` | `LucideIcons.search` |
| `Icons.check_rounded` | `LucideIcons.check` |
| `Icons.auto_awesome_outlined` | `LucideIcons.sparkles` |
| `Icons.psychology_alt_outlined` | `LucideIcons.brain` |
| `Icons.speed_rounded` | `LucideIcons.gauge` |
| `Icons.arrow_upward_rounded` | `LucideIcons.arrowUp` |
| `Icons.stop_rounded` | `LucideIcons.square` |
| `Icons.minimize_rounded` | `LucideIcons.minus` |
| `Icons.crop_square_rounded` | `LucideIcons.maximize2` |
| `Icons.restore_rounded` | `LucideIcons.minimize2` |
| `Icons.palette_outlined` | `LucideIcons.palette` |
| `Icons.data_object_rounded` | `LucideIcons.braces` |
| `Icons.build_circle_rounded` | `LucideIcons.wrench` |
| `Icons.hub_rounded` | `LucideIcons.network` |
| `Icons.terminal_rounded` | `LucideIcons.terminal` |
| `Icons.expand_more_rounded` | `LucideIcons.chevronDown` |
| `Icons.segment_rounded` | `LucideIcons.list` |
| `Icons.copy_rounded` | `LucideIcons.copy` |

#### 5.1.3 自绘交互组件的 shadcn 风格统一

以下使用 `InkWell` + `Material(color: transparent)` 手工构建的交互组件需要统一风格：

| 组件 | 文件 | 处置 |
|---|---|---|
| `_ActionIcon` | `ide_home.dart` | 换色为 shadcn palette，改用 `ShadIconButton` 或保留自绘 + 替换 hover/active 色值 |
| `_TitleBarActionButton` | `window_frame.dart` | 同上 |
| `_WindowButton` | `window_frame.dart` | 保留自绘（Windows 标准窗口按钮有特殊尺寸约束），仅换色 |
| `_SettingsNavItem` | `settings_page.dart` | → `ShadButton.ghost` 带左侧图标 |
| `_ThemeModeTabButton` | `settings_page.dart` | → `ShadTabs` 组件 |
| `_AppearanceSettingRow` | `settings_page.dart` | 保留自绘布局，换色至 shadcn |

#### 5.1.4 分割线统一

将所有硬编码的 `Container(width:1, color: colors.border)` 和 `Border(bottom: BorderSide(color: colors.border))` 统一使用 `ShadTheme.of(context).colorScheme.border`：

```dart
// 旧
Border.all(color: colors.border)

// 新
Border.all(color: ShadTheme.of(context).colorScheme.border)
```

#### 5.1.5 删除 IdeColors 遗留

全量迁移完成后：

1. 删除 `lib/src/ui/core/ide_colors.dart`
2. 删除 `lib/src/ui/core/shad_theme_bridge.dart`
3. 删除 `lib/src/ui/core/app_theme.dart` 中的 `buildIdeTheme()` 和 `buildCompactTheme()`
4. 将 `app_theme.dart` 仅保留 `IdeTypography`（代码字体信息）和 `buildShadTheme()`
5. 全文搜索 `IdeColors.of(context)` 确认零残留

#### 5.1.6 macOS 毛玻璃文字对比度微调

macOS 毛玻璃模式下，浅色壁纸 + 浅色主题可能导致文字发虚。处置：

- 在 macOS + 浅色主题时，为面板背景添加一层微弱白色遮罩（`Colors.white.withOpacity(0.5)`），提高文字底衬对比度
- 在 macOS + 深色主题时，面板背景添加深色遮罩（`Colors.black.withOpacity(0.3)`）
- 通过 `Platform.isMacOS` 条件判断，Windows/Linux 不施加遮罩

#### 5.1.7 PanelCard / Pane 组件适配

`lib/src/ui/core/pane_widgets.dart` 中的 `PanelCard`、`Pane`、`EmptyState`、`StateLabel` 是全局共享的 shell 组件，需要：

- `PanelCard.color` → 从 `IdeColors.of(context).panel` 改为 `ShadTheme.of(context).colorScheme.card`
- `Pane` 标题区 → 字体从 `Theme.of(context).textTheme` 改为 `ShadTheme.of(context).textTheme`
- `EmptyState` → 文字颜色从 `colors.mutedText` 改为 `ShadTheme.of(context).colorScheme.mutedForeground`
- `StateLabel` → 保留自绘，颜色参数化

#### 5.1.8 测试修复

现有 widget test 可能依赖 `MaterialApp` 或 `IdeColors.dark` 常量。需要：

- 将测试中的 `MaterialApp` 替换为 `ShadApp` 或用 `ShadApp.custom` 包装
- 确认 `buildCompactTheme()` 的测试调用点迁移到 `buildShadTheme()`
- 保留 `IdeColors.dark` 常量值在测试辅助文件中（避免大量断言修改），但标记为测试专用

### 5.2 验证标准

| 检查项 | 通过标准 |
|---|---|
| 全文搜索 `IdeColors` | 零残留（`lib/` 范围，测试辅助除外） |
| 全文搜索 `Icons.` (Material Icons) | 零残留 |
| 全文搜索 `flutter_treeview` | 零残留（`pubspec.yaml` + 代码） |
| 全文搜索 `MaterialApp` | 零残留 |
| 全文搜索 `Scaffold` | 零残留 |
| `flutter analyze` | 零 error，零 warning（新增） |
| `flutter test` | 全部通过 |
| **三平台视觉走查** | 见下方细则 |

**视觉走查细则**：

| 区域 | macOS | Windows / Linux |
|---|---|---|
| 窗口背景 | 毛玻璃透出桌面壁纸 | shadcn slate 纯色 |
| 标题栏 | 交通灯按钮正常，标题文字清晰 | 自绘三按钮正常，菜单栏弹出正常 |
| 左侧 ActivityRail | 半透明面板浮于毛玻璃之上 | 不透明 panel 色 |
| 项目列表 | 选中态 + 线程列表正常 | 同左 |
| Agent 主编辑区 | 对话渲染正常（markdown 未迁移但不崩溃） | 同左 |
| Composer 输入框 | 多行输入、发送、取消正常 | 同左 |
| 模型/思考/速率选择器 | ShadSelect 弹出列表正常 | 同左 |
| 右侧文件树 | 重写后的树形控件正常 | 同左 |
| 设置页 | 主题切换、字体选择弹窗正常 | 同左 |
| Toast 提示 | ShadSonner 弹出正常 | 同左 |
| 浅色主题 | 毛玻璃 + 白色遮罩，文字清晰 | 浅色纯底 |
| 深色主题 | 毛玻璃 + 深色遮罩，面板层次分明 | 深色纯底 |
| 分隔线 | 全局统一 border 色 | 同左 |
| 圆角 | 面板圆角统一 6px，按钮圆角统一 `ShadTheme.radius` | 同左 |
| 无移动端大尺寸残留 | 所有 touch target ≤ 36px，按钮高度 ≤ 32px | 同左 |

### 5.3 涉及文件

| 文件 | 改动类型 |
|---|---|
| `lib/src/features/workspace/presentation/file_tree_pane.dart` | 重写文件树 |
| `lib/src/features/workspace/presentation/tree_view_file_node_mapper.dart` | 适配新树组件 |
| `lib/src/features/workspace/presentation/file_node_data.dart` | 可能调整 |
| `lib/src/ui/core/pane_widgets.dart` | 换色至 shadcn |
| `lib/src/ui/core/ide_colors.dart` | 删除 |
| `lib/src/ui/core/shad_theme_bridge.dart` | 删除 |
| `lib/src/ui/core/app_theme.dart` | 精简 |
| `lib/src/ui/features/ide/views/ide_home.dart` | 自绘组件换色 + 图标替换 |
| `lib/src/ui/core/window_frame.dart` | 图标替换 + 换色 |
| `lib/src/features/settings/presentation/settings_page.dart` | 全面 shadcn 化 |
| `lib/src/features/agent/presentation/widgets/*.dart` | 图标替换 |
| `lib/src/ui/features/ide/views/project_list_pane.dart` | 图标替换 + 换色 |
| `pubspec.yaml` | 移除 `flutter_treeview` |
| `test/**/*.dart` | 适配新主题 |

### 5.4 回滚方案

阶段五改动面广，建议在阶段四完成后打 Git tag `pre-phase5`。如需回滚，`git reset --hard pre-phase5`。

---

## 六、风险矩阵与缓解措施

| 风险 | 影响级别 | 缓解措施 |
|---|---|---|
| `ShadApp` 缺少 `Scaffold` 导致部分 Material widget 找不到祖先 | **高** | 阶段二先用 `Material` widget 包裹 home 作为临时过渡；阶段四彻底移除 |
| `macos_window_utils` 与 `window_manager` 初始化冲突 | **中** | 严格控制初始化顺序：`window_manager` → `WindowManipulator`；分别管理不同职责 |
| `mixin_markdown_widget` / `flutter_highlight` 在纯 `ShadApp` 下报错 | **中** | 在 Agent 对话区域保留一层 `Material` 包装作为兼容壳 |
| shadcn 组件不支持某些 Material 特性（如 `TextInputAction.send`） | **中** | 对核心输入框保留 `TextField` 底层，仅替换装饰层 |
| macOS 毛玻璃下弹出层文字不可读 | **低** | 弹出层强制不透明背景 |
| 测试大面积失败 | **中** | 每阶段完成后立即运行测试并修复；测试辅助中保留旧常量 |
| Lucide Icons 缺少某些 Material Icons 的等价物 | **低** | 查阅 lucide.dev 图标库，必要时保留个别 Material Icons |

---

## 七、里程碑时间线建议

| 阶段 | 预计工作量 | 关键交付物 |
|---|---|---|
| 阶段一：依赖与环境准备 | 0.5 天 | `pubspec.yaml` 更新 + 桥接文件 + 三平台编译通过 |
| 阶段二：全局入口与主题适配 | 1.5 天 | `ShadApp` 启动 + macOS 毛玻璃 + 双主题切换 |
| 阶段三：原子组件批量替换 | 2 天 | 所有按钮 / 输入框 / 分隔线迁移完成 |
| 阶段四：复杂交互与弹出层 | 2 天 | Select / Dialog / Toast 全部迁移 |
| 阶段五：布局调优与走查 | 3 天 | 文件树重写 + 图标全量替换 + IdeColors 清除 + 三端视觉走查 |
| **合计** | **~9 天** | |

---

## 八、附录

### 附录 A：迁移后的导入变化

```dart
// 旧
import 'package:flutter/material.dart';

// 新（逐步过渡）
import 'package:shadcn_ui/shadcn_ui.dart';
// 仅在需要 Material 底层能力时保留：
import 'package:flutter/widgets.dart';
```

### 附录 B：ShadApp vs MaterialApp 关键差异

| 能力 | MaterialApp | ShadApp |
|---|---|---|
| 内置 Scaffold | 是 | 否 |
| 内置 Navigator | 是 | 是 |
| ScaffoldMessenger | 是 | 否（用 ShadSonner） |
| ThemeData | Material ThemeData | ShadThemeData |
| 默认滚动行为 | Material | 平台自适应 |
| i18n | MaterialLocalizations | GlobalShadLocalizations |

### 附录 C：需要保留 Material 依赖的场景

1. `mixin_markdown_widget` 内部依赖 Material Widgets → 在其宿主区域保留 `Material` 包装
2. `flutter_highlight` 可能依赖 `Theme.of(context)` → 同上
3. `CircularProgressIndicator` → 保留并通过 `valueColor` 适配

### 附录 D：Git 分支策略建议

```
main
  └── feat/shadcn-migration
        ├── phase-1/deps          (完成后 merge 回 feat/shadcn-migration)
        ├── phase-2/theme-entry   (同上)
        ├── phase-3/atomic-swap   (同上)
        ├── phase-4/complex-ui    (同上)
        └── phase-5/polish        (同上，最终 merge 回 main)
```

每阶段独立分支，通过编译验证后合入主迁移分支，确保任何阶段可独立回滚。
