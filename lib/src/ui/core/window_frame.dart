import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';

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
                    style: TextStyle(color: colors.mutedText, fontSize: 12),
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
                      child: _TitleBarActionButton(action: action),
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

class _WindowMenuButton extends StatelessWidget {
  const _WindowMenuButton({required this.menu});

  final WindowMenu menu;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return PopupMenuButton<WindowMenuItem>(
      key: menu.key,
      tooltip: '',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      onSelected: (item) => item.onPressed?.call(),
      itemBuilder: (context) {
        return [
          for (final item in menu.items)
            PopupMenuItem<WindowMenuItem>(
              key: item.key,
              value: item,
              enabled: item.onPressed != null,
              height: 32,
              child: Text(
                item.label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                ),
              ),
            ),
        ];
      },
      child: SizedBox(
        height: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Text(
              menu.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.mutedText, fontSize: 12),
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
  const _TitleBarActionButton({required this.action});

  final WindowTitleBarAction action;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final activeBackground = colors.accent.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12,
    );
    final activeForeground = colors.accentForeground;
    final foreground = action.active ? activeForeground : colors.mutedText;
    return Tooltip(
      message: action.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        selected: action.active,
        label: action.semanticLabel,
        child: Material(
          key: action.key,
          color: Colors.transparent,
          child: InkWell(
            onTap: action.onPressed,
            borderRadius: BorderRadius.circular(6),
            hoverColor: action.active ? activeBackground : colors.windowHover,
            child: Ink(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: action.active ? activeBackground : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(action.icon, size: 16, color: foreground),
            ),
          ),
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
    // 非关闭按钮悬停时，深色主题用白色高亮、浅色主题沿用深色图标，保证对比度；
    // 关闭按钮恒为红色底配白图标。
    final idleIcon = colors.windowIcon;
    final hoverIcon = widget.isClose
        ? Colors.white
        : (Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : colors.windowIcon);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 40,
            height: 32,
            alignment: Alignment.center,
            color: _hover ? hoverColor : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 14,
              color: _hover ? hoverIcon : idleIcon,
            ),
          ),
        ),
      ),
    );
  }
}
