import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'app_theme.dart';

/// IDE 主题专用调色板。
///
/// 色值来自 `shadcn_flutter` 的 Zinc [sf.ColorSchemes] 与 [sf.Colors] 色板
/// （blue / red / amber / green / sky 等），再映射为 IDE 语义字段。运行时通过
/// [IdeThemeScope] 解析；`app_theme.dart` 还会将它们投影到 Material 和
/// `shadcn_flutter` 主题，因此第三方组件也会间接生效。
///
/// 每个字段都是跨功能的语义颜色，而不是某个组件的专用色。下方字段
/// 注释中的“生效位置”列出当前主要消费者。
@immutable
class IdeColors {
  const IdeColors({
    required this.frame,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceOverlay,
    required this.panel,
    required this.editor,
    required this.border,
    required this.borderSubtle,
    required this.mutedText,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.primaryMuted,
    required this.warning,
    required this.error,
    required this.success,
    required this.info,
    required this.accentForeground,
    required this.onAccent,
    required this.windowHover,
    required this.windowIcon,
    required this.closeHover,
    required this.hoverSurface,
    required this.pressedSurface,
    required this.selectedSurface,
    required this.selectedHoverSurface,
    required this.userMessageSurface,
    required this.focusRing,
  });

  /// 从官方 Zinc 方案 + blue 品牌主色构建 IDE 语义调色板。
  ///
  /// 表面层级在 [sf.ColorScheme] 扁平字段之上用 [sf.Colors.zinc] 阶梯补全，
  /// 以保持 IDE 的 frame / canvas / pane / control 明度顺序。
  factory IdeColors.fromShadcnColorScheme(sf.ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final zinc = sf.Colors.zinc;
    final neutral = sf.Colors.neutral;
    final blue = sf.Colors.blue;
    final red = sf.Colors.red;
    final amber = sf.Colors.amber;
    final green = sf.Colors.green;
    final sky = sf.Colors.sky;
    final gray = sf.Colors.gray;
    // shadcn `.blue` recolor 在深浅下都指向 Colors.blue（500）；
    // IDE 按亮度拆阶梯，避免深浅主题 brand / ring 完全相同。
    final brand = isDark ? blue[500] : blue[600];

    if (isDark) {
      return IdeColors(
        frame: neutral[700],
        // 画布略深于面板：background 与 zinc.900 拉开层级。
        editor: neutral[800],
        surface: neutral[700],
        surfaceElevated: neutral[800],
        surfaceOverlay: zinc[800],
        panel: zinc[900],
        border: neutral[600],
        borderSubtle: zinc[900],
        mutedText: scheme.mutedForeground,
        textPrimary: scheme.foreground,
        textSecondary: scheme.mutedForeground,
        textTertiary: zinc[500],
        accent: brand,
        primaryMuted: brand.withValues(alpha: 0.32),
        warning: amber[400],
        // 深色下 destructive 方案色偏暗，状态文本改用更亮的 red 阶梯。
        error: red[400],
        success: green[400],
        info: sky[400],
        accentForeground: sf.Colors.white,
        onAccent: sf.Colors.white,
        windowHover: zinc[800],
        windowIcon: zinc[400],
        closeHover: red[500],
        hoverSurface: zinc[800],
        pressedSurface: zinc[700],
        selectedSurface: scheme.accent,
        selectedHoverSurface: zinc[700],
        userMessageSurface: zinc[800],
        focusRing: brand,
      );
    }

    return IdeColors(
      frame: neutral[50],
      // 浅色：canvas 最亮，pane / control 依次略灰。
      editor: sf.Colors.white,
      surface: neutral[50],
      surfaceElevated: zinc[100],
      surfaceOverlay: scheme.popover,
      panel: scheme.card,
      border: scheme.border,
      borderSubtle: zinc[100],
      mutedText: scheme.mutedForeground,
      textPrimary: scheme.foreground,
      textSecondary: scheme.mutedForeground,
      textTertiary: zinc[400],
      accent: brand,
      primaryMuted: brand.withValues(alpha: 0.24),
      warning: amber[700],
      error: red[500],
      success: green[600],
      info: sky[600],
      // 浅色选中态落在浅灰底上，强调图标用品牌蓝而非白色。
      accentForeground: brand,
      onAccent: sf.Colors.white,
      windowHover: zinc[200],
      windowIcon: zinc[500],
      closeHover: red[500],
      hoverSurface: zinc[100],
      pressedSurface: zinc[200],
      selectedSurface: scheme.accent,
      selectedHoverSurface: zinc[200],
      userMessageSurface: zinc[100],
      focusRing: brand,
    );
  }

  /// 应用最底层的框架背景，用于承托各个内容表面。
  ///
  /// 生效位置：`WindowFrame` 外框与标题栏、Material `Scaffold` 和
  /// shadcn 根背景、面板拖拽分隔区，以及 `IdeTab`/Composer 选择器的
  /// 展开态背景。
  final Color frame;

  /// 默认内容表面，层级高于 [frame]、低于抬升和覆盖层。
  ///
  /// 生效位置：Material canvas/card、shadcn card、Agent 上下文侧栏，
  /// 以及模型配置中的分段控件容器。
  final Color surface;

  /// 在 [surface] 上抬升一层的中性表面，用于嵌套内容分组。
  ///
  /// 生效位置：设置页导航面板、`IdeTab` 背景、Agent 回答/文件编辑卡、
  /// 消息气泡、Markdown 代码块/引用/表头、附件缩略图和配置编辑器行号栏。
  final Color surfaceElevated;

  /// 最上层覆盖表面，与页面内容分离且必须保持不透明。
  ///
  /// 生效位置：`IdeContextMenu`、Provider 选择 Popover、`IdeTooltip`、
  /// 用量统计筛选层和模型配置内部的次级选择层；同时投影为 shadcn popover。
  final Color surfaceOverlay;

  /// Composer 专用的连续面板背景。
  ///
  /// 生效位置：Agent Composer 外卡、输入区及其拖拽角遮罩，
  /// 以及模型/工作目录权限的共享选择弹层。该字段保留独立语义，
  /// 便于 Composer 未来与通用 [surface] 分色。
  final Color panel;

  /// IDE 中央主工作区背景。
  ///
  /// 生效位置：`IdeHome` 中承载 `AgentPane` 的中央编辑器容器。
  /// 不用于 Composer 或侧栏，这些区域分别使用 [panel]/[surface]。
  final Color editor;

  /// 可清晰识别的常规边界色，也是交互态中性底色的基准。
  ///
  /// 生效位置：窗口外边框、卡片/消息/设置控件边框、Material 分隔线、
  /// shadcn border，以及文件树、项目列表、选择器的 hover/pressed/focus 派生色。
  final Color border;

  /// 低对比度边界色，用于同一表面内的轻量分组。
  ///
  /// 生效位置：上下文菜单分隔线、页头/侧栏内分隔线、Markdown 表格和
  /// 代码块边界、模型/权限选择弹层、图片草稿边框，并投影为 shadcn input。
  final Color borderSubtle;

  /// 旧版的弱化前景别名，语义与 [textSecondary] 保持同步。
  ///
  /// 生效位置：Agent 头部的 provider/token/时间元数据、项目 Thread 辅助文字、
  /// 空面板 trailing 图标。新代码应优先使用 [textSecondary]；[copyWith] 会保证
  /// 两个字段的兼容同步行为。
  final Color mutedText;

  /// 最高对比度的内容前景色。
  ///
  /// 生效位置：页面/面板标题、正文、代码、可用菜单项、消息内容，
  /// `IdeTextStyles` 默认正文，以及 Material/shadcn 的核心 foreground。
  final Color textPrimary;

  /// 中等对比度的辅助前景色。
  ///
  /// 生效位置：副标题、元数据、标签、未激活导航/按钮图标、折叠卡摘要、
  /// `IdeTextStyles.bodySmall/caption`，以及 Material icon 和 shadcn muted foreground。
  final Color textSecondary;

  /// 最低对比度但仍需可读的辅助前景色。
  ///
  /// 生效位置：输入占位符、禁用/不可用控件、隐藏模型、调试日志与时间戳、
  /// 选择弹层轻量标题，以及 `IdeTextStyles.placeholder`。
  final Color textTertiary;

  /// 主题的强交互与品牌强调色。
  ///
  /// 生效位置：选中的文件/Thread/导航图标、进行中状态、Composer 发送按钮、
  /// Markdown 链接、选择器勾选/底部指示线，并投影为 shadcn primary 和
  /// 图表 `chart1`。焦点描边统一使用 [focusRing]。
  final Color accent;

  /// [accent] 的半透明弱化背景，用于蓝色弱强调。
  ///
  /// 生效位置：可操作提示、少量活动状态和 Markdown 文本选区。普通导航、
  /// 列表选中与用户消息分别使用 [selectedSurface] 和 [userMessageSurface]。
  final Color primaryMuted;

  /// 需要注意、等待或可恢复异常的状态色。
  ///
  /// 生效位置：待审批/等待中的 Agent 回合、压缩和更新提示、Fast 标识、
  /// Agent 安装/账号警告、warning 日志与状态卡，以及图表 `chart3`。
  final Color warning;

  /// 失败、不可恢复问题和破坏性操作的状态色。
  ///
  /// 生效位置：错误文本/日志/状态卡、配置校验失败、错误 Toast、
  /// `IdeContextMenu` destructive 菜单项、shadcn destructive 和图表 `chart5`。
  final Color error;

  /// 成功、已完成和健康可用状态的语义色。
  ///
  /// 生效位置：Agent 回合完成标记、已安装/已登录/配置有效状态、
  /// 成功 Toast/状态卡、Diff 新增行，以及图表 `chart4`。
  final Color success;

  /// 中性说明、正常运行和搜索/系统事件的状态色。
  ///
  /// 生效位置：info 日志/状态卡、Agent 搜索与系统事件、模型下回合生效提示、
  /// 用户问题图标和 Markdown 引用边线，以及图表 `chart2`。
  final Color info;

  /// 选中/激活态落在中性选中底色上的前景色（图标/标签）。
  ///
  /// 深色下为白；浅色下使用 [accent]，以便在浅底面板上保持可见。
  /// 不要用于实心 [accent] 填充上的文字——那种场景用 [onAccent]。
  ///
  /// 生效位置：`IdeActivityRail` 的激活图标和 `WindowFrame` 的激活
  /// 标题栏动作图标。
  final Color accentForeground;

  /// 落在实心 [accent] 填充上的前景色（Primary 按钮文字/图标等）。
  ///
  /// 深浅主题均为高对比白色，与 [accentForeground]（选中态强调色）语义分离。
  ///
  /// 生效位置：`app_theme.dart` 中 shadcn `primaryForeground`，最终影响所有
  /// 使用实心 primary/accent 背景的第三方主按钮和图标。
  final Color onAccent;

  /// Windows/Linux 自绘的普通窗口按钮悬停背景。
  ///
  /// 生效位置：`WindowFrame` 右上角最小化和最大化/还原按钮 hover；
  /// 关闭按钮改用 [closeHover]。
  final Color windowHover;

  /// Windows/Linux 自绘窗口控制图标的静止态前景色。
  ///
  /// 生效位置：`WindowFrame` 右上角最小化、最大化/还原和关闭图标；
  /// hover 时普通按钮切换到 [textPrimary]，关闭按钮切换到白色。
  final Color windowIcon;

  /// Windows/Linux 自绘关闭按钮的破坏性悬停背景。
  ///
  /// 生效位置：`WindowFrame` 右上角关闭按钮 hover。深浅主题均使用
  /// `sf.Colors.red[500]`，以保持平台操作语义一致。
  final Color closeHover;

  /// 普通可交互控件的悬停背景。
  ///
  /// 生效位置：`PaneInteractiveSurface` 默认 hover；设置页导航项 hover；
  /// Agent 消息区可点击块 hover；Material `hoverColor` 投影。
  final Color hoverSurface;

  /// 普通可交互控件的按下背景。
  ///
  /// 生效位置：`PaneInteractiveSurface` 默认 pressed 态。
  final Color pressedSurface;

  /// 普通导航、列表和 Tab 的中性选中背景。
  ///
  /// 生效位置：`IdeActivityRail` / `IdeChoiceCard` 选中底；设置页导航选中；
  /// `PaneInteractiveSurface` 默认 selected；shadcn `accent`（Zeta 中表示
  /// 中性选中，而非品牌蓝）投影。
  final Color selectedSurface;

  /// 已选中控件的悬停背景。
  ///
  /// 生效位置：`PaneInteractiveSurface` 选中+hover；设置页导航选中项 hover。
  final Color selectedHoverSurface;

  /// 用户消息专用表面，不表达品牌或主操作。
  ///
  /// 生效位置：Agent 会话中用户气泡背景（`agent_pane_messages`）。
  final Color userMessageSurface;

  /// 键盘焦点和输入焦点的统一描边色。
  ///
  /// 生效位置：Composer 外卡聚焦边与 [IdeEffects.focusRing]；模型配置/控件
  /// `focusBorderColor`；Material `focusColor` 与 shadcn `ring` 投影。
  final Color focusRing;

  /// 窗口框架、标题栏与面板间 gutter 表面。
  Color get frameSurface => frame;

  /// 中央编辑器与页面主画布表面。
  Color get canvasSurface => editor;

  /// 会话栏、文件栏与设置导航表面。
  Color get paneSurface => surface;

  /// 输入框、分段控件与紧凑选择器表面。
  Color get controlSurface => surfaceElevated;

  /// Popover、菜单、Tooltip 与 Drawer 表面。
  Color get popoverSurface => surfaceOverlay;

  /// 深色调色板：`ColorSchemes.darkZinc` + `Colors.blue` 品牌主色。
  ///
  /// 各参数的具体生效位置见上方同名字段注释。
  static final IdeColors dark = IdeColors.fromShadcnColorScheme(
    sf.ColorSchemes.darkZinc,
  );

  /// 浅色调色板：`ColorSchemes.lightZinc` + `Colors.blue` 品牌主色。
  ///
  /// 与深色主题共享同一套语义层级；各参数的具体生效位置见上方同名字段注释。
  static final IdeColors light = IdeColors.fromShadcnColorScheme(
    sf.ColorSchemes.lightZinc,
  );

  /// 从 [context] 取出当前主题下的 [IdeColors]。
  static IdeColors of(BuildContext context) {
    return IdeThemeScope.of(context).colors;
  }

  /// 复制当前调色板并替换指定语义颜色。
  ///
  /// [mutedText] 是 [textSecondary] 的历史兼容别名；仅覆盖其中任意一个时，
  /// 本方法会同步另一个，避免新旧调用点出现不一致的辅助前景色。
  IdeColors copyWith({
    Color? frame,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceOverlay,
    Color? panel,
    Color? editor,
    Color? border,
    Color? borderSubtle,
    Color? mutedText,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? primaryMuted,
    Color? warning,
    Color? error,
    Color? success,
    Color? info,
    Color? accentForeground,
    Color? onAccent,
    Color? windowHover,
    Color? windowIcon,
    Color? closeHover,
    Color? hoverSurface,
    Color? pressedSurface,
    Color? selectedSurface,
    Color? selectedHoverSurface,
    Color? userMessageSurface,
    Color? focusRing,
  }) {
    final resolvedTextSecondary =
        textSecondary ?? mutedText ?? this.textSecondary;
    final resolvedMutedText = mutedText ?? textSecondary ?? this.mutedText;
    return IdeColors(
      frame: frame ?? this.frame,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      panel: panel ?? this.panel,
      editor: editor ?? this.editor,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      mutedText: resolvedMutedText,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: resolvedTextSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      primaryMuted: primaryMuted ?? this.primaryMuted,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      success: success ?? this.success,
      info: info ?? this.info,
      accentForeground: accentForeground ?? this.accentForeground,
      onAccent: onAccent ?? this.onAccent,
      windowHover: windowHover ?? this.windowHover,
      windowIcon: windowIcon ?? this.windowIcon,
      closeHover: closeHover ?? this.closeHover,
      hoverSurface: hoverSurface ?? this.hoverSurface,
      pressedSurface: pressedSurface ?? this.pressedSurface,
      selectedSurface: selectedSurface ?? this.selectedSurface,
      selectedHoverSurface: selectedHoverSurface ?? this.selectedHoverSurface,
      userMessageSurface: userMessageSurface ?? this.userMessageSurface,
      focusRing: focusRing ?? this.focusRing,
    );
  }

  /// 在当前调色板与 [other] 之间逐项插值，用于主题过渡动画。
  IdeColors lerp(IdeColors other, double t) {
    return IdeColors(
      frame: Color.lerp(frame, other.frame, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      editor: Color.lerp(editor, other.editor, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      primaryMuted: Color.lerp(primaryMuted, other.primaryMuted, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
      accentForeground: Color.lerp(
        accentForeground,
        other.accentForeground,
        t,
      )!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      windowHover: Color.lerp(windowHover, other.windowHover, t)!,
      windowIcon: Color.lerp(windowIcon, other.windowIcon, t)!,
      closeHover: Color.lerp(closeHover, other.closeHover, t)!,
      hoverSurface: Color.lerp(hoverSurface, other.hoverSurface, t)!,
      pressedSurface: Color.lerp(pressedSurface, other.pressedSurface, t)!,
      selectedSurface: Color.lerp(selectedSurface, other.selectedSurface, t)!,
      selectedHoverSurface: Color.lerp(
        selectedHoverSurface,
        other.selectedHoverSurface,
        t,
      )!,
      userMessageSurface: Color.lerp(
        userMessageSurface,
        other.userMessageSurface,
        t,
      )!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
    );
  }
}
