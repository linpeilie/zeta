import 'package:flutter/material.dart';

import 'package:zeta/src/core/constants/app_typography.dart';

import 'app_theme.dart';
import 'ide_colors.dart';

/// IDE 设计系统排版 token。
///
/// 通过 [of] 从 [IdeThemeScope] 读取当前颜色与字体/字号，按比例缩放生成
/// 语义 `TextStyle`。业务 UI 应使用本类字段，而不是裸 `TextStyle(fontSize: …)`。
///
/// 缩放规则：
/// - UI 样式字号 = 基准 × (`uiFontSize` / [defaultUiFontSize])
/// - 代码样式字号 = 基准 × (`codeFontSize` / [defaultCodeFontSize])
/// 用户在设置页改字号时，整表一起缩放。
@immutable
class IdeTextStyles {
  const IdeTextStyles({
    required this.displayLarge,
    required this.displaySmall,
    required this.titleLarge,
    required this.titleSmall,
    required this.bodyMedium,
    required this.bodySmall,
    required this.caption,
    required this.codeMedium,
    required this.codeSmall,
    required this.pageTitle,
    required this.sectionTitle,
    required this.rowTitle,
    required this.toolbarLabel,
    required this.proseBody,
    required this.meta,
    required this.metricValue,
    required this.placeholder,
  });

  /// 最大展示标题（基准 18 / w700）。
  ///
  /// 生效位置：Agent Markdown `h1`（`agent_pane_styles`）；空状态大标题等。
  final TextStyle displayLarge;

  /// 次级展示标题（基准 15 / w700）。
  ///
  /// 生效位置：Agent Markdown `h2`；用量统计空状态标题等。
  final TextStyle displaySmall;

  /// 区块/卡片主标题（基准 13 / w700）。
  ///
  /// 生效位置：Agent 会话头标题、计划卡标题、Agent 管理能力卡标题、
  /// Markdown `h3` 等。
  final TextStyle titleLarge;

  /// 小组件标题（基准 12 / w600）。
  ///
  /// 生效位置：`IdeStatusCard` 标题、上下文面板分组标题、Markdown 表头/`h4`、
  /// 用量统计任务组标题等。
  final TextStyle titleSmall;

  /// 默认正文（基准 12 / w400，主色）。
  ///
  /// 生效位置：窗口标题栏文字、上下文菜单项、选择卡说明、消息正文回退、
  /// Composer 输入文字、大量列表主文案；Agent 摘要/项文本多基于此 `copyWith`。
  final TextStyle bodyMedium;

  /// 次级正文（基准 11 / w400）。
  ///
  /// 生效位置：`IdeTabs` 标签、Toast 文案、文件树节点名、项目列表元信息、
  /// Agent 头部/工具卡/Composer 辅助文案、Pane 空状态等——使用面最广的小字。
  final TextStyle bodySmall;

  /// 说明/标签（基准 10 / w500，三级色）。
  ///
  /// 生效位置：项目列表时间戳与状态 chip、Agent 头部元数据、上下文面板字段标签、
  /// 用量统计筛选说明、日志副标题等。
  final TextStyle caption;

  /// 中等代码字（基准 12 / 代码字体 / w500）。
  ///
  /// 目标生效位置：行内代码、配置片段主显示。
  /// 当前较少直接引用：多数代码场景用 [codeSmall] 或 Markdown 代码样式。
  final TextStyle codeMedium;

  /// 小号代码字（基准 11 / 代码字体 / 次级色）。
  ///
  /// 生效位置：Agent 管理路径/版本字符串、配置编辑器关键字、日志时间戳与
  /// 消息体、上下文面板 JSON/路径、Markdown 代码块基样式等。
  final TextStyle codeSmall;

  /// 页面顶栏标题（基准 15 / w600）。
  ///
  /// 生效位置：`IdePageHeader` 标题；Agent 日志页标题。
  final TextStyle pageTitle;

  /// 页面内 section 标题（基准 13 / w600）。
  ///
  /// 生效位置：`IdeSection` 标题；配置编辑器「配置文件」等分组标题。
  final TextStyle sectionTitle;

  /// 列表/表格行主标题（基准 12 / w500）。
  ///
  /// 生效位置：Agent 管理模型列表行显示名等行级标题。
  final TextStyle rowTitle;

  /// 工具条/指标条标签（基准 11 / w500，次级色）。
  ///
  /// 生效位置：`CompactMetricBar` 指标标签；`IdeDataRow` 默认标签样式。
  final TextStyle toolbarLabel;

  /// 长文阅读正文（基准 13 / 行高 1.55）。
  ///
  /// 生效位置：Agent 助手回复 Markdown 基样式与段落（`agent_pane_styles` /
  /// `agent_pane_messages`）。
  final TextStyle proseBody;

  /// 元数据（基准 10 / w400，三级色）。
  ///
  /// 生效位置：Agent 时间线 meta、工具摘要行（`agent_pane_styles`）；
  /// Agent 管理状态 meta。
  final TextStyle meta;

  /// 指标数值（基准 18 / w600）。
  ///
  /// 生效位置：`CompactMetricBar` 大号数值。
  final TextStyle metricValue;

  /// 输入占位符（基准 12 / 三级色）。
  ///
  /// 目标生效位置：文本框 placeholder。
  /// 当前未直接引用：多数输入用 shadcn `placeholder:` 子组件自带样式；
  /// 需要 Graphite 一致占位符时再接此 token。
  final TextStyle placeholder;

  /// 从当前上下文解析语义排版。
  ///
  /// 字体与字号来自 [IdeThemeScope]（由外观设置注入）；颜色来自
  /// [IdeColors.of]。可选 [codeFontFamily] 仅覆盖代码字体。
  static IdeTextStyles of(BuildContext context, {String? codeFontFamily}) {
    final ideTheme = IdeThemeScope.of(context);
    return resolve(
      colors: ideTheme.colors,
      uiFontFamily: ideTheme.uiFontFamily,
      uiFontFamilyFallback: ideTheme.uiFontFamilyFallback,
      codeFontFamily: codeFontFamily == null || codeFontFamily.isEmpty
          ? ideTheme.codeFontFamily
          : codeFontFamily,
      uiFontSize: ideTheme.uiFontSize,
      codeFontSize: ideTheme.codeFontSize,
    );
  }

  /// 按照统一 token 生成语义排版集合。
  ///
  /// 测试或无 `BuildContext` 时可用；生产路径优先 [of]。
  static IdeTextStyles resolve({
    required IdeColors colors,
    String? uiFontFamily,
    List<String> uiFontFamilyFallback = const <String>[],
    String codeFontFamily = bundledCodeFontFamily,
    double uiFontSize = defaultUiFontSize,
    double codeFontSize = defaultCodeFontSize,
  }) {
    final uiScale = uiFontSize / defaultUiFontSize;
    final codeScale = codeFontSize / defaultCodeFontSize;
    return IdeTextStyles(
      displayLarge: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 18 * uiScale,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 15 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 13 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 12 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 12 * uiScale,
        height: 1.42,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 11 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
      caption: _textStyle(
        color: colors.textTertiary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 10 * uiScale,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
      codeMedium: _textStyle(
        color: colors.textPrimary,
        fontFamily: codeFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 12 * codeScale,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      codeSmall: _textStyle(
        color: colors.textSecondary,
        fontFamily: codeFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 11 * codeScale,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
      pageTitle: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 15 * uiScale,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      sectionTitle: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 13 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      rowTitle: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 12 * uiScale,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      toolbarLabel: _textStyle(
        color: colors.textSecondary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 11 * uiScale,
        height: 1.25,
        fontWeight: FontWeight.w500,
      ),
      proseBody: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 13 * uiScale,
        height: 1.55,
        fontWeight: FontWeight.w400,
      ),
      meta: _textStyle(
        color: colors.textTertiary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 10 * uiScale,
        height: 1.3,
        fontWeight: FontWeight.w400,
      ),
      metricValue: _textStyle(
        color: colors.textPrimary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 18 * uiScale,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
      placeholder: _textStyle(
        color: colors.textTertiary,
        fontFamily: uiFontFamily,
        fontFamilyFallback: uiFontFamilyFallback,
        fontSize: 12 * uiScale,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

TextStyle _textStyle({
  required Color color,
  required double fontSize,
  required double height,
  required FontWeight fontWeight,
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) {
  return TextStyle(
    color: color,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: fontSize,
    height: height,
    fontWeight: fontWeight,
  );
}
