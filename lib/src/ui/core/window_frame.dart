import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/ui/core/app_theme.dart';

/// 包裹主内容的窗口外框。
///
/// 隐藏原生标题栏后由本组件提供自定义标题栏：macOS 下保留系统交通灯按钮并
/// 提供拖拽区与标题；Windows/Linux 下额外绘制最小化/最大化/关闭按钮。
class WindowFrame extends StatelessWidget {
  const WindowFrame({
    required this.child,
    required this.enableNativeWindowFrame,
    super.key,
  });

  final Widget child;
  final bool enableNativeWindowFrame;

  @override
  Widget build(BuildContext context) {
    final showCustomTitleBar = enableNativeWindowFrame;
    final content = Column(
      children: [
        if (showCustomTitleBar) const _TitleBar(),
        Expanded(child: child),
      ],
    );

    if (!showCustomTitleBar) {
      return ColoredBox(color: ideFrameColor, child: content);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ideFrameColor,
        // macOS 下交通灯与圆角由系统负责；其他平台补一条细边框。
        border: Platform.isMacOS
            ? null
            : Border.all(color: ideBorderColor, width: 1),
      ),
      child: content,
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    return Container(
      height: 28,
      color: ideFrameColor,
      child: Row(
        children: [
          // macOS 下左侧让出交通灯按钮的空间，且不拦截点击。
          if (isMac) const SizedBox(width: 76),
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
                    style: const TextStyle(
                      color: ideMutedTextColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!isMac) const _WindowButtons(),
        ],
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
    final hoverColor = widget.isClose
        ? const Color(0xFFD84E4E)
        : const Color(0xFF303030);
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
              color: _hover ? Colors.white : const Color(0xFFB8B8B8),
            ),
          ),
        ),
      ),
    );
  }
}
