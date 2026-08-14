import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 套餐窗口卡片之间的间距。
const double agentUsageQuotaGalleryGap = IdeSpacing.space8;

/// 画廊交叉轴高度：胶囊内边距 + 标签行 + 进度条 + 预留重置行。
const double agentUsageQuotaGalleryHeight =
    IdeSpacing.space8 * 2 + 15 + IdeSpacing.space6 + 4 + IdeSpacing.space2 + 13;

/// 套餐窗口在画廊视口中的卡片宽度：1 张 100%、2 张各约 50%、3 张及以上各 40%。
double agentUsageQuotaCardWidth({
  required double viewportWidth,
  required int windowCount,
}) {
  if (windowCount <= 1) {
    return viewportWidth;
  }
  if (windowCount == 2) {
    return (viewportWidth - agentUsageQuotaGalleryGap) / 2;
  }
  return viewportWidth * 0.4;
}

/// 固定高度的横向套餐额度画廊。
class AgentUsageQuotaGallery extends StatefulWidget {
  const AgentUsageQuotaGallery({required this.windows, super.key});

  /// Provider 返回的额度窗口，按原始顺序横向排布。
  final List<AgentUsageWindow> windows;

  @override
  State<AgentUsageQuotaGallery> createState() => _AgentUsageQuotaGalleryState();
}

class _AgentUsageQuotaGalleryState extends State<AgentUsageQuotaGallery> {
  final ScrollController _controller = ScrollController();
  bool _hovered = false;
  double _cardWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(covariant AgentUsageQuotaGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windows.length != widget.windows.length &&
        _controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _canScroll => widget.windows.length >= 3;

  bool get _canScrollBack =>
      _canScroll &&
      _controller.hasClients &&
      _controller.offset > _controller.position.minScrollExtent + 0.5;

  bool get _canScrollForward {
    if (!_canScroll) {
      return false;
    }
    if (!_controller.hasClients) {
      return true;
    }
    return _controller.offset < _controller.position.maxScrollExtent - 0.5;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is! PointerScrollEvent || !_controller.hasClients) {
        return;
      }
      final delta =
          resolved.scrollDelta.dx.abs() > resolved.scrollDelta.dy.abs()
          ? resolved.scrollDelta.dx
          : resolved.scrollDelta.dy;
      final position = _controller.position;
      final next = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next != position.pixels) {
        position.jumpTo(next);
      }
    });
  }

  Future<void> _scrollByCard(double direction) async {
    if (!_controller.hasClients || _cardWidth <= 0) {
      return;
    }
    final delta = (_cardWidth + agentUsageQuotaGalleryGap) * direction;
    final target = (_controller.offset + delta).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : IdeMotion.durationNormal;
    await _controller.animateTo(
      target,
      duration: duration,
      curve: IdeMotion.curveDefault,
    );
  }

  @override
  Widget build(BuildContext context) {
    final windows = widget.windows;
    return SizedBox(
      key: const ValueKey('agent-usage-quota-gallery'),
      height: agentUsageQuotaGalleryHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          _cardWidth = agentUsageQuotaCardWidth(
            viewportWidth: viewportWidth,
            windowCount: windows.length,
          );
          return MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    key: const ValueKey('agent-usage-quota-gallery-scroll'),
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    physics: _canScroll
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < windows.length;
                          index++
                        ) ...[
                          if (index > 0)
                            const SizedBox(width: agentUsageQuotaGalleryGap),
                          SizedBox(
                            width: _cardWidth,
                            height: agentUsageQuotaGalleryHeight,
                            child: _QuotaWindowCard(
                              key: ValueKey<String>(
                                'agent-usage-window-$index',
                              ),
                              window: windows[index],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _GalleryEdgeButton(
                    alignment: Alignment.centerLeft,
                    visible: _hovered && _canScroll,
                    enabled: _canScrollBack,
                    tooltip: '上一窗口',
                    icon: Icons.chevron_left_rounded,
                    buttonKey: const ValueKey('agent-usage-quota-prev-button'),
                    onPressed: () => unawaited(_scrollByCard(-1)),
                  ),
                  _GalleryEdgeButton(
                    alignment: Alignment.centerRight,
                    visible: _hovered && _canScroll,
                    enabled: _canScrollForward,
                    tooltip: '下一窗口',
                    icon: Icons.chevron_right_rounded,
                    buttonKey: const ValueKey('agent-usage-quota-next-button'),
                    onPressed: () => unawaited(_scrollByCard(1)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GalleryEdgeButton extends StatelessWidget {
  const _GalleryEdgeButton({
    required this.alignment,
    required this.visible,
    required this.enabled,
    required this.tooltip,
    required this.icon,
    required this.buttonKey,
    required this.onPressed,
  });

  final Alignment alignment;
  final bool visible;
  final bool enabled;
  final String tooltip;
  final IconData icon;
  final Key buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : IdeMotion.durationFast;
    return Align(
      alignment: alignment,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        curve: IdeMotion.curveDefault,
        child: IgnorePointer(
          ignoring: !visible || !enabled,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space2),
            child: IdeTooltip(
              message: tooltip,
              child: PaneInteractiveSurface(
                key: buttonKey,
                onPressed: enabled ? onPressed : null,
                enabled: enabled,
                button: true,
                semanticLabel: tooltip,
                width: IdeMetrics.iconButtonHitSize,
                height: IdeMetrics.iconButtonHitSize,
                padding: EdgeInsets.zero,
                borderRadius: IdeRadius.allSmall,
                backgroundColor: colors.surfaceOverlay.withValues(alpha: 0.92),
                child: Icon(
                  icon,
                  size: 16,
                  color: enabled ? colors.textSecondary : colors.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuotaWindowCard extends StatelessWidget {
  const _QuotaWindowCard({required this.window, super.key});

  final AgentUsageWindow window;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final used = window.usedPercent.clamp(0, 100);
    final remaining = (100 - used).clamp(0, 100);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.hoverSurface,
        borderRadius: IdeRadius.allSmall,
      ),
      child: Padding(
        padding: const EdgeInsets.all(IdeSpacing.space8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    window.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.bodySmall,
                  ),
                ),
                const SizedBox(width: IdeSpacing.space8),
                Text(
                  '$remaining%',
                  style: textStyles.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: IdeSpacing.space6),
            AgentUsageQuotaProgressBar(usedPercent: used.toDouble()),
            const SizedBox(height: IdeSpacing.space2),
            SizedBox(
              height: 13,
              child: window.resetsAt == null
                  ? null
                  : Text(
                      formatUsageResetAt(window.resetsAt!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前额度窗口的剩余进度条。
class AgentUsageQuotaProgressBar extends StatelessWidget {
  const AgentUsageQuotaProgressBar({required this.usedPercent, super.key});

  /// 已用百分比，0~100。
  final double usedPercent;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final used = usedPercent.clamp(0, 100);
    final remaining = 100 - used;
    final fraction = remaining / 100;
    return sf.LinearProgressIndicator(
      value: fraction,
      minHeight: 4,
      color: colors.textSecondary,
      backgroundColor: colors.borderSubtle,
      borderRadius: IdeRadius.allMicro,
      showSparks: false,
      disableAnimation: true,
    );
  }
}
