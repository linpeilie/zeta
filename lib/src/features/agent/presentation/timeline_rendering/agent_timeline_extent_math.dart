/// 时间线高度估算的共享算式。
///
/// renderer 与 [AgentTimelineExtentDescriptorFactory] 必须用同一份公式：估算与
/// 真实高度脱节会让长会话滚动出现跳动（锚点靠估算高度维持）。这里只放纯函数，
/// 不含任何分发或类型分支。
library;

import 'dart:math' as math;

/// 归一化后的估算度量。
///
/// 宽度非法（非有限 / 非正）时回退 720，缩放非法时回退 1.0——冷启动首帧拿不到
/// 真实约束时也必须给出有限估算。
final class AgentTimelineExtentMetrics {
  const AgentTimelineExtentMetrics._({
    required this.width,
    required this.scale,
  });

  /// 从原始布局输入归一化。
  factory AgentTimelineExtentMetrics.from({
    required double crossAxisExtent,
    required double textScale,
  }) {
    return AgentTimelineExtentMetrics._(
      width: crossAxisExtent.isFinite && crossAxisExtent > 0
          ? crossAxisExtent
          : 720.0,
      scale: textScale.isFinite && textScale > 0 ? textScale : 1.0,
    );
  }

  /// 有效交叉轴宽度（logical px）。
  final double width;

  /// 有效文本缩放。
  final double scale;

  /// 单行文本高度。
  double get lineHeight => 18.0 * scale;
}

/// 计划交互卡底部输入框 + 动作栏 + 分隔线的固定高度。
double agentPlanInteractionChromeExtent(double scale) => 120 * scale;

/// 操作组（命令集 / 文件编辑组）的上下外间距合计（未乘缩放）。
///
/// 与 `operationGroupOuterPadding` 保持一致：块内 2、块外 10。
double agentOperationGroupOuterExtent({
  required bool precededByOperationGroup,
  required bool followedByOperationGroup,
}) {
  final top = precededByOperationGroup ? 0.0 : 10.0;
  final bottom = followedByOperationGroup ? 2.0 : 10.0;
  return top + bottom;
}

/// 按源行逐行累加折行，估算一段 Markdown 的渲染高度。
double estimateAgentMarkdownExtent(
  String text, {
  required double width,
  required double lineHeight,
  required double scale,
}) {
  // 全文渲染：历史与 live 均按完整内容估算高度，禁止折叠预览截断。
  final charsPerLine = math.max(24, (width / (7.5 * scale)).floor());
  var visualLines = 0;
  var blockSpacingLines = 0.0;
  var insideFence = false;
  for (final sourceLine in text.split('\n')) {
    final trimmed = sourceLine.trim();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      insideFence = !insideFence;
      visualLines += 1;
      blockSpacingLines += 0.5;
      continue;
    }

    // 必须逐源行累加折行；按全文字符数与显式行数取 max 会严重低估
    // “多行且每行都需要折行”的长 Markdown。
    final lineLength = trimmed.runes.length;
    final effectiveCharsPerLine = insideFence
        ? math.max(20, (charsPerLine * 0.9).floor())
        : charsPerLine;
    visualLines += math.max(1, (lineLength / effectiveCharsPerLine).ceil());

    if (trimmed.isEmpty) {
      blockSpacingLines += 0.45;
    } else if (!insideFence && trimmed.startsWith('#')) {
      blockSpacingLines += 0.7;
    } else if (!insideFence &&
        (trimmed.startsWith('- ') ||
            trimmed.startsWith('* ') ||
            trimmed.startsWith('> '))) {
      blockSpacingLines += 0.15;
    }
  }

  return (visualLines + blockSpacingLines) * lineHeight;
}
