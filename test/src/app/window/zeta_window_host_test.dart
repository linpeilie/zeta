import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/window/zeta_shutdown_hook.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';

void main() {
  test('native host 按登记顺序跑 shutdown hook，且不经平台通道', () async {
    final host = NativeDesktopWindowHost();
    final order = <int>[];
    final first = _RecordingShutdownHook(1, order);
    final second = _RecordingShutdownHook(2, order);
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
    final order = <int>[];
    host.addShutdownHook(_RecordingShutdownHook(1, order));
    await host.closeWindow();
    expect(order, isEmpty);
  });
}

final class _RecordingShutdownHook implements ZetaShutdownHook {
  _RecordingShutdownHook(this.id, this.order);

  final int id;
  final List<int> order;

  @override
  Future<void> run() async => order.add(id);
}
