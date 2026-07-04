import 'package:flutter/services.dart';

/// 连接原生菜单（macOS「文件」菜单）与 Flutter 侧动作的单例桥接。
///
/// 原生菜单被选中后，通过名为 `zeta/menu` 的 [MethodChannel] 调用 Flutter；
/// 本桥接将调用分发到注册的回调。仅应在生产环境（非 widget 测试）注册。
class MenuActionBridge {
  MenuActionBridge._();

  static final MenuActionBridge instance = MenuActionBridge._();

  static const MethodChannel _channel = MethodChannel('zeta/menu');

  VoidCallback? _openProjectHandler;
  bool _handlerInstalled = false;

  /// 注册「打开项目」回调；传 `null` 取消注册。
  void setOpenProject(VoidCallback? callback) {
    _openProjectHandler = callback;
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
        case 'openProject':
          _openProjectHandler?.call();
      }
      return null;
    });
  }
}
