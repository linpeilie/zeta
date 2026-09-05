import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/features/agent/application/agent_provider_icon_resolver.dart';

import 'package:zeta_ui/zeta_ui.dart';

/// 使用稳定 Provider id 渲染对应的 Agent 品牌图标。
///
/// 品牌由插件静态描述声明保留原色或随主题着色；未知 Provider 使用中立扩展
/// 图标。presentation 不读取协议类型，也不参与插件路由。
class AgentProviderIcon extends ConsumerWidget {
  /// 创建 Agent Provider 图标。
  const AgentProviderIcon({
    required this.providerId,
    super.key,
    this.size = 18,
    this.color,
    this.semanticLabel,
  });

  /// Provider 的稳定配置 id。
  final String providerId;

  /// 图标的逻辑宽高。
  final double size;

  /// 可主题着色的单色 SVG 与回退图标使用的颜色；默认使用 IDE 次级文本色。
  ///
  /// 对声明保留品牌原色的 SVG（如 Claude）不生效。
  final Color? color;

  /// 图标独立表达信息时使用的无障碍标签。
  ///
  /// 未提供时图标视为装饰内容，避免与外层列表行的语义重复。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveColor = color ?? IdeColors.of(context).textSecondary;
    final asset = ref.watch(agentProviderIconResolverProvider)(providerId);
    if (asset == null) {
      return _buildFallback(effectiveColor);
    }

    final normalizedSemanticLabel = semanticLabel?.trim();
    final hasSemanticLabel = normalizedSemanticLabel?.isNotEmpty ?? false;
    return svg.SvgPicture.asset(
      asset.assetPath,
      package: asset.packageName,
      key: ValueKey<String>('agent-provider-icon-svg-$providerId'),
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: asset.colorPolicy == AgentIconColorPolicy.original
          ? null
          : ColorFilter.mode(effectiveColor, BlendMode.srcIn),
      semanticsLabel: hasSemanticLabel ? normalizedSemanticLabel : null,
      excludeFromSemantics: !hasSemanticLabel,
      placeholderBuilder: (_) => SizedBox.square(dimension: size),
      errorBuilder: (_, _, _) => _buildFallback(effectiveColor),
    );
  }

  Widget _buildFallback(Color effectiveColor) {
    final normalizedSemanticLabel = semanticLabel?.trim();
    return Icon(
      Icons.extension_outlined,
      key: ValueKey<String>('agent-provider-icon-fallback-$providerId'),
      size: size,
      color: effectiveColor,
      semanticLabel: normalizedSemanticLabel?.isEmpty ?? true
          ? null
          : normalizedSemanticLabel,
    );
  }
}
