import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../ide_effects.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../surfaces/ide_surface.dart';

/// 工作台按父容器宽度解析出的布局模式。
enum IdeWorkbenchLayoutMode { wide, medium, compact }

/// 工作台当前唯一打开的覆盖层。
enum IdeWorkbenchOverlay { navigation, inspector }

/// Rail 构建器会收到考虑最小 Canvas 宽度后的最终布局模式。
typedef IdeWorkbenchRailBuilder =
    Widget Function(BuildContext context, IdeWorkbenchLayoutMode mode);

/// 按统一断点解析工作台的名义模式。
IdeWorkbenchLayoutMode resolveWorkbenchLayoutMode(double width) {
  if (width >= IdeMetrics.wideBreakpoint) {
    return IdeWorkbenchLayoutMode.wide;
  }
  if (width >= IdeMetrics.mediumBreakpoint) {
    return IdeWorkbenchLayoutMode.medium;
  }
  return IdeWorkbenchLayoutMode.compact;
}

/// 统一 IDE Rail、Pane、Canvas 与窄屏 Overlay 的页面骨架。
///
/// 组件只负责布局决策；Pane 可见性、宽度和 Overlay 打开状态仍由调用方持有。
/// 当名义断点无法为中央 Canvas 保留最小宽度时，会自动降级到下一布局模式。
class IdeWorkbenchScaffold extends StatelessWidget {
  const IdeWorkbenchScaffold({
    required this.canvas,
    super.key,
    this.leadingRailBuilder,
    this.navigationPane,
    this.navigationResizeHandle,
    this.inspectorPane,
    this.inspectorResizeHandle,
    this.trailingRailBuilder,
    this.navigationVisible = true,
    this.inspectorVisible = true,
    this.activeOverlay,
    this.navigationWidth = IdeMetrics.sidePaneDefaultWidth,
    this.inspectorWidth = IdeMetrics.inspectorPaneWidth,
    this.onDismissOverlay,
    this.overlayTriggerFocusNode,
  }) : assert(navigationWidth >= 0),
       assert(inspectorWidth >= 0),
       assert(activeOverlay == null || onDismissOverlay != null);

  final Widget canvas;
  final IdeWorkbenchRailBuilder? leadingRailBuilder;
  final Widget? navigationPane;
  final Widget? navigationResizeHandle;
  final Widget? inspectorPane;
  final Widget? inspectorResizeHandle;
  final IdeWorkbenchRailBuilder? trailingRailBuilder;
  final bool navigationVisible;
  final bool inspectorVisible;
  final IdeWorkbenchOverlay? activeOverlay;
  final double navigationWidth;
  final double inspectorWidth;
  final VoidCallback? onDismissOverlay;

  /// 通过 Scrim 或 Esc 关闭 Overlay 后需要恢复焦点的触发控件。
  final FocusNode? overlayTriggerFocusNode;

  @override
  Widget build(BuildContext context) {
    final navigation = navigationPane;
    final inspector = inspectorPane;
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedNavigationWidth = navigationWidth
            .clamp(IdeMetrics.sidePaneMinWidth, IdeMetrics.sidePaneMaxWidth)
            .toDouble();
        final resolvedInspectorWidth = inspectorWidth
            .clamp(IdeMetrics.sidePaneMinWidth, IdeMetrics.sidePaneMaxWidth)
            .toDouble();
        final mode = _resolveEffectiveLayoutMode(
          width: constraints.maxWidth,
          navigationAvailable: navigation != null && navigationVisible,
          inspectorAvailable: inspector != null && inspectorVisible,
          leadingRailAvailable: leadingRailBuilder != null,
          trailingRailAvailable: trailingRailBuilder != null,
          navigationWidth: resolvedNavigationWidth,
          inspectorWidth: resolvedInspectorWidth,
        );
        final leadingRail = leadingRailBuilder?.call(context, mode);
        final trailingRail = trailingRailBuilder?.call(context, mode);
        final navigationInline =
            navigation != null &&
            navigationVisible &&
            mode != IdeWorkbenchLayoutMode.compact;
        final inspectorInline =
            inspector != null &&
            inspectorVisible &&
            mode == IdeWorkbenchLayoutMode.wide;

        final base = Row(
          key: ValueKey('workbench-base-${mode.name}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (leadingRail case final Widget rail) ...[
              SizedBox(
                key: const ValueKey('workbench-leading-rail'),
                width: IdeMetrics.activityRailWidth,
                child: rail,
              ),
              const SizedBox(width: IdeSpacing.space8),
            ],
            if (navigationInline) ...[
              SizedBox(
                key: const ValueKey('workbench-navigation-inline'),
                width: resolvedNavigationWidth,
                child: navigation,
              ),
              _PaneSeparator(child: navigationResizeHandle),
            ],
            Expanded(
              key: const ValueKey('workbench-canvas-slot'),
              child: KeyedSubtree(
                key: const ValueKey('workbench-canvas'),
                child: IdeSurface.canvas(child: canvas),
              ),
            ),
            if (inspectorInline) ...[
              _PaneSeparator(child: inspectorResizeHandle),
              SizedBox(
                key: const ValueKey('workbench-inspector-inline'),
                width: resolvedInspectorWidth,
                child: inspector,
              ),
            ],
            if (trailingRail case final Widget rail) ...[
              const SizedBox(width: IdeSpacing.space8),
              SizedBox(
                key: const ValueKey('workbench-trailing-rail'),
                width: IdeMetrics.activityRailWidth,
                child: rail,
              ),
            ],
          ],
        );

        final showNavigationOverlay =
            activeOverlay == IdeWorkbenchOverlay.navigation &&
            navigation != null &&
            navigationVisible &&
            !navigationInline;
        final showInspectorOverlay =
            activeOverlay == IdeWorkbenchOverlay.inspector &&
            inspector != null &&
            inspectorVisible &&
            !inspectorInline;

        if (!showNavigationOverlay && !showInspectorOverlay) {
          return base;
        }

        final brightness = sf.Theme.of(context).brightness;
        final leadingInset = leadingRail == null
            ? 0.0
            : IdeMetrics.activityRailWidth + IdeSpacing.space8;
        final trailingInset = trailingRail == null
            ? 0.0
            : IdeMetrics.activityRailWidth + IdeSpacing.space8;
        final availableOverlayWidth =
            (constraints.maxWidth - leadingInset - trailingInset)
                .clamp(0.0, double.infinity)
                .toDouble();
        final overlayWidth =
            (showNavigationOverlay
                    ? resolvedNavigationWidth
                    : resolvedInspectorWidth)
                .clamp(0.0, availableOverlayWidth)
                .toDouble();

        void dismissOverlay() {
          onDismissOverlay?.call();
          overlayTriggerFocusNode?.requestFocus();
        }

        final overlayStack = Stack(
          key: const ValueKey('workbench-overlay-stack'),
          children: [
            base,
            Positioned.fill(
              child: Semantics(
                button: true,
                label: 'Close workbench overlay',
                child: GestureDetector(
                  key: const ValueKey('workbench-overlay-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: dismissOverlay,
                  child: ColoredBox(color: IdeEffects.scrim(brightness)),
                ),
              ),
            ),
            if (showNavigationOverlay)
              Positioned(
                key: const ValueKey('workbench-navigation-overlay'),
                top: 0,
                bottom: 0,
                left: leadingInset,
                width: overlayWidth,
                child: _WorkbenchOverlaySurface(
                  brightness: brightness,
                  child: navigation,
                ),
              ),
            if (showInspectorOverlay)
              Positioned(
                key: const ValueKey('workbench-inspector-overlay'),
                top: 0,
                bottom: 0,
                right: trailingInset,
                width: overlayWidth,
                child: _WorkbenchOverlaySurface(
                  brightness: brightness,
                  child: inspector,
                ),
              ),
          ],
        );
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): dismissOverlay,
          },
          child: overlayStack,
        );
      },
    );
  }
}

IdeWorkbenchLayoutMode _resolveEffectiveLayoutMode({
  required double width,
  required bool navigationAvailable,
  required bool inspectorAvailable,
  required bool leadingRailAvailable,
  required bool trailingRailAvailable,
  required double navigationWidth,
  required double inspectorWidth,
}) {
  final requestedMode = resolveWorkbenchLayoutMode(width);

  bool fits({required bool includeInspector}) {
    final railExtent =
        (leadingRailAvailable
            ? IdeMetrics.activityRailWidth + IdeSpacing.space8
            : 0) +
        (trailingRailAvailable
            ? IdeMetrics.activityRailWidth + IdeSpacing.space8
            : 0);
    final navigationExtent = navigationAvailable
        ? navigationWidth + IdeSpacing.space8
        : 0;
    final inspectorExtent = includeInspector && inspectorAvailable
        ? inspectorWidth + IdeSpacing.space8
        : 0;
    return !width.isFinite ||
        width - railExtent - navigationExtent - inspectorExtent >=
            IdeMetrics.mainEditorMinWidth;
  }

  return switch (requestedMode) {
    IdeWorkbenchLayoutMode.wide when fits(includeInspector: true) =>
      IdeWorkbenchLayoutMode.wide,
    IdeWorkbenchLayoutMode.wide || IdeWorkbenchLayoutMode.medium
        when fits(includeInspector: false) =>
      IdeWorkbenchLayoutMode.medium,
    _ => IdeWorkbenchLayoutMode.compact,
  };
}

class _PaneSeparator extends StatelessWidget {
  const _PaneSeparator({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: IdeSpacing.space8, child: child);
  }
}

class _WorkbenchOverlaySurface extends StatelessWidget {
  const _WorkbenchOverlaySurface({
    required this.brightness,
    required this.child,
  });

  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: IdeRadius.allMedium,
        boxShadow: IdeEffects.overlayShadow(brightness),
      ),
      child: child,
    );
  }
}
