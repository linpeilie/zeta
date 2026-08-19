import 'dart:async';

import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:flutter/services.dart';

import 'package:zeta/app/platform/method_channel_facade.dart';

/// Method-channel implementation of [MenuCommandApi].
final class MethodChannelMenuCommandAdapter implements MenuCommandApi {
  /// Creates an adapter with an injected channel facade.
  MethodChannelMenuCommandAdapter(this._channel) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Native channel name.
  static const channelName = 'zeta/menu';

  /// Current Flutter-to-native configuration schema.
  static const schemaVersion = 1;

  final PlatformMethodChannelFacade _channel;
  final StreamController<MenuCommand> _commands =
      StreamController<MenuCommand>.broadcast();

  @override
  Stream<MenuCommand> get commands => _commands.stream;

  @override
  Future<bool> configure(MenuConfiguration configuration) async {
    try {
      final configured = await _channel.invokeMethod<Object?>(
        'configure',
        <String, Object?>{
          'version': schemaVersion,
          'fileMenuLabel': configuration.fileMenuLabel,
          'openProjectLabel': configuration.openProjectLabel,
        },
      );
      return configured == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> setMenuEnabled({
    required String commandId,
    required bool enabled,
  }) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', <String, Object?>{
        'commandId': commandId,
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Windows and Linux do not install the native application menu channel.
    }
  }

  /// Releases the native callback and command stream.
  Future<void> close() async {
    _channel.setMethodCallHandler(null);
    await _commands.close();
  }

  Future<Object?> _handleMethodCall(PlatformMethodCall call) async {
    if (call.method == 'openProject' && !_commands.isClosed) {
      _commands.add(MenuCommand.openProject);
    }
    return null;
  }
}
