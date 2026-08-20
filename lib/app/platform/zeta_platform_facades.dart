import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/app/platform/desktop_attention_adapter.dart';
import 'package:zeta/app/platform/desktop_notification_adapter.dart';
import 'package:zeta/app/platform/file_selector_adapter.dart';
import 'package:zeta/app/platform/flutter_file_selector_facade.dart';
import 'package:zeta/app/platform/flutter_local_notifications_facade.dart';
import 'package:zeta/app/platform/flutter_pasteboard_facade.dart';
import 'package:zeta/app/platform/flutter_window_manager_facade.dart';
import 'package:zeta/app/platform/io_system_file_manager_facade.dart';
import 'package:zeta/app/platform/macos_window_facade.dart';
import 'package:zeta/app/platform/menu_command_adapter.dart';
import 'package:zeta/app/platform/method_channel_facade.dart';
import 'package:zeta/app/platform/pasteboard_clipboard_adapter.dart';
import 'package:zeta/app/platform/system_file_manager_adapter.dart';
import 'package:zeta/app/platform/system_font_catalog_adapter.dart';
import 'package:zeta/app/platform/window_command_adapter.dart';

/// Every plugin and channel seam the composition root needs.
///
/// Grouping them keeps plugin construction inside the platform adapter
/// boundary and gives the composition root a single injection point.
final class ZetaPlatformFacades {
  /// Creates a facade bundle from already constructed seams.
  const ZetaPlatformFacades({
    required this.fileSelector,
    required this.pasteboard,
    required this.fileManager,
    required this.windowManager,
    required this.macOsWindow,
    required this.notifications,
    required this.menuChannel,
    required this.fontChannel,
    required this.attentionChannel,
  });

  /// Creates the production bundle backed by real plugins and channels.
  factory ZetaPlatformFacades.production({
    required String linuxNotificationActionName,
  }) {
    return ZetaPlatformFacades(
      fileSelector: FlutterFileSelectorFacade(),
      pasteboard: FlutterPasteboardFacade(),
      fileManager: IoSystemFileManagerFacade(),
      windowManager: FlutterWindowManagerFacade(WindowManager.instance),
      macOsWindow: MacOsWindowManipulatorFacade(enabled: Platform.isMacOS),
      notifications: FlutterLocalNotificationsFacade(
        FlutterLocalNotificationsPlugin(),
        linuxActionName: linuxNotificationActionName,
      ),
      menuChannel: _channel(MethodChannelMenuCommandAdapter.channelName),
      fontChannel: _channel(
        MethodChannelSystemFontCatalogAdapter.channelName,
      ),
      attentionChannel: _channel(
        MethodChannelDesktopAttentionAdapter.channelName,
      ),
    );
  }

  static PlatformMethodChannelFacade _channel(String name) =>
      FlutterMethodChannelFacade(MethodChannel(name));

  /// Native open/save dialog seam.
  final FileSelectorFacade fileSelector;

  /// System clipboard seam.
  final PasteboardFacade pasteboard;

  /// Native file-manager reveal seam.
  final SystemFileManagerFacade fileManager;

  /// Desktop window plugin seam.
  final WindowManagerFacade windowManager;

  /// macOS title-bar seam.
  final MacOsWindowFacade macOsWindow;

  /// Desktop notification plugin seam.
  final DesktopNotificationPluginFacade notifications;

  /// `zeta/menu` channel seam.
  final PlatformMethodChannelFacade menuChannel;

  /// `zeta/system_fonts` channel seam.
  final PlatformMethodChannelFacade fontChannel;

  /// `zeta/desktop_attention` channel seam.
  final PlatformMethodChannelFacade attentionChannel;
}
