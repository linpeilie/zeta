import 'package:app_ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Visual desktop platform used by [WindowFrame].
enum WindowFramePlatform {
  /// macOS traffic-light layout.
  macOS,

  /// Windows logo and caption-control layout.
  windows,

  /// Linux caption-control layout.
  linux,

  /// Neutral custom-title-bar layout.
  other,
}

/// Wraps the title-bar drag surface in an app-owned platform adapter.
typedef WindowDragRegionBuilder = Widget Function(
  BuildContext context,
  Widget child,
);

/// Immutable group of title-bar menu items.
@immutable
class WindowMenu {
  /// Creates a menu group.
  const WindowMenu({required this.label, required this.items, this.key});

  /// Caller-supplied group label.
  final String label;

  /// Menu items.
  final List<WindowMenuItem> items;

  /// Stable group key.
  final Key? key;
}

/// Immutable title-bar menu item.
@immutable
class WindowMenuItem {
  /// Creates a menu item; null [onPressed] disables it.
  const WindowMenuItem({required this.label, this.onPressed, this.key});

  /// Visible item copy.
  final String label;

  /// Activation callback.
  final VoidCallback? onPressed;

  /// Stable item key.
  final Key? key;
}

/// Immutable application action rendered in the title bar.
@immutable
class WindowTitleBarAction {
  /// Creates a title-bar action.
  const WindowTitleBarAction({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
    this.key,
    this.focusNode,
    this.active = false,
    this.enabled = true,
  });

  /// Action glyph.
  final IconData icon;

  /// Hover tooltip copy.
  final String tooltip;

  /// Accessible action name.
  final String semanticLabel;

  /// Activation callback.
  final VoidCallback onPressed;

  /// Stable key.
  final Key? key;

  /// Optional externally owned focus node.
  final FocusNode? focusNode;

  /// Whether the action is selected.
  final bool active;

  /// Whether activation is enabled.
  final bool enabled;
}

/// App-owned state, copy, and callbacks for native window operations.
@immutable
class WindowControlSet {
  /// Creates a window-control set.
  const WindowControlSet({
    required this.minimizeLabel,
    required this.maximizeLabel,
    required this.restoreLabel,
    required this.closeLabel,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
    this.maximized = false,
  });

  /// Accessible/tooltip copy for minimize.
  final String minimizeLabel;

  /// Accessible/tooltip copy for maximize.
  final String maximizeLabel;

  /// Accessible/tooltip copy for restore.
  final String restoreLabel;

  /// Accessible/tooltip copy for close.
  final String closeLabel;

  /// App adapter callback for minimizing the window.
  final VoidCallback onMinimize;

  /// App adapter callback for maximizing or restoring the window.
  final VoidCallback onToggleMaximize;

  /// App adapter callback for closing the window.
  final VoidCallback onClose;

  /// Current maximized state supplied by the app adapter.
  final bool maximized;
}

/// A pure-UI custom desktop window frame.
class WindowFrame extends StatelessWidget {
  /// Creates a window frame whose platform effects are supplied by the app.
  const WindowFrame({
    required this.child,
    this.showCustomTitleBar = false,
    this.platform,
    this.menus = const <WindowMenu>[],
    this.menuSemanticLabel,
    this.titleBarLeadingActions = const <WindowTitleBarAction>[],
    this.titleBarActions = const <WindowTitleBarAction>[],
    this.windowControls,
    this.windowsLogo,
    this.windowsLogoSemanticLabel,
    this.dragRegionBuilder,
    super.key,
  }) : assert(
         windowsLogo == null || windowsLogoSemanticLabel != null,
         'A Windows logo requires windowsLogoSemanticLabel.',
       );

  /// Main application content.
  final Widget child;

  /// Whether to render the custom title bar.
  final bool showCustomTitleBar;

  /// Optional deterministic platform override.
  final WindowFramePlatform? platform;

  /// Title-bar menu groups.
  final List<WindowMenu> menus;

  /// Accessible name for the menu trigger.
  final String? menuSemanticLabel;

  /// Actions before the drag region.
  final List<WindowTitleBarAction> titleBarLeadingActions;

  /// Actions after the drag region.
  final List<WindowTitleBarAction> titleBarActions;

  /// App-owned native window state and callbacks.
  final WindowControlSet? windowControls;

  /// App-owned Windows brand widget.
  final Widget? windowsLogo;

  /// Accessible name for [windowsLogo].
  final String? windowsLogoSemanticLabel;

  /// App-owned wrapper such as `DragToMoveArea`.
  final WindowDragRegionBuilder? dragRegionBuilder;

  @override
  Widget build(BuildContext context) {
    if (menus.isNotEmpty && menuSemanticLabel == null) {
      throw FlutterError('WindowFrame menus require menuSemanticLabel.');
    }
    final colors = context.appColors;
    final resolvedPlatform =
        platform ?? _platformFromTarget(defaultTargetPlatform);
    final content = Column(
      children: <Widget>[
        if (showCustomTitleBar)
          _TitleBar(
            platform: resolvedPlatform,
            menus: menus,
            menuSemanticLabel: menuSemanticLabel,
            titleBarLeadingActions: titleBarLeadingActions,
            titleBarActions: titleBarActions,
            windowControls: windowControls,
            windowsLogo: windowsLogo,
            windowsLogoSemanticLabel: windowsLogoSemanticLabel,
            dragRegionBuilder: dragRegionBuilder,
          ),
        Expanded(child: child),
      ],
    );
    if (!showCustomTitleBar) {
      return ColoredBox(color: colors.frame, child: content);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.frame,
        border: resolvedPlatform == WindowFramePlatform.macOS
            ? null
            : Border.all(color: colors.border),
      ),
      child: content,
    );
  }
}

WindowFramePlatform _platformFromTarget(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.macOS => WindowFramePlatform.macOS,
    TargetPlatform.windows => WindowFramePlatform.windows,
    TargetPlatform.linux => WindowFramePlatform.linux,
    _ => WindowFramePlatform.other,
  };
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.platform,
    required this.menus,
    required this.menuSemanticLabel,
    required this.titleBarLeadingActions,
    required this.titleBarActions,
    required this.windowControls,
    required this.windowsLogo,
    required this.windowsLogoSemanticLabel,
    required this.dragRegionBuilder,
  });

  final WindowFramePlatform platform;
  final List<WindowMenu> menus;
  final String? menuSemanticLabel;
  final List<WindowTitleBarAction> titleBarLeadingActions;
  final List<WindowTitleBarAction> titleBarActions;
  final WindowControlSet? windowControls;
  final Widget? windowsLogo;
  final String? windowsLogoSemanticLabel;
  final WindowDragRegionBuilder? dragRegionBuilder;

  @override
  Widget build(BuildContext context) {
    final isMac = platform == WindowFramePlatform.macOS;
    final isWindows = platform == WindowFramePlatform.windows;
    final metrics = context.appMetrics;
    final spacing = context.appSpacing;
    final dragChild = SizedBox(
      height: metrics.titleBarHeight - spacing.xxs,
    );
    return ColoredBox(
      color: context.appColors.frame,
      child: ConstrainedBox(
        key: const ValueKey<String>('window-title-bar'),
        constraints: BoxConstraints(minHeight: metrics.titleBarHeight),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: spacing.xxxs),
          child: Row(
            children: <Widget>[
              if (isMac) SizedBox(width: metrics.macOSTrafficLightGutter),
              if (isWindows && windowsLogo != null)
                Semantics(
                  image: true,
                  label: windowsLogoSemanticLabel,
                  excludeSemantics: true,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: spacing.xs,
                      right: spacing.xxs,
                    ),
                    child: windowsLogo,
                  ),
                ),
              if (titleBarLeadingActions.isNotEmpty)
                _TitleBarActionGroup(actions: titleBarLeadingActions),
              if (menus.isNotEmpty)
                _WindowMenuButton(
                  menus: menus,
                  semanticLabel: menuSemanticLabel!,
                ),
              Expanded(
                child: dragRegionBuilder?.call(context, dragChild) ?? dragChild,
              ),
              if (titleBarActions.isNotEmpty)
                _TitleBarActionGroup(actions: titleBarActions),
              if (!isMac && windowControls != null)
                _WindowButtons(controls: windowControls!),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBarActionGroup extends StatelessWidget {
  const _TitleBarActionGroup({required this.actions});

  final List<WindowTitleBarAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final action in actions)
          Padding(
            padding: EdgeInsets.only(left: context.appSpacing.xxs),
            child: IdeTooltip(
              message: action.tooltip,
              child: PaneInteractiveSurface(
                key: action.key,
                focusNode: action.focusNode,
                onPressed: action.enabled ? action.onPressed : null,
                enabled: action.enabled,
                selected: action.active,
                semanticLabel: action.semanticLabel,
                width: context.appMetrics.iconButtonHitSize,
                height: context.appMetrics.iconButtonHitSize,
                padding: EdgeInsets.zero,
                child: Icon(
                  action.icon,
                  size: 16,
                  color: !action.enabled
                      ? context.appColors.textTertiary
                      : action.active
                      ? context.appColors.accentForeground
                      : context.appColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WindowMenuButton extends StatelessWidget {
  const _WindowMenuButton({
    required this.menus,
    required this.semanticLabel,
  });

  final List<WindowMenu> menus;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: context.appSpacing.xxs),
      child: IdeTooltip(
        message: semanticLabel,
        child: IdeIconButton(
          key: menus.first.key,
          icon: sf.LucideIcons.menu,
          semanticLabel: semanticLabel,
          variant: IdeButtonVariant.ghost,
          onPressed: () => showIdePopover<void>(
            context: context,
            alignment: Alignment.bottomLeft,
            anchorAlignment: Alignment.topLeft,
            offset: Offset(0, context.appSpacing.xxs),
            builder: (_) => IdeContextMenu(
              actions: <IdeContextMenuAction>[
                for (var menuIndex = 0; menuIndex < menus.length; menuIndex++)
                  for (
                    var itemIndex = 0;
                    itemIndex < menus[menuIndex].items.length;
                    itemIndex++
                  )
                    IdeContextMenuAction(
                      key: menus[menuIndex].items[itemIndex].key,
                      label: menus[menuIndex].items[itemIndex].label,
                      enabled:
                          menus[menuIndex].items[itemIndex].onPressed != null,
                      dividerAbove: menuIndex > 0 && itemIndex == 0,
                      onPressed:
                          menus[menuIndex].items[itemIndex].onPressed ?? () {},
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowButtons extends StatelessWidget {
  const _WindowButtons({required this.controls});

  final WindowControlSet controls;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _WindowButton(
          icon: sf.LucideIcons.minus,
          label: controls.minimizeLabel,
          onPressed: controls.onMinimize,
        ),
        _WindowButton(
          icon: controls.maximized
              ? sf.LucideIcons.minimize
              : sf.LucideIcons.maximize,
          label: controls.maximized
              ? controls.restoreLabel
              : controls.maximizeLabel,
          onPressed: controls.onToggleMaximize,
        ),
        _WindowButton(
          icon: sf.LucideIcons.x,
          label: controls.closeLabel,
          onPressed: controls.onClose,
          destructive: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IdeTooltip(
      message: label,
      child: PaneInteractiveSurface(
        onPressed: onPressed,
        semanticLabel: label,
        width: 46,
        height: context.appMetrics.iconButtonHitSize,
        padding: EdgeInsets.zero,
        hoverBackgroundColor: destructive
            ? colors.closeHover
            : colors.windowHover,
        pressedBackgroundColor: destructive
            ? colors.closeHover
            : colors.pressedSurface,
        child: Icon(icon, size: 14, color: colors.windowIcon),
      ),
    );
  }
}
