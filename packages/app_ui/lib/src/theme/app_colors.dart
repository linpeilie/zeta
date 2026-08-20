import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// IDE 主题专用调色板。
///
/// 色值以 `shadcn_flutter` 的 Zinc color schemes 为语义基底，并组合
/// [sf.Colors.neutral] / [sf.Colors.zinc] 表面阶梯及 blue / red / amber /
/// green / sky 状态色板，再映射为 IDE 语义字段。运行时通过 Material theme
/// 解析；`app_theme.dart` 还会将它们投影到 Material 和 `shadcn_flutter`
/// 主题，因此第三方组件也会间接生效。
///
/// 每个字段都是跨功能的语义颜色，而不是某个组件的专用色。下方字段
/// 注释中的“生效位置”列出当前主要消费者。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Creates a complete semantic palette.
  const AppColors({
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
    required this.intelligenceAccent,
    required this.primaryMuted,
    required this.warning,
    required this.error,
    required this.success,
    required this.onSuccess,
    required this.info,
    required this.onWarning,
    required this.onInfo,
    required this.accentForeground,
    required this.onAccent,
    required this.windowHover,
    required this.windowIcon,
    required this.closeHover,
    required this.hoverSurface,
    required this.pressedSurface,
    required this.selectedSurface,
    required this.selectedHoverSurface,
    required this.focusRing,
  });

  /// 构建单色炭黑（深色）/ 单色浅灰（浅色）语义调色板。
  ///
  /// **表面阶梯是严格单调的**，两套主题遵循同一条规则：`frame` 永远是离内容
  /// 最远的一档（深色最黑、浅色最灰），往内依次是 canvas → pane → control →
  /// popover。层级只靠这条明度阶梯加 1px 极低透明度描边表达，不靠投影。
  ///
  /// ```text
  /// dark: frame < canvas < pane < control < popover
  /// light: frame → canvas > pane > control
  /// ```
  ///
  /// 底色一律取自 [sf.Colors.neutral] 单一色系，不再混用 zinc，避免同一屏里
  /// 出现两种灰的色温。状态色（warning / error / success / info）与
  /// [intelligenceAccent] 仍取各自色板，它们编码语义而非表面层级。
  ///
  /// 描边与交互态改用**半透明叠加**而非不透明色：`white @ 8%` 叠在炭黑上是
  /// 一条发丝线，换成不透明的 `#525252` 就会变成一条灰带。同理，hover 是
  /// 「把背景提亮 5%」，因此它必须是能叠在任意表面上的半透明色。
  factory AppColors.fromShadcnColorScheme(sf.ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    const zinc = sf.Colors.zinc;
    const neutral = sf.Colors.neutral;
    const blue = sf.Colors.blue;
    const red = sf.Colors.red;
    const amber = sf.Colors.amber;
    const green = sf.Colors.green;
    const sky = sf.Colors.sky;
    const violet = sf.Colors.violet;
    // 品牌蓝按亮度拆阶梯，再向中性灰回拉一档降饱和：全局只在发送按钮、
    // 选中指示线这类核心行动点出现，高饱和会破坏单色底的克制感。
    final brand = Color.lerp(
      isDark ? blue[500] : blue[600],
      isDark ? neutral[300] : neutral[600],
      0.30,
    )!;

    if (isDark) {
      // 半透明叠加的基准色：深色主题用白，叠上去即「提亮」。
      const overlayBase = sf.Colors.white;
      return AppColors(
        frame: neutral[950],
        // 中央画布比 frame 略亮一档，又比侧栏更深，保持 IDE 的视觉重心。
        editor: Color.lerp(neutral[950], neutral[900], 0.45)!,
        surface: neutral[900],
        surfaceElevated: Color.lerp(neutral[900], neutral[800], 0.5)!,
        surfaceOverlay: neutral[800],
        panel: neutral[900],
        border: overlayBase.withValues(alpha: 0.08),
        borderSubtle: overlayBase.withValues(alpha: 0.05),
        mutedText: neutral[400],
        textPrimary: neutral[50],
        textSecondary: neutral[400],
        // 三级前景不能再压暗：10px 的时间戳落在最亮的 popover 档（#262626）上时，
        // neutral.500 只有 3.3:1，达不到 WCAG AA。提到 ~#909090 才能在全部四档
        // 表面上都拿到 4.5:1 以上。层级弱化交给字号和字重，不靠牺牲对比度。
        textTertiary: Color.lerp(neutral[500], neutral[400], 0.6)!,
        accent: brand,
        intelligenceAccent: violet[400],
        primaryMuted: brand.withValues(alpha: 0.32),
        warning: amber[400],
        // 深色下 destructive 方案色偏暗，状态文本改用更亮的 red 阶梯。
        error: red[400],
        success: green[400],
        onSuccess: neutral[950],
        info: sky[400],
        onWarning: neutral[950],
        onInfo: neutral[950],
        accentForeground: sf.Colors.white,
        onAccent: sf.Colors.white,
        windowHover: overlayBase.withValues(alpha: 0.08),
        windowIcon: neutral[400],
        closeHover: red[500],
        hoverSurface: overlayBase.withValues(alpha: 0.05),
        pressedSurface: overlayBase.withValues(alpha: 0.08),
        selectedSurface: overlayBase.withValues(alpha: 0.08),
        selectedHoverSurface: overlayBase.withValues(alpha: 0.12),
        focusRing: brand,
      );
    }

    // 浅色主题镜像同一套规则，只是叠加基准换成近黑，方向相反。
    final overlayBase = zinc[950];
    return AppColors(
      frame: zinc[200],
      editor: sf.Colors.white,
      surface: neutral[50],
      surfaceElevated: zinc[100],
      surfaceOverlay: sf.Colors.white,
      panel: neutral[50],
      border: overlayBase.withValues(alpha: 0.12),
      borderSubtle: overlayBase.withValues(alpha: 0.07),
      mutedText: zinc[600],
      textPrimary: zinc[950],
      textSecondary: zinc[600],
      // 与深色同理：zinc.500 落在最暗的 control 档（zinc.100）上只有 4.4:1，
      // 向 zinc.600 压一档才能在全部四档表面上守住 AA。
      textTertiary: Color.lerp(zinc[500], zinc[600], 0.2)!,
      accent: brand,
      intelligenceAccent: violet[500],
      primaryMuted: brand.withValues(alpha: 0.24),
      warning: amber[700],
      error: red[500],
      success: green[600],
      onSuccess: sf.Colors.white,
      info: sky[600],
      onWarning: sf.Colors.white,
      onInfo: sf.Colors.white,
      // 浅色选中态落在浅灰底上，强调图标用品牌蓝而非白色。
      accentForeground: brand,
      onAccent: sf.Colors.white,
      windowHover: overlayBase.withValues(alpha: 0.08),
      windowIcon: zinc[500],
      closeHover: red[500],
      hoverSurface: overlayBase.withValues(alpha: 0.05),
      pressedSurface: overlayBase.withValues(alpha: 0.08),
      selectedSurface: overlayBase.withValues(alpha: 0.08),
      selectedHoverSurface: overlayBase.withValues(alpha: 0.12),
      focusRing: brand,
    );
  }

  /// 应用框架与标题栏的语义背景；允许与 pane 共用同一色阶。
  ///
  /// 生效位置：`WindowFrame` 外框与标题栏、Material `Scaffold` 和
  /// shadcn 根背景、面板拖拽分隔区，以及 `IdeTab`/Composer 选择器的
  /// 展开态背景。
  final Color frame;

  /// 默认 pane 内容表面；名称表达用途，不约束它与 [frame] 的明度顺序。
  ///
  /// 生效位置：Material canvas/card、shadcn card、Agent 上下文侧栏，
  /// 以及模型配置中的分段控件容器。
  final Color surface;

  /// 嵌套控件与内容分组的对比表面。
  ///
  /// “Elevated” 表达视觉分组，不要求深浅主题采用相同的明度方向。
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

  /// 高级智能能力与高计算强度状态的强调色。
  ///
  /// 生效位置：模型最高思考档位、未来需要表达增强推理能力的状态提示。
  /// 与品牌主操作使用的 [accent] 分离，避免紫色能力提示改变全局交互语义。
  final Color intelligenceAccent;

  /// [accent] 的半透明弱化背景，用于蓝色弱强调。
  ///
  /// 生效位置：可操作提示、少量活动状态和 Markdown 文本选区。普通导航、
  /// 列表选中与用户消息气泡分别使用 [selectedSurface] 和 [hoverSurface]。
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

  /// Foreground shown on [success].
  final Color onSuccess;

  /// 中性说明、正常运行和搜索/系统事件的状态色。
  ///
  /// 生效位置：info 日志/状态卡、Agent 搜索与系统事件、模型下回合生效提示、
  /// 用户问题图标和 Markdown 引用边线，以及图表 `chart2`。
  final Color info;

  /// Foreground shown on [warning].
  final Color onWarning;

  /// Foreground shown on [info].
  final Color onInfo;

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

  /// 普通可交互控件的悬停背景；同一档极浅灰也用作静态卡片底色。
  ///
  /// 生效位置：`PaneInteractiveSurface` 默认 hover；设置页导航项 hover；
  /// Agent 消息区可点击块 hover；Material `hoverColor` 投影；用户消息气泡、
  /// Agent 统计套餐额度卡片与 Token 统计网格等静态浅底容器。
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

  /// 键盘焦点和输入焦点的统一描边色。
  ///
  /// 生效位置：Composer 外卡聚焦边与统一 focus ring；模型配置/控件
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

  /// 深色调色板：Zinc 语义方案 + neutral/Zinc 表面 + blue 品牌主色。
  ///
  /// 各参数的具体生效位置见上方同名字段注释。
  static final AppColors dark = AppColors.fromShadcnColorScheme(
    sf.ColorSchemes.darkZinc,
  );

  /// 浅色调色板：Zinc 语义方案 + neutral/Zinc 表面 + blue 品牌主色。
  ///
  /// 与深色主题共享语义用途，不共享固定明度顺序；各参数的具体生效位置见上方注释。
  static final AppColors light = AppColors.fromShadcnColorScheme(
    sf.ColorSchemes.lightZinc,
  );

  /// Reads the semantic palette from the nearest Material theme.
  static AppColors of(BuildContext context) {
    return Theme.of(context).extension<AppColors>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  /// 复制当前调色板并替换指定语义颜色。
  ///
  /// [mutedText] 是 [textSecondary] 的历史兼容别名；仅覆盖其中任意一个时，
  /// 本方法会同步另一个，避免新旧调用点出现不一致的辅助前景色。
  @override
  AppColors copyWith({
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
    Color? intelligenceAccent,
    Color? primaryMuted,
    Color? warning,
    Color? error,
    Color? success,
    Color? onSuccess,
    Color? info,
    Color? onWarning,
    Color? onInfo,
    Color? accentForeground,
    Color? onAccent,
    Color? windowHover,
    Color? windowIcon,
    Color? closeHover,
    Color? hoverSurface,
    Color? pressedSurface,
    Color? selectedSurface,
    Color? selectedHoverSurface,
    Color? focusRing,
  }) {
    final resolvedTextSecondary =
        textSecondary ?? mutedText ?? this.textSecondary;
    final resolvedMutedText = mutedText ?? textSecondary ?? this.mutedText;
    return AppColors(
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
      intelligenceAccent: intelligenceAccent ?? this.intelligenceAccent,
      primaryMuted: primaryMuted ?? this.primaryMuted,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      info: info ?? this.info,
      onWarning: onWarning ?? this.onWarning,
      onInfo: onInfo ?? this.onInfo,
      accentForeground: accentForeground ?? this.accentForeground,
      onAccent: onAccent ?? this.onAccent,
      windowHover: windowHover ?? this.windowHover,
      windowIcon: windowIcon ?? this.windowIcon,
      closeHover: closeHover ?? this.closeHover,
      hoverSurface: hoverSurface ?? this.hoverSurface,
      pressedSurface: pressedSurface ?? this.pressedSurface,
      selectedSurface: selectedSurface ?? this.selectedSurface,
      selectedHoverSurface: selectedHoverSurface ?? this.selectedHoverSurface,
      focusRing: focusRing ?? this.focusRing,
    );
  }

  /// 在当前调色板与 [other] 之间逐项插值，用于主题过渡动画。
  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
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
      intelligenceAccent: Color.lerp(
        intelligenceAccent,
        other.intelligenceAccent,
        t,
      )!,
      primaryMuted: Color.lerp(primaryMuted, other.primaryMuted, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      info: Color.lerp(info, other.info, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
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
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
    );
  }
}
