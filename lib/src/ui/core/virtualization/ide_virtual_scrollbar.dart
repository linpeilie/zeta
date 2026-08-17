/// 项目级虚拟列表滚动条与“滚到底部”按钮。
///
/// 消费真实 [ScrollMetrics]，不按 item 数量模拟 thumb。禁用子树自动
/// scrollbar，避免双 thumb。视觉映射 Graphite / Ide 设计令牌。
library;

import 'package:flutter/material.dart';

import '../ide_colors.dart';
import '../ide_effects.dart';
import '../ide_motion.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';
import '../pane_widgets.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'ide_virtual_scroll_coordinator.dart';

/// 默认滚动条语义标签。
const String kIdeVirtualScrollbarSemanticLabel = '对话滚动条';

/// 滚到底部按钮默认语义。
const String kIdeScrollToEndButtonSemanticLabel = '滚动到对话底部';

/// 项目级 RawScrollbar 包装：绑定同一 [ScrollController]，关闭自动双条。
class IdeVirtualScrollbar extends StatelessWidget {
  /// 创建虚拟列表滚动条。
  const IdeVirtualScrollbar({
    required this.controller,
    required this.child,
    super.key,
    this.semanticLabel = kIdeVirtualScrollbarSemanticLabel,
    this.thickness = 8,
    this.minThumbLength = 32,
    this.padding = EdgeInsets.zero,
  });

  /// 与列表共用的滚动控制器。
  final ScrollController controller;

  /// 通常为关闭了自动 scrollbar 的 [CustomScrollView]。
  final Widget child;

  /// 无障碍名称。
  final String semanticLabel;

  /// thumb 默认厚度（logical px）。
  final double thickness;

  /// thumb 最小长度。
  final double minThumbLength;

  /// 滚动条内边距。
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    // 只画 thumb，不画轨道底色；alpha 压低以免压过时间线内容。
    final thumbColor = colors.textTertiary.withValues(alpha: 0.22);

    return Semantics(
      container: true,
      label: semanticLabel,
      child: RawScrollbar(
        controller: controller,
        thumbVisibility: true,
        trackVisibility: false,
        interactive: true,
        thickness: thickness,
        radius: const Radius.circular(IdeRadius.small),
        minThumbLength: minThumbLength,
        padding: padding,
        thumbColor: thumbColor,
        trackColor: Colors.transparent,
        trackBorderColor: Colors.transparent,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: child,
        ),
      ),
    );
  }
}

/// free 模式下显示的“滚到底部”浮动按钮。
///
/// 不是滚动条的一部分；由 coordinator 的
/// [IdeVirtualScrollCoordinator.shouldShowScrollToEndButton] 控制可见性。
class IdeScrollToEndButton extends StatelessWidget {
  /// 创建滚到底部按钮。
  const IdeScrollToEndButton({
    required this.onPressed,
    super.key,
    this.hasNewContent = false,
    this.semanticLabel = kIdeScrollToEndButtonSemanticLabel,
  });

  /// 点击后应进入 followEnd 并 reveal 末项。
  final VoidCallback onPressed;

  /// streaming 期间可提示有新内容（v1 不要求未读计数）。
  final bool hasNewContent;

  /// 无障碍名称。
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);

    return PaneInteractiveSurface(
      onPressed: onPressed,
      button: true,
      semanticLabel: semanticLabel,
      borderRadius: IdeRadius.allMedium,
      backgroundColor: colors.surfaceElevated,
      hoverBackgroundColor: colors.hoverSurface,
      pressedBackgroundColor: colors.pressedSurface,
      borderColor: colors.borderSubtle,
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space12,
        vertical: IdeSpacing.space8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.arrow_downward_rounded,
            size: 14,
            color: hasNewContent ? colors.accent : colors.textSecondary,
          ),
          const SizedBox(width: IdeSpacing.space6),
          Text(
            hasNewContent
                ? context.l10n.timelineNewContent
                : context.l10n.timelineBackToBottom,
            style: textStyles.bodySmall.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 将滚动条与可选“滚到底部”按钮组合在一起的壳层。
///
/// 默认不替换 Agent 生产路径；测试与阶段 4 集成可复用此结构。
class IdeVirtualScrollShell extends StatelessWidget {
  /// 创建滚动壳层。
  const IdeVirtualScrollShell({
    required this.controller,
    required this.child,
    super.key,
    this.coordinator,
    this.semanticLabel = kIdeVirtualScrollbarSemanticLabel,
    this.showScrollToEndButton = false,
    this.hasNewContent = false,
    this.onScrollToEnd,
    this.scrollToEndSemanticLabel = kIdeScrollToEndButtonSemanticLabel,
  });

  /// 与列表共用 controller。
  final ScrollController controller;

  /// 可滚动内容（应已关闭自动 scrollbar 或交由 [IdeVirtualScrollbar] 关闭）。
  final Widget child;

  /// 可选协调器；若提供且 [showScrollToEndButton] 未强制，可推导按钮可见性。
  final IdeVirtualScrollCoordinator? coordinator;

  /// 滚动条语义。
  final String semanticLabel;

  /// 是否显示滚到底部按钮。
  final bool showScrollToEndButton;

  /// 是否提示新内容。
  final bool hasNewContent;

  /// 点击滚到底部。
  final VoidCallback? onScrollToEnd;

  /// 按钮语义。
  final String scrollToEndSemanticLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IdeVirtualScrollbar(
            controller: controller,
            semanticLabel: semanticLabel,
            child: child,
          ),
        ),
        if (showScrollToEndButton && onScrollToEnd != null)
          Positioned(
            right: IdeSpacing.space12,
            bottom: IdeSpacing.space12,
            child: AnimatedOpacity(
              opacity: 1,
              duration: IdeMotion.durationFast,
              child: IdeScrollToEndButton(
                onPressed: onScrollToEnd!,
                hasNewContent: hasNewContent,
                semanticLabel: scrollToEndSemanticLabel,
              ),
            ),
          ),
      ],
    );
  }
}

/// 从 [ScrollNotification] 识别用户滚动并转发给 coordinator。
///
/// 接受 [UserScrollNotification] 与带 [DragUpdateDetails] 的
/// [ScrollUpdateNotification]。programmatic 期间一律忽略。
bool dispatchUserScrollToCoordinator({
  required IdeVirtualScrollCoordinator coordinator,
  required ScrollNotification notification,
  required ScrollController controller,
}) {
  if (coordinator.isProgrammatic) {
    return false;
  }

  final isUserDragUpdate =
      notification is ScrollUpdateNotification &&
      notification.dragDetails != null;
  final accept = notification is UserScrollNotification || isUserDragUpdate;
  if (!accept) {
    return false;
  }
  if (!controller.hasClients) {
    return false;
  }

  final position = controller.position;
  coordinator.onUserScroll(
    IdeVirtualScrollMetricsSnapshot(
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
      viewportDimension: position.viewportDimension,
    ),
  );
  return true;
}
