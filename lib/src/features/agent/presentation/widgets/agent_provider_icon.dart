import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';

const Map<String, String> _agentProviderIconAssets = <String, String>{
  defaultAgentProviderId: 'assets/icons/agents/codex.svg',
  grokAgentProviderId: 'assets/icons/agents/grok.svg',
};

/// 使用稳定 Provider id 渲染对应的 Agent 品牌图标。
///
/// 内置品牌使用随主题着色的 SVG；未知 Provider 回退到与协议类型匹配的
/// Material 图标，避免 presentation 调用方自行维护资源映射。
class AgentProviderIcon extends StatelessWidget {
  /// 创建 Agent Provider 图标。
  const AgentProviderIcon({
    required this.providerId,
    super.key,
    this.kind,
    this.size = 18,
    this.color,
    this.semanticLabel,
  });

  /// Provider 的稳定配置 id。
  final String providerId;

  /// 未找到品牌资源时用于选择回退图标的协议类型。
  final AgentProviderKind? kind;

  /// 图标的逻辑宽高。
  final double size;

  /// 单色 SVG 与回退图标使用的颜色；默认使用 IDE 次级文本色。
  final Color? color;

  /// 图标独立表达信息时使用的无障碍标签。
  ///
  /// 未提供时图标视为装饰内容，避免与外层列表行的语义重复。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IdeColors.of(context).textSecondary;
    final assetPath = _agentProviderIconAssets[providerId];
    if (assetPath == null) {
      return _buildFallback(effectiveColor);
    }

    final normalizedSemanticLabel = semanticLabel?.trim();
    final hasSemanticLabel = normalizedSemanticLabel?.isNotEmpty ?? false;
    return svg.SvgPicture.asset(
      assetPath,
      key: ValueKey<String>('agent-provider-icon-svg-$providerId'),
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
      semanticsLabel: hasSemanticLabel ? normalizedSemanticLabel : null,
      excludeFromSemantics: !hasSemanticLabel,
      placeholderBuilder: (_) => SizedBox.square(dimension: size),
      errorBuilder: (_, _, _) => _buildFallback(effectiveColor),
    );
  }

  Widget _buildFallback(Color effectiveColor) {
    final normalizedSemanticLabel = semanticLabel?.trim();
    return Icon(
      _fallbackIcon(kind),
      key: ValueKey<String>('agent-provider-icon-fallback-$providerId'),
      size: size,
      color: effectiveColor,
      semanticLabel: normalizedSemanticLabel?.isEmpty ?? true
          ? null
          : normalizedSemanticLabel,
    );
  }
}

IconData _fallbackIcon(AgentProviderKind? kind) => switch (kind) {
  AgentProviderKind.codexAppServer => Icons.code_rounded,
  AgentProviderKind.acp => Icons.smart_toy_outlined,
  AgentProviderKind.cursorAcp => Icons.block_rounded,
  AgentProviderKind.claudeCode => Icons.terminal_rounded,
  null => Icons.extension_outlined,
};
