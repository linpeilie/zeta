---
name: zeta-design-system
description: >-
  Zeta IDE 的「Graphite 石墨蓝」设计系统规范：颜色/间距/圆角/阴影/动效
  token 的取值与用法、ui/core 复用组件的选用规则、硬性编码约束与新增 UI
  的检查清单。在本仓库编写或修改任何 Flutter UI（widget、主题、颜色、
  面板、hover/selected 态、阴影、圆角、字体样式）之前必须先阅读并遵循
  本技能。
---

# Zeta 设计系统（Graphite）

Zeta 的 UI 基于 shadcn_ui + 自建 token 体系。所有视觉取值集中在
`lib/src/ui/core/` 下的 token 类；业务代码只允许消费 token,不允许出现
裸颜色、裸圆角、手写阴影。

## 视觉身份

「Graphite」：中性石墨灰底（无色相偏移）+ 蔚蓝强调（accent `#1B84FF`
深色 / `#0B76D8` 浅色），selected 行用 `primaryMuted`（accent 半透明）
铺底，success/error/warning/info 保留独立语义色。深浅两套调色板见
`IdeColors.dark` / `IdeColors.light`（`lib/src/ui/core/ide_colors.dart`），
改色只改那里，不要在组件里覆写。

## Token 类清单

| Token 类 | 文件 | 内容 |
|---|---|---|
| `IdeColors` | `ide_colors.dart` | 语义色：frame/surface/surfaceElevated/surfaceOverlay/panel/editor、border/borderSubtle、textPrimary/Secondary/Tertiary、accent/primaryMuted、error/warning/success/info、窗口按钮色 |
| `IdeRadius` | `ide_effects.dart` | 圆角四档：small 6（行/按钮/菜单项/代码块）、medium 8（面板卡片/输入框）、large 12（弹层/对话框）、composer 16（Composer/计划卡），另有 `pill` |
| `IdeEffects` | `ide_effects.dart` | 阴影预设 `panelShadow`/`overlayShadow`/`composerRestShadow`/`composerFocusShadow` 与 `scrim`，全部按 `Brightness` 取值 |
| `IdeSpacing` | `ide_spacing.dart` | 4px 基准间距 `space2..space32` 与常用 EdgeInsets 预设 |
| `IdeTextStyles` | `ide_text_styles.dart` | 语义字号 display/title/body/code/caption；UI 与代码字体族由 `IdeTypography` 提供 |
| `IdeMotion` | `ide_motion.dart` | 时长 fast 100 / normal 160 / slow 260,曲线 `curveDefault`/`curvePopup` |

获取方式一律为 `IdeColors.of(context)` / `IdeTextStyles.of(context)`；
`ShadTheme.of(context)` 只用于 brightness、radius 与 shadcn 组件主题。

## 常用取值约定

- 面板层级：窗口底 `frame` → 面板 `surface`/`panel` → 卡片/代码块
  `surfaceElevated` → 弹层 `surfaceOverlay`。
- hover 背景：`colors.border.withValues(alpha: 深色 0.18 / 浅色 0.3)`；
  `PaneInteractiveSurface` 与全局 ghost 按钮主题已内置该默认值，能不传就不传。
- selected 背景：`colors.primaryMuted`；selected 前景/图标：`colors.accent`。
- 选项卡片（`IdeChoiceCard`）：未选中为 `surface` 底 + `border` 边框 +
  `textSecondary` 图标；选中为 `primaryMuted` 底 + `accent` 边框与前景；
  圆角 `IdeRadius.allMedium`，内边距 `IdeSpacing.all12`。
- diff 增删行：`+` 用 `success`、`-` 用 `error`（不要用 accent/warning）。
- 禁用态文字：`textTertiary`；次要说明：`textSecondary`。
- 焦点边框：`colors.accent`（可带 alpha），阴影用
  `IdeEffects.composerFocusShadow`。

## 组件选用规则（先复用 ui/core,再造新轮子）

| 场景 | 组件 |
|---|---|
| 面板容器（带边框/阴影/圆角） | `PanelCard` |
| 带标题栏的面板 | `Pane`（title/subtitle/trailing） |
| 可点击行（文件树行、线程行、菜单项） | `PaneInteractiveSurface`（内置 hover/pressed/selected/focus 态） |
| 折叠信息卡（工具调用、计划、diff 组） | `IdeCollapsibleCard` |
| 语义状态卡（info/warning/error/success） | `IdeStatusCard` |
| 胶囊选择器/标签 | `IdeChip` |
| 图标+标题的卡片式单选（2–4 个互斥选项，如设置项） | `IdeChoiceCardGroup` + `IdeChoiceCard` |
| 右键/更多菜单 | `IdeContextMenu` + `IdeContextMenuAction` |
| 左右活动栏 | `IdeActivityRail` + `IdeRailAction` |
| 分栏拖拽条 | `IdeResizeHandle` |
| 提示气泡 | `IdeTooltip` |
| 加载指示 | `IdeLoadingIndicator` |
| 通用按钮 | shadcn `ShadButton`/`ShadIconButton`（ghost 主题已全局统一 hover） |
| 弹层/对话框/Toast | shadcn `ShadPopover`/`ShadDialog`/`ShadToast`（主题已统一 surfaceOverlay + overlayShadow + large 圆角） |

## 硬性规则

1. 业务/feature 代码禁止出现裸 `Color(0x...)`、`Colors.black`、
   `Colors.grey` 等常量色。唯一例外：token 定义文件本身,以及实心
   accent/closeHover 上的 `Colors.white` 前景。
2. 圆角只允许 `IdeRadius` 四档 + `pill`；禁止手写
   `BorderRadius.circular(<数字>)`（动态尺寸如进度条胶囊除外）。
3. 阴影只允许 `IdeEffects` 预设；禁止手写 `BoxShadow` 列表。
4. 间距/内边距必须使用 `IdeSpacing`；不要出现魔法数字 padding。
5. 亮度判断只用 `ShadTheme.of(context).brightness`；禁止
   `Theme.of(context).brightness` 与 `computeLuminance` 探测。
6. 文字样式从 `IdeTextStyles` 取,禁止 `TextStyle(fontSize: ...)` 起新样式；
   代码/等宽文本用 `codeSmall` + `IdeTypography.of(context).codeFontFamily`。
7. 重复的交互列表行必须携带稳定 `ValueKey`；流式/高频重绘区域
   （streaming markdown、高亮代码、diff 详情）外层包 `RepaintBoundary`。
8. 长文本（路径、标题、摘要）必须 `maxLines` + `TextOverflow.ellipsis`。
9. 主题相关改动完成后运行 `dart format .` 与 `flutter analyze`,
   涉及行为改动补跑 `flutter test`。

## 新增 UI 工作流 checklist

```
- [ ] 先在 ui/core 找可复用组件,确认无法复用再新建
- [ ] 颜色全部来自 IdeColors.of(context)（或其 alpha 派生）
- [ ] 圆角/阴影/间距/动效全部来自 IdeRadius/IdeEffects/IdeSpacing/IdeMotion
- [ ] 深浅两套主题下均检查过（外观设置可即时切换）
- [ ] hover/selected/focus/disabled 四态与现有面板一致
- [ ] 列表行带 ValueKey,重区域带 RepaintBoundary,长文本带省略
- [ ] dart format + flutter analyze 通过
```

## 修改 token 时

- 新增颜色语义：在 `IdeColors` 加字段,同步 dark/light 两套、
  `copyWith`/`lerp`/`==`/`hashCode` 与 `shadColorSchemeFromIdeColors` 映射。
- 新增圆角/阴影档位：加到 `IdeRadius`/`IdeEffects`,不要在业务层内联。
- 旧常量 `ideAccentColor` 等仅为兼容保留在 `app_theme.dart`,新代码一律
  使用 `IdeColors`；`idePanelGap`/`idePanelRadius` 已废弃。
