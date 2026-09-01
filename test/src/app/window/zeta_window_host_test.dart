import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/window/zeta_window_host.dart';

void main() {
  test('native host 按登记顺序跑 shutdown hook，且不经平台通道', () async {
    final host = NativeDesktopWindowHost();
    final order = <int>[];
    Future<void> first() async => order.add(1);
    Future<void> second() async => order.add(2);
    host.addShutdownHook(first);
    host.addShutdownHook(second);
    await host.flushShutdownHooks();
    expect(order, <int>[1, 2]);

    order.clear();
    host.removeShutdownHook(first);
    await host.flushShutdownHooks();
    expect(order, <int>[2]);
  });

  test('headless host 的 shutdown hook 是空操作', () async {
    final host = HeadlessWindowHost();
    var ran = false;
    host.addShutdownHook(() async => ran = true);
    await host.closeWindow();
    expect(ran, isFalse);
  });
}
