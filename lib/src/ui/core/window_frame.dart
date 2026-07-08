import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
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
  late final ShadPopoverController _popoverController;

  @override
  void initState() {
    super.initState();
    _popoverController = ShadPopoverController();
  }

  @override
  void dispose() {
    _popoverController.dispose();
    super.dispose();
  }

  void _handleMenuItemPressed(WindowMenuItem item) {
    _popoverController.hide();
    item.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return ShadPopover(
      key: widget.menu.key,
      controller: _popoverController,
      padding: const EdgeInsets.all(4),
      anchor: const ShadAnchorAuto(
        offset: Offset(0, 4),
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        fallback: ShadAnchorAuto(
          offset: Offset(0, -4),
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
        ),
      ),
      popover: (context) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in widget.menu.items)
                ShadButton.ghost(
                  key: item.key,
                  onPressed: item.onPressed == null
                      ? null
                      : () => _handleMenuItemPressed(item),
                  width: double.infinity,
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  mainAxisAlignment: MainAxisAlignment.start,
                  child: Text(
                    item.label,
                    style: textStyles.bodyMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      child: SizedBox(
        height: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Text(
              widget.menu.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
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
    final shadTheme = ShadTheme.of(context);
    final colorScheme = shadTheme.colorScheme;
    final activeBackground = colorScheme.primary.withValues(
      alpha: shadTheme.brightness == Brightness.dark ? 0.22 : 0.12,
    );
    final hoverBackground = colorScheme.border.withValues(
      alpha: shadTheme.brightness == Brightness.dark ? 0.18 : 0.3,
    );
    final foreground = action.active
        ? colorScheme.primaryForeground
        : colorScheme.mutedForeground;
    return IdeTooltip(
      message: action.tooltip,
      child: Semantics(
        button: true,
        selected: action.active,
        label: action.semanticLabel,
        child: ShadIconButton.ghost(
          onPressed: action.onPressed,
          width: 28,
          height: 28,
          padding: EdgeInsets.zero,
          backgroundColor: action.active
              ? activeBackground
              : Colors.transparent,
          hoverBackgroundColor: action.active
              ? activeBackground
              : hoverBackground,
          foregroundColor: foreground,
          icon: Icon(action.icon, size: 16),
        ),
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
