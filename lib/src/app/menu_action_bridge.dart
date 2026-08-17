import 'package:flutter/services.dart';

/// 连接原生菜单（macOS「文件」菜单）与 Flutter 侧动作的桥接。
///
/// 原生菜单被选中后，通过名为 `zeta/menu` 的 [MethodChannel] 调用 Flutter；
/// 本桥接将调用分发到注册的回调，并向原生发送版本化菜单配置。
/// 生产环境使用 [instance]；测试可通过 [MenuActionBridge.new] 注入通道。
class MenuActionBridge {
  MenuActionBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('zeta/menu');

  static final MenuActionBridge instance = MenuActionBridge();

  /// 当前 Flutter → 原生 configure 协议版本。
  static const int schemaVersion = 1;

  final MethodChannel _channel;

  VoidCallback? _openProjectHandler;
  bool _handlerInstalled = false;

  /// 注册「打开项目」回调；传 `null` 取消注册。
  void setOpenProject(VoidCallback? callback) {
    _openProjectHandler = callback;
    if (callback != null) {
      _ensureHandlerInstalled();
    }
  }

  /// 把当前进程语言的 File / Open Project 标签发给原生。
  ///
  /// 未知版本或缺字段由原生 fail-closed：不安装、不更新，并返回 false。
  /// Windows / Linux 没有该插件时视为无需配置。
  Future<bool> configure({
    required String fileMenuLabel,
    required String openProjectLabel,
  }) async {
    try {
      final result = await _channel.invokeMethod<Object?>('configure', {
        'version': schemaVersion,
        'fileMenuLabel': fileMenuLabel,
        'openProjectLabel': openProjectLabel,
      });
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
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
