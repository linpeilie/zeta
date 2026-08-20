import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';

/// Responsive layout mode for an [IdeWorkbenchScaffold].
enum IdeWorkbenchLayoutMode {
  /// Navigation and inspector panes can be inline.
  wide,

  /// Navigation can be inline while the inspector uses an overlay.
  medium,

  /// Side panes use overlays unless navigation is explicitly retained inline.
  compact,
}

/// The single active workbench overlay.
enum IdeWorkbenchOverlay {
  /// Navigation-pane overlay.
  navigation,

  /// Inspector-pane overlay.
  inspector,
}

/// Builds a rail after the effective workbench mode has been resolved.
typedef IdeWorkbenchRailBuilder = Widget Function(
  BuildContext context,
  IdeWorkbenchLayoutMode mode,
);

/// Resolves the nominal workbench mode for [width].
IdeWorkbenchLayoutMode resolveWorkbenchLayoutMode(
  double width, {
  AppMetrics metrics = const AppMetrics(),
}) {
  if (width >= metrics.wideBreakpoint) return IdeWorkbenchLayoutMode.wide;
  if (width >= metrics.mediumBreakpoint) return IdeWorkbenchLayoutMode.medium;
  return IdeWorkbenchLayoutMode.compact;
}

/// Resolves the effective mode after reserving visible rail and pane extents.
IdeWorkbenchLayoutMode resolveEffectiveWorkbenchLayoutMode({
  required double width,
  required bool navigationAvailable,
  required bool inspectorAvailable,
  required bool leadingRailAvailable,
  required bool trailingRailAvailable,
  required double navigationWidth,
  required double inspectorWidth,
  AppMetrics metrics = const AppMetrics(),
  AppSpacing spacing = const AppSpacing(),
}) {
  final requestedMode = resolveWorkbenchLayoutMode(width, metrics: metrics);

  bool fits({required bool includeInspector}) {
    final railExtent =
        (leadingRailAvailable ? metrics.activityRailWidth + spacing.xxs : 0) +
        (trailingRailAvailable ? spacing.xxs + metrics.activityRailWidth : 0);
    final navigationExtent = navigationAvailable
        ? navigationWidth + spacing.xs
        : 0;
    final inspectorExtent = includeInspector && inspectorAvailable
        ? inspectorWidth + spacing.xs
        : 0;
    return !width.isFinite ||
        width - railExtent - navigationExtent - inspectorExtent >=
            metrics.mainEditorMinWidth;
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

/// A responsive desktop shell for rails, panes, canvas, and modal overlays.
///
/// Visibility, widths, and overlay state remain caller-owned. All localized
/// copy, including [closeOverlaySemanticLabel], is injected by the app.
class IdeWorkbenchScaffold extends StatelessWidget {
  /// Creates a workbench scaffold.
  const IdeWorkbenchScaffold({
    required this.canvas,
    required this.closeOverlaySemanticLabel,
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
    this.navigationWidth,
    this.inspectorWidth,
    this.onDismissOverlay,
    this.overlayTriggerFocusNode,
    super.key,
  }) : assert(
         closeOverlaySemanticLabel != '',
         'closeOverlaySemanticLabel must not be empty',
       ),
       assert(
         navigationWidth == null || navigationWidth >= 0,
         'navigationWidth must not be negative',
       ),
       assert(
         inspectorWidth == null || inspectorWidth >= 0,
         'inspectorWidth must not be negative',
       ),
       assert(
         activeOverlay == null || onDismissOverlay != null,
         'active overlays require onDismissOverlay',
       );

  /// Central workbench content.
  final Widget canvas;

  /// Localized accessible name for the overlay dismiss scrim.
  final String closeOverlaySemanticLabel;

  /// Optional leading rail builder.
  final IdeWorkbenchRailBuilder? leadingRailBuilder;

  /// Optional navigation pane.
  final Widget? navigationPane;

  /// Optional navigation resize affordance.
  final Widget? navigationResizeHandle;

  /// Optional inspector pane.
  final Widget? inspectorPane;

  /// Optional inspector resize affordance.
  final Widget? inspectorResizeHandle;

  /// Optional trailing rail builder.
  final IdeWorkbenchRailBuilder? trailingRailBuilder;

  /// Whether navigation is visible.
  final bool navigationVisible;

  /// Whether compact mode retains navigation inline.
  final bool navigationInlineInCompact;

  /// Whether the inspector is visible.
  final bool inspectorVisible;

  /// Currently active modal overlay.
  final IdeWorkbenchOverlay? activeOverlay;

  /// Caller-owned navigation width.
  final double? navigationWidth;

  /// Caller-owned inspector width.
  final double? inspectorWidth;

  /// Dismisses the current overlay.
  final VoidCallback? onDismissOverlay;

  /// Trigger that regains focus after the overlay closes.
  final FocusNode? overlayTriggerFocusNode;

  @override
  Widget build(BuildContext context) {
    final metrics = context.appMetrics;
    final spacing = context.appSpacing;
    final navigation = navigationPane;
    final inspector = inspectorPane;
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedNavigationWidth =
            (navigationWidth ?? metrics.sidePaneDefaultWidth).clamp(
              metrics.sidePaneMinWidth,
              metrics.sidePaneMaxWidth,
            );
        final resolvedInspectorWidth =
            (inspectorWidth ?? metrics.inspectorPaneWidth).clamp(
              metrics.sidePaneMinWidth,
              metrics.sidePaneMaxWidth,
            );
        final mode = resolveEffectiveWorkbenchLayoutMode(
          width: constraints.maxWidth,
          navigationAvailable: navigation != null && navigationVisible,
          inspectorAvailable: inspector != null && inspectorVisible,
          leadingRailAvailable: leadingRailBuilder != null,
          trailingRailAvailable: trailingRailBuilder != null,
          navigationWidth: resolvedNavigationWidth,
          inspectorWidth: resolvedInspectorWidth,
          metrics: metrics,
          spacing: spacing,
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

        final base = Row(
          key: const ValueKey<String>('workbench-base'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (leadingRail case final rail?) ...<Widget>[
              SizedBox(
                key: const ValueKey<String>('workbench-leading-rail'),
                width: metrics.activityRailWidth,
                child: rail,
              ),
              SizedBox(
                key: const ValueKey<String>('workbench-leading-rail-gap'),
                width: spacing.xxs,
              ),
            ],
            if (navigationInline) ...<Widget>[
              SizedBox(
                key: const ValueKey<String>('workbench-navigation-inline'),
                width: resolvedNavigationWidth,
                child: navigation,
              ),
              _PaneSeparator(
                key: const ValueKey<String>(
                  'workbench-navigation-separator',
                ),
                width: spacing.xs,
                child: navigationResizeHandle,
              ),
            ],
            Expanded(
              key: const ValueKey<String>('workbench-canvas-slot'),
              child: KeyedSubtree(
                key: const ValueKey<String>('workbench-canvas'),
                child: IdeSurface(
                  level: IdeSurfaceLevel.canvas,
                  borderRadius: context.appRadii.allLarge,
                  showBorder: true,
                  child: canvas,
                ),
              ),
            ),
            if (inspectorInline) ...<Widget>[
              _PaneSeparator(
                key: const ValueKey<String>(
                  'workbench-inspector-separator',
                ),
                width: spacing.xs,
                child: inspectorResizeHandle,
              ),
              SizedBox(
                key: const ValueKey<String>('workbench-inspector-inline'),
                width: resolvedInspectorWidth,
                child: inspector,
              ),
            ],
            if (trailingRail case final rail?) ...<Widget>[
              SizedBox(
                key: const ValueKey<String>('workbench-trailing-rail-gap'),
                width: spacing.xxs,
              ),
              SizedBox(
                key: const ValueKey<String>('workbench-trailing-rail'),
                width: metrics.activityRailWidth,
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
        if (!showNavigationOverlay && !showInspectorOverlay) return base;

        final brightness = Theme.of(context).brightness;
        final leadingInset = leadingRail == null
            ? 0.0
            : metrics.activityRailWidth + spacing.xxs;
        final trailingInset = trailingRail == null
            ? 0.0
            : spacing.xxs + metrics.activityRailWidth;
        final availableOverlayWidth =
            (constraints.maxWidth - leadingInset - trailingInset).clamp(
              0.0,
              double.infinity,
            );
        final overlayWidth =
            (showNavigationOverlay
                    ? resolvedNavigationWidth
                    : resolvedInspectorWidth)
                .clamp(0.0, availableOverlayWidth);

        void dismissOverlay() {
          onDismissOverlay?.call();
          overlayTriggerFocusNode?.requestFocus();
        }

        final overlayStack = Stack(
          key: const ValueKey<String>('workbench-overlay-stack'),
          children: <Widget>[
            base,
            Positioned.fill(
              child: Semantics(
                button: true,
                label: closeOverlaySemanticLabel,
                child: GestureDetector(
                  key: const ValueKey<String>('workbench-overlay-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: dismissOverlay,
                  child: ColoredBox(
                    color: context.appEffects.scrim(brightness),
                  ),
                ),
              ),
            ),
            if (showNavigationOverlay)
              Positioned(
                key: const ValueKey<String>(
                  'workbench-navigation-overlay',
                ),
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
                key: const ValueKey<String>('workbench-inspector-overlay'),
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
        return Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          child: _WorkbenchOverlayKeyboardScope(
            onDismiss: dismissOverlay,
            child: overlayStack,
          ),
        );
      },
    );
  }
}

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

class _PaneSeparator extends StatelessWidget {
  const _PaneSeparator({required this.width, this.child, super.key});

  final double width;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: child);
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
        borderRadius: context.appRadii.allLarge,
        boxShadow: context.appEffects.overlayShadow(brightness),
      ),
      child: child,
    );
  }
}
