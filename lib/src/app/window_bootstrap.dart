import 'dart:io';

import 'package:flutter/material.dart';
import 'package:macos_window_utils/window_manipulator.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';

/// 初始化桌面窗口。
///
/// 隐藏原生标题栏（macOS 仍保留交通灯按钮）、设定初始尺寸与最小尺寸后显示窗口。
/// 需要在 `runApp` 之前调用 [windowManager.ensureInitialized]。
Future<void> bootstrapDesktopWindow() async {
  // 启动时尚未读取持久化的主题偏好，默认跟随系统：用系统亮度决定窗口初始
  // 背景色，避免浅色系统下出现深色闪烁。
  final systemBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  final frameColor = systemBrightness == Brightness.dark
      ? IdeColors.dark.frame
      : IdeColors.light.frame;
  final options = WindowOptions(
    size: const Size(1280, 800),
    minimumSize: const Size(900, 560),
    center: true,
    title: appTitle,
    // 隐藏原生标题栏：macOS 下交通灯按钮仍保留，内容会延伸到窗口顶部。
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: frameColor,
  );

  if (Platform.isMacOS) {
    await WindowManipulator.initialize(enableWindowDelegate: true);
  }

  await windowManager.waitUntilReadyToShow(options, () async {
    if (Platform.isMacOS) {
      // 保留全尺寸内容区与隐藏原生标题，由 Flutter 自绘不透明标题栏；
      // 不再启用透明背景与 NSVisualEffectView 毛玻璃。
      await WindowManipulator.enableFullSizeContentView();
      await WindowManipulator.hideTitle();
      await WindowManipulator.makeTitlebarTransparent();
    }
    await windowManager.show();
    await windowManager.focus();
  });
}
