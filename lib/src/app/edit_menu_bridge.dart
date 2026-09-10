import 'package:flutter/services.dart';

/// 原生 Edit 菜单（macOS Copy）到 Flutter 选区的桥接。
///
/// 菜单项 `copy:` 打在 First Responder 上，不会经过 Dart [Shortcuts]。
/// 对话流 [SelectionArea] 有焦点时，由此把复制转交给 Flutter。
class EditMenuBridge {
  EditMenuBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'zeta/edit_menu';

  static final EditMenuBridge instance = EditMenuBridge();

  final MethodChannel _channel;

  VoidCallback? _copyHandler;
  bool _handlerInstalled = false;

  /// 注册 Copy 回调；传 `null` 取消注册。
  void setCopyHandler(VoidCallback? callback) {
    _copyHandler = callback;
    if (callback != null) {
      _ensureHandlerInstalled();
    }
  }

  void _ensureHandlerInstalled() {
    if (_handlerInstalled) {
      return;
    }
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'copy':
          _copyHandler?.call();
      }
      return null;
    });
  }
}
