import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';

import 'package:zeta_ui/src/ide_colors.dart';
import 'package:zeta_ui/src/ide_effects.dart';
import 'package:zeta_ui/src/ide_metrics.dart';
import 'package:zeta_ui/src/ide_motion.dart';
import 'package:zeta_ui/src/ide_spacing.dart';
import 'package:zeta_ui/src/ide_text_styles.dart';
import 'package:zeta_ui/src/pane_widgets.dart';
import 'zeta_ui_text_catalog.dart';

/// 包裹主内容的窗口外框。
///
/// 隐藏原生标题栏后由本组件提供自定义标题栏：macOS 下保留系统交通灯按钮并
/// 提供拖拽区与标题；Windows 下在最左侧显示应用 Logo；全平台可承载 Flutter
/// 菜单；Windows/Linux 额外绘制最小化/最大化/关闭按钮。
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
    this.focusNode,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onPressed;
  final Key? key;
  final FocusNode? focusNode;
  final bool active;

  /// 为 false 时按钮仍渲染，但不响应点击。
  final bool enabled;
}

class WindowFrame extends StatelessWidget {
  const WindowFrame({
    required this.child,
    required this.enableNativeWindowFrame,
    this.menus = const <WindowMenu>[],
    this.titleBarLeadingActions = const <WindowTitleBarAction>[],
    this.titleBarActions = const <WindowTitleBarAction>[],
    this.showWindowControls = true,
    this.brandLogo,
    super.key,
  });

  final Widget child;
  final bool enableNativeWindowFrame;

  /// Windows 标题栏最左侧的品牌 Logo。
  ///
  /// **品牌属于产品，不属于设计系统**：`zeta_ui` 不声明也不读取任何品牌资产，
  /// 由宿主传入现成 Widget（例如 `SvgPicture.asset`）。为空时该位置留空，
  /// 标题栏其余布局不变。
  final Widget? brandLogo;

  /// 标题栏顶部菜单；菜单内容由上层 feature 决定。
  final List<WindowMenu> menus;

  /// 标题栏左侧动作按钮；位于 macOS 交通灯 gutter 之后、Windows 品牌 Logo
  /// 之后，其余平台最左侧。
  final List<WindowTitleBarAction> titleBarLeadingActions;

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
            titleBarLeadingActions: titleBarLeadingActions,
            titleBarActions: titleBarActions,
            showWindowControls: showWindowControls,
            brandLogo: brandLogo,
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
        border: defaultTargetPlatform == TargetPlatform.macOS
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
    required this.titleBarLeadingActions,
    required this.titleBarActions,
    required this.showWindowControls,
    required this.brandLogo,
  });

  final List<WindowMenu> menus;
  final List<WindowTitleBarAction> titleBarLeadingActions;
  final List<WindowTitleBarAction> titleBarActions;
  final bool showWindowControls;
  final Widget? brandLogo;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final platform = defaultTargetPlatform;
    final isMac = platform == TargetPlatform.macOS;
    final isWindows = platform == TargetPlatform.windows;
    // 最小高度保证无菜单时仍可拖拽；有 Menubar 时由内容撑开，不再锁死固定像素。
    // Column 给非 flex 子项无限高约束，不能用 CrossAxisAlignment.stretch。
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.frame),
      child: ConstrainedBox(
        key: const ValueKey('window-title-bar'),
        constraints: const BoxConstraints(minHeight: IdeMetrics.titleBarHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // macOS 下左侧让出交通灯按钮的空间，且不拦截点击。
              if (isMac)
                const SizedBox(width: IdeMetrics.macOSTrafficLightGutter),
              // Windows 下 Logo 固定在最左侧，折叠等 leading action 紧随其后。
              if (isWindows && brandLogo != null)
                _WindowsTitleBarLogo(logo: brandLogo!),
              if (titleBarLeadingActions.isNotEmpty)
                _TitleBarActionGroup(
                  actions: titleBarLeadingActions,
                  trailing: false,
                  showWindowControls: showWindowControls,
                  isMac: isMac,
                ),
              if (menus.isNotEmpty) _WindowMenuBar(menus: menus),
              Expanded(
                child: DragToMoveArea(
                  child: isWindows
                      ? const SizedBox(height: IdeMetrics.titleBarHeight)
                      : const SizedBox(
                          // 外层上下各有 space2，这里填满标题栏的内容高度，
                          // 否则自绘标题栏的 DragToMoveArea 会因无 child 而变成零高度。
                          height: IdeMetrics.titleBarHeight - IdeSpacing.space4,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: IdeSpacing.space10,
                            ),
                          ),
                        ),
                ),
              ),
              if (titleBarActions.isNotEmpty)
                _TitleBarActionGroup(
                  actions: titleBarActions,
                  trailing: true,
                  showWindowControls: showWindowControls,
                  isMac: isMac,
                ),
              if (!isMac && showWindowControls) const _WindowButtons(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBarActionGroup extends StatelessWidget {
  const _TitleBarActionGroup({
    required this.actions,
    required this.trailing,
    required this.showWindowControls,
    required this.isMac,
  });

  final List<WindowTitleBarAction> actions;
  final bool trailing;
  final bool showWindowControls;
  final bool isMac;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: trailing ? IdeSpacing.space4 : 0,
        right: trailing
            ? (!isMac && showWindowControls
                  ? IdeSpacing.space2
                  : IdeSpacing.space6)
            : IdeSpacing.space2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(left: IdeSpacing.space4),
              child: _TitleBarActionButton(key: action.key, action: action),
            ),
        ],
      ),
    );
  }
}

/// Windows 标题栏品牌 Logo。
///
/// 布局契约：左侧外边距 [IdeSpacing.space8]、右侧 [IdeSpacing.space4]，
/// 图标 22×22，与下方 Workbench 左侧 rail 视觉对齐。
class _WindowsTitleBarLogo extends StatelessWidget {
  const _WindowsTitleBarLogo({required this.logo});

  /// 宿主注入的品牌图形；设计系统只负责尺寸盒、边距与无障碍标签。
  final Widget logo;

  static const double logoSize = 22;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('window-title-bar-logo'),
      image: true,
      label: IdeUiText.of(context).workbenchLogoSemantics,
      child: Padding(
        padding: const EdgeInsets.only(
          left: IdeSpacing.space8,
          right: IdeSpacing.space4,
        ),
        child: SizedBox(width: logoSize, height: logoSize, child: logo),
      ),
    );
  }
}

/// 全平台标题栏菜单，委托给 [sf.Menubar] 以获得标准悬停切换与键盘导航。
class _WindowMenuBar extends StatelessWidget {
  const _WindowMenuBar({required this.menus});

  final List<WindowMenu> menus;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final theme = sf.Theme.of(context);

    // 顶层只剩这一个纯 icon 触发按钮：不再用标题栏高度撑开，改为按
    // padding + icon 自然定形，交给 _TitleBar 外层 Row 的
    // CrossAxisAlignment.center 居中——和折叠 icon（_TitleBarActionButton）
    // 走同一套布局逻辑，命中区才能对齐成同样的正方形。
    final menubarTextStyle = textStyles.bodyMedium.copyWith(
      color: colors.textSecondary,
    );
    final menuItemTextStyle = textStyles.bodyMedium.copyWith(
      color: colors.textPrimary,
    );

    return Padding(
      padding: const EdgeInsets.only(left: IdeSpacing.space4),
      child: sf.ComponentTheme(
        data: sf.MenubarButtonTheme(
          // shadcn 默认 menubar 按钮 padding 按文字标签设计（约 40×40 命中区），
          // 收紧到与其它标题栏 icon 按钮一致的 IdeMetrics.iconButtonHitSize
          // （28×28 = 16px 图标 + 上下左右各 IdeSpacing.space6）。
          padding: (context, states, value) =>
              const EdgeInsets.all(IdeSpacing.space6),
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
            popoverOffset: const Offset(0, IdeSpacing.space4),
            children: [
              sf.MenuButton(
                key: const ValueKey('window-menu-trigger'),
                subMenu: [
                  for (var index = 0; index < menus.length; index += 1) ...[
                    if (index > 0) const sf.MenuDivider(),
                    for (final item in menus[index].items)
                      sf.MenuButton(
                        key: item.key,
                        enabled: item.onPressed != null,
                        onPressed: item.onPressed == null
                            ? null
                            : (context) => item.onPressed!.call(),
                        child: Text(item.label),
                      ),
                  ],
                ],
                child: Semantics(
                  button: true,
                  label: IdeUiText.of(context).commonMenu,
                  child: Icon(
                    sf.LucideIcons.menu,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
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
    final text = IdeUiText.of(context);
    return Row(
      children: [
        _WindowButton(
          icon: sf.LucideIcons.minus,
          tooltip: text.windowMinimize,
          onPressed: () => windowManager.minimize(),
        ),
        _WindowButton(
          // 未最大化：maximize；已最大化：minimize（还原）
          icon: _maximized ? sf.LucideIcons.minimize : sf.LucideIcons.maximize,
          tooltip: _maximized ? text.windowRestore : text.windowMaximize,
          onPressed: () async {
            if (_maximized) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WindowButton(
          icon: sf.LucideIcons.x,
          tooltip: text.windowClose,
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
    final foreground = !action.enabled
        ? colors.textTertiary
        : action.active
        ? colors.accentForeground
        : colorScheme.mutedForeground;
    return IdeTooltip(
      message: action.tooltip,
      child: PaneInteractiveSurface(
        focusNode: action.focusNode,
        onPressed: action.onPressed,
        enabled: action.enabled,
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
      child: Semantics(
        button: true,
        label: widget.tooltip,
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
      ),
    );
  }
}
