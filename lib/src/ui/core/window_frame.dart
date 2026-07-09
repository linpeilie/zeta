import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_context_menu.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_popover.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 包裹主内容的窗口外框。
///
/// 隐藏原生标题栏后由本组件提供自定义标题栏：macOS 下保留系统交通灯按钮并
/// 提供拖拽区与标题；Windows/Linux 下可承载 Flutter 菜单，并额外绘制最小化/
/// 最大化/关闭按钮。
@immutable
class WindowMenu {
  const WindowMenu({required this.label, required this.items, this.key});

  final String label;
  final List<WindowMenuItem> items;
  final Key? key;
}

@immutable
class WindowMenuItem {
  const WindowMenuItem({required this.label, this.onPressed, this.key});

  final String label;
  final VoidCallback? onPressed;
  final Key? key;
}

@immutable
class WindowTitleBarAction {
  const WindowTitleBarAction({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
    this.key,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onPressed;
  final Key? key;
  final bool active;
}

class WindowFrame extends StatelessWidget {
  const WindowFrame({
    required this.child,
    required this.enableNativeWindowFrame,
    this.menus = const <WindowMenu>[],
    this.titleBarActions = const <WindowTitleBarAction>[],
    this.showWindowControls = true,
    super.key,
  });

  final Widget child;
  final bool enableNativeWindowFrame;

  /// 标题栏顶部菜单；菜单内容由上层 feature 决定。
  final List<WindowMenu> menus;

  /// 标题栏右侧动作按钮；由上层 feature 注入具体行为。
  final List<WindowTitleBarAction> titleBarActions;

  /// 测试可关闭右侧窗口按钮，避免依赖 `window_manager` 平台通道。
  final bool showWindowControls;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final showCustomTitleBar = enableNativeWindowFrame;
    final content = Column(
      children: [
        if (showCustomTitleBar)
          _TitleBar(
            menus: menus,
            titleBarActions: titleBarActions,
            showWindowControls: showWindowControls,
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
        // macOS 下交通灯与圆角由系统负责；其他平台补一条细边框。
        border: Platform.isMacOS
            ? null
            : Border.all(color: colors.border, width: 1),
      ),
      child: content,
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.menus,
    required this.titleBarActions,
    required this.showWindowControls,
  });

  final List<WindowMenu> menus;
  final List<WindowTitleBarAction> titleBarActions;
  final bool showWindowControls;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final isMac = Platform.isMacOS;
    return Container(
      height: 28,
      color: colors.frame,
      child: Row(
        children: [
          // macOS 下左侧让出交通灯按钮的空间，且不拦截点击。
          if (isMac) const SizedBox(width: 76),
          if (menus.isNotEmpty) _WindowMenuBar(menus: menus),
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.bodyMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (titleBarActions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: 4,
                right: !isMac && showWindowControls ? 2 : 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in titleBarActions)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _TitleBarActionButton(
                        key: action.key,
                        action: action,
                      ),
                    ),
                ],
              ),
            ),
          if (!isMac && showWindowControls) const _WindowButtons(),
        ],
      ),
    );
  }
}

class _WindowMenuBar extends StatelessWidget {
  const _WindowMenuBar({required this.menus});

  final List<WindowMenu> menus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final menu in menus) _WindowMenuButton(menu: menu)],
      ),
    );
  }
}

class _WindowMenuButton extends StatefulWidget {
  const _WindowMenuButton({required this.menu});

  final WindowMenu menu;

  @override
  State<_WindowMenuButton> createState() => _WindowMenuButtonState();
}

class _WindowMenuButtonState extends State<_WindowMenuButton> {
  IdePopoverHandle<void>? _popoverEntry;
  bool _menuOpen = false;

  @override
  void dispose() {
    _popoverEntry?.dismiss();
    _popoverEntry = null;
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuOpen) {
      _dismissMenu();
      return;
    }
    _showMenu();
  }

  void _showMenu() {
    if (_popoverEntry != null) {
      return;
    }
    setState(() {
      _menuOpen = true;
    });
    final entry = showIdePopover<void>(
      context: context,
      alignment: Alignment.topLeft,
      anchorAlignment: Alignment.bottomLeft,
      offset: const Offset(0, 4),
      modal: false,
      builder: (context) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160),
          child: IdeContextMenu(
            actions: [
              for (final item in widget.menu.items)
                IdeContextMenuAction(
                  key: item.key,
                  label: item.label,
                  enabled: item.onPressed != null,
                  onPressed: item.onPressed ?? () {},
                ),
            ],
          ),
        );
      },
    );
    _popoverEntry = entry;
    entry.future.whenComplete(() {
      if (!mounted) {
        return;
      }
      setState(() {
        if (identical(_popoverEntry, entry)) {
          _popoverEntry = null;
        }
        _menuOpen = false;
      });
    });
  }

  void _dismissMenu() {
    final entry = _popoverEntry;
    if (entry == null) {
      return;
    }
    _popoverEntry = null;
    setState(() {
      _menuOpen = false;
    });
    entry.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final theme = sf.Theme.of(context);
    final hoverBackground = colors.border.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.3,
    );
    final selectedBackground = colors.border.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.26 : 0.38,
    );
    return PaneInteractiveSurface(
      key: widget.menu.key,
      onPressed: _toggleMenu,
      selected: _menuOpen,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      borderRadius: IdeRadius.allSmall,
      hoverBackgroundColor: hoverBackground,
      selectedBackgroundColor: selectedBackground,
      child: Center(
        child: Text(
          widget.menu.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyles.bodyMedium.copyWith(
            color: _menuOpen ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _WindowButtons extends StatefulWidget {
  const _WindowButtons();

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_refreshMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _refreshMaximized() async {
    _maximized = await windowManager.isMaximized();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(
          icon: Icons.minimize_rounded,
          tooltip: 'Minimize',
          onPressed: () => windowManager.minimize(),
        ),
        _WindowButton(
          icon: _maximized ? Icons.restore_rounded : Icons.crop_square_rounded,
          tooltip: _maximized ? 'Restore' : 'Maximize',
          onPressed: () async {
            if (_maximized) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WindowButton(
          icon: Icons.close_rounded,
          tooltip: 'Close',
          isClose: true,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _TitleBarActionButton extends StatelessWidget {
  const _TitleBarActionButton({required this.action, super.key});

  final WindowTitleBarAction action;

  @override
  Widget build(BuildContext context) {
    final theme = sf.Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeBackground = colorScheme.primary.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12,
    );
    final hoverBackground = colorScheme.border.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.3,
    );
    final foreground = action.active
        ? colorScheme.primaryForeground
        : colorScheme.mutedForeground;
    return IdeTooltip(
      message: action.tooltip,
      child: PaneInteractiveSurface(
        onPressed: action.onPressed,
        selected: action.active,
        button: true,
        semanticLabel: action.semanticLabel,
        width: 28,
        height: 28,
        padding: EdgeInsets.zero,
        borderRadius: IdeRadius.allSmall,
        hoverBackgroundColor: action.active
            ? activeBackground
            : hoverBackground,
        pressedBackgroundColor: action.active
            ? activeBackground
            : hoverBackground,
        selectedBackgroundColor: activeBackground,
        child: Icon(action.icon, size: 16, color: foreground),
      ),
    );
  }
}

/// 自绘的最小化/最大化/关闭按钮（Windows/Linux 使用）。
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final hoverColor = widget.isClose ? colors.closeHover : colors.windowHover;
    final idleIcon = colors.windowIcon;
    final hoverIcon = widget.isClose ? Colors.white : colors.textPrimary;
    return IdeTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: IdeMotion.durationFast,
            curve: IdeMotion.curveDefault,
            width: 38,
            height: 24,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _hover ? hoverColor : Colors.transparent,
              borderRadius: IdeRadius.allSmall,
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: _hover ? hoverIcon : idleIcon,
            ),
          ),
        ),
      ),
    );
  }
}
