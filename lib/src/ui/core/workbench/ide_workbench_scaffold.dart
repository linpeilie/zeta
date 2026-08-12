import 'package:flutter/widgets.dart';
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
    this.navigationInlineInCompact = false,
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

  /// 是否在紧凑模式下仍以内联方式保留导航面板。
  ///
  /// 适用于没有 Activity Rail 触发入口、但仍必须保持导航可用的页面。
  final bool navigationInlineInCompact;

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
            (mode != IdeWorkbenchLayoutMode.compact ||
                navigationInlineInCompact);
        final inspectorInline =
            inspector != null &&
            inspectorVisible &&
            mode == IdeWorkbenchLayoutMode.wide;

        // 基础 Row 使用稳定 key，避免 Wide/Medium/Compact 切换时卸载 Canvas。
        // 所有直接 child 都带稳定 key，防止条件 slot 插入/删除时 Element 误匹配。
        final base = Row(
          key: const ValueKey('workbench-base'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (leadingRail case final Widget rail) ...[
              // 左栏：scaffold 内外侧贴边（外距由 IdeHome space4 提供），
              // 内侧与内容间距 space4。
              SizedBox(
                key: const ValueKey('workbench-leading-rail'),
                width: IdeMetrics.activityRailWidth,
                child: rail,
              ),
              const SizedBox(
                key: ValueKey('workbench-leading-rail-gap'),
                width: IdeSpacing.space4,
              ),
            ],
            if (navigationInline) ...[
              SizedBox(
                key: const ValueKey('workbench-navigation-inline'),
                width: resolvedNavigationWidth,
                child: navigation,
              ),
              _PaneSeparator(
                key: const ValueKey('workbench-navigation-separator'),
                child: navigationResizeHandle,
              ),
            ],
            Expanded(
              key: const ValueKey('workbench-canvas-slot'),
              child: KeyedSubtree(
                key: const ValueKey('workbench-canvas'),
                // 列级圆角 + 与侧栏一致的边框；内容区 IdeSurface.canvas 仍默认无描边。
                child: IdeSurface(
                  level: IdeSurfaceLevel.canvas,
                  borderRadius: IdeRadius.allLarge,
                  showBorder: true,
                  child: canvas,
                ),
              ),
            ),
            if (inspectorInline) ...[
              _PaneSeparator(
                key: const ValueKey('workbench-inspector-separator'),
                child: inspectorResizeHandle,
              ),
              SizedBox(
                key: const ValueKey('workbench-inspector-inline'),
                width: resolvedInspectorWidth,
                child: inspector,
              ),
            ],
            if (trailingRail case final Widget rail) ...[
              // 右栏：内侧 space4，scaffold 内外侧贴边；与左栏镜像。
              const SizedBox(
                key: ValueKey('workbench-trailing-rail-gap'),
                width: IdeSpacing.space4,
              ),
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
        // inset 须与 rail 列宽 + 内侧 gap（space4）一致；外侧无额外 gap。
        final leadingInset = leadingRail == null
            ? 0.0
            : IdeMetrics.activityRailWidth + IdeSpacing.space4;
        final trailingInset = trailingRail == null
            ? 0.0
            : IdeSpacing.space4 + IdeMetrics.activityRailWidth;
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
        return _WorkbenchOverlayKeyboardScope(
          onDismiss: dismissOverlay,
          child: overlayStack,
        );
      },
    );
  }
}

/// Overlay 是模态层；即使触发按钮位于 Workbench 外（例如窗口标题栏），
/// Esc 也必须能关闭当前浮层。全局监听仅在 Overlay 挂载期间存在。
class _WorkbenchOverlayKeyboardScope extends StatefulWidget {
  const _WorkbenchOverlayKeyboardScope({
    required this.onDismiss,
    required this.child,
  });

  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_WorkbenchOverlayKeyboardScope> createState() =>
      _WorkbenchOverlayKeyboardScopeState();
}

class _WorkbenchOverlayKeyboardScopeState
    extends State<_WorkbenchOverlayKeyboardScope> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    widget.onDismiss();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
    // 两侧总占用均为 栏宽 + 内侧 space4（外侧贴边）。
    final railExtent =
        (leadingRailAvailable
            ? IdeMetrics.activityRailWidth + IdeSpacing.space4
            : 0) +
        (trailingRailAvailable
            ? IdeSpacing.space4 + IdeMetrics.activityRailWidth
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
  const _PaneSeparator({super.key, this.child});

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
        borderRadius: IdeRadius.allLarge,
        boxShadow: IdeEffects.overlayShadow(brightness),
      ),
      child: child,
    );
  }
}
