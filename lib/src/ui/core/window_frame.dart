import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 包裹主内容的窗口外框。
///
/// 隐藏原生标题栏后由本组件提供自定义标题栏：macOS 下保留系统交通灯按钮并
/// 提供拖拽区与标题；Windows 下在最左侧显示应用 Logo；Windows/Linux 下可承载
/// Flutter 菜单，并额外绘制最小化/最大化/关闭按钮。
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
    final isWindows = Platform.isWindows;
    // 最小高度保证无菜单时仍可拖拽；有 Menubar 时由内容撑开，不再锁死固定像素。
    // Column 给非 flex 子项无限高约束，不能用 CrossAxisAlignment.stretch。
    return ColoredBox(
      color: colors.frame,
      child: ConstrainedBox(
        key: const ValueKey('window-title-bar'),
        constraints: const BoxConstraints(minHeight: IdeMetrics.titleBarHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // macOS 下左侧让出交通灯按钮的空间，且不拦截点击。
              if (isMac) const SizedBox(width: 76),
              if (isWindows) const _WindowsTitleBarLogo(),
              if (menus.isNotEmpty) _WindowMenuBar(menus: menus),
              Expanded(
                child: DragToMoveArea(
                  child: isWindows
                      ? const SizedBox(height: IdeMetrics.titleBarHeight)
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: IdeSpacing.space10,
                          ),
                          // heightFactor 避免 Row 在无限高约束下把 Align 拉爆。
                          child: Align(
                            alignment: Alignment.centerRight,
                            heightFactor: 1,
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
                    left: IdeSpacing.space4,
                    right: !isMac && showWindowControls
                        ? IdeSpacing.space2
                        : IdeSpacing.space6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final action in titleBarActions)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: IdeSpacing.space4,
                          ),
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
        ),
      ),
    );
  }
}

class _WindowsTitleBarLogo extends StatelessWidget {
  const _WindowsTitleBarLogo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('window-title-bar-logo'),
      image: true,
      label: 'Zeta Logo',
      child: Padding(
        padding: const EdgeInsets.only(
          left: IdeSpacing.space6,
          right: IdeSpacing.space4,
        ),
        child: SvgPicture.asset(
          'assets/branding/zeta_logo.svg',
          width: 20,
          height: 20,
        ),
      ),
    );
  }
}

/// Windows/Linux 标题栏菜单，委托给 [sf.Menubar] 以获得标准悬停切换与键盘导航。
class _WindowMenuBar extends StatelessWidget {
  const _WindowMenuBar({required this.menus});

  final List<WindowMenu> menus;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final theme = sf.Theme.of(context);

    // 菜单按钮由标题栏高度约束负责撑开，文字沿用 IDE 正常行高并在按钮内居中。
    final menubarTextStyle = textStyles.bodyMedium.copyWith(
      color: colors.textSecondary,
    );
    final menuItemTextStyle = textStyles.bodyMedium.copyWith(
      color: colors.textPrimary,
    );

    return Padding(
      padding: const EdgeInsets.only(left: IdeSpacing.space4),
      child: SizedBox(
        height: IdeMetrics.titleBarHeight,
        child: sf.ComponentTheme(
          data: sf.MenubarButtonTheme(
            textStyle: (context, states, value) {
              final openOrHover =
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.selected) ||
                  states.contains(WidgetState.focused);
              return menubarTextStyle.copyWith(
                color: openOrHover ? colors.textPrimary : colors.textSecondary,
              );
            },
            decoration: (context, states, value) {
              final openOrHover =
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.selected) ||
                  states.contains(WidgetState.focused);
              if (!openOrHover || states.contains(WidgetState.disabled)) {
                return const BoxDecoration();
              }
              final isDark = theme.brightness == Brightness.dark;
              return BoxDecoration(
                color: colors.border.withValues(alpha: isDark ? 0.26 : 0.38),
                borderRadius: IdeRadius.allSmall,
              );
            },
          ),
          child: sf.ComponentTheme(
            data: sf.MenuButtonTheme(
              textStyle: (context, states, value) {
                if (states.contains(WidgetState.disabled)) {
                  return menuItemTextStyle.copyWith(color: colors.textTertiary);
                }
                return menuItemTextStyle;
              },
            ),
            child: sf.Menubar(
              border: false,
              popoverOffset: const Offset(0, IdeSpacing.space8),
              children: [
                for (final menu in menus)
                  sf.MenuButton(
                    key: menu.key,
                    subMenu: [
                      for (final item in menu.items)
                        sf.MenuButton(
                          key: item.key,
                          enabled: item.onPressed != null,
                          onPressed: item.onPressed == null
                              ? null
                              : (context) => item.onPressed!.call(),
                          child: Text(item.label),
                        ),
                    ],
                    child: Text(menu.label),
                  ),
              ],
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
    final theme = sf.Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeBackground = colorScheme.primary.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12,
    );
    final hoverBackground = colorScheme.border.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.3,
    );
    // active 落在淡化 primary 底上，用 accentForeground（选中强调色）；
    // 不能用 primaryForeground/onAccent（实心 accent 上的白字）。
    final colors = IdeColors.of(context);
    final foreground = action.active
        ? colors.accentForeground
        : colorScheme.mutedForeground;
    return IdeTooltip(
      message: action.tooltip,
      child: PaneInteractiveSurface(
        onPressed: action.onPressed,
        selected: action.active,
        button: true,
        semanticLabel: action.semanticLabel,
        width: IdeMetrics.iconButtonHitSize,
        height: IdeMetrics.iconButtonHitSize,
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
    // 与标题栏 min 高度对齐（扣除上下 2px padding），Menubar 撑高时仍垂直居中。
    const buttonHeight = IdeMetrics.titleBarHeight - IdeSpacing.space4;
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
            width: 46,
            height: buttonHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? hoverColor : Colors.transparent,
              borderRadius: IdeRadius.allSmall,
            ),
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
