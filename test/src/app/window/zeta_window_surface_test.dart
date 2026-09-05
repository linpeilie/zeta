import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/app/window/zeta_window_surface.dart';

void main() {
  late HeadlessWindowHost host;
  late ProviderContainer container;

  setUp(() {
    host = HeadlessWindowHost();
    container = ProviderContainer(
      overrides: <Override>[zetaWindowHostProvider.overrideWithValue(host)],
    );
    addTearDown(container.dispose);
    container.read(zetaWindowSurfaceProvider);
  });

  test('默认窗口表面是聚焦、未最小化', () {
    expect(
      container.read(zetaWindowSurfaceProvider),
      const ZetaWindowSurfaceState(),
    );
  });

  test('minimize 暂停 ticker 并失去焦点', () {
    host.emitMinimize();
    expect(
      container.read(zetaWindowSurfaceProvider),
      const ZetaWindowSurfaceState(focused: false, minimized: true),
    );
  });

  test('restore 恢复 ticker 与焦点', () {
    host.emitMinimize();
    host.emitRestore();
    expect(
      container.read(zetaWindowSurfaceProvider),
      const ZetaWindowSurfaceState(),
    );
  });

  test('maximize 只恢复 ticker，不改焦点', () {
    host.emitMinimize();
    host.emitMaximize();
    expect(
      container.read(zetaWindowSurfaceProvider),
      const ZetaWindowSurfaceState(focused: false, maximized: true),
    );
  });

  test('focus 恢复 ticker 并聚焦', () {
    host.emitMinimize();
    host.emitFocus();
    expect(
      container.read(zetaWindowSurfaceProvider),
      const ZetaWindowSurfaceState(),
    );
  });

  test('blur 只失去焦点', () {
    host.emitBlur();
    expect(
      container.read(zetaWindowSurfaceProvider),
      const ZetaWindowSurfaceState(focused: false),
    );
  });

  test('show 事件恢复 ticker', () {
    host.emitMinimize();
    host.emitEvent('show');
    expect(
      container.read(zetaWindowSurfaceProvider),
      const ZetaWindowSurfaceState(focused: false),
    );
  });

  test('全屏恢复 ticker', () {
    host.emitMinimize();
    host.emitEnterFullScreen();
    expect(
      container.read(zetaWindowSurfaceProvider),
      const ZetaWindowSurfaceState(focused: false),
    );
  });
}
