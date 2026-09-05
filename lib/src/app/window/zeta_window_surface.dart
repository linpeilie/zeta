import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/window/zeta_window_host.dart';

/// 桌面窗口表面的只读快照。
///
/// 平台 [WindowListener] 只在 [ZetaWindowSurfaceNotifier] 里实现一次，这里是
/// 翻译后的中立状态。根组件与 IdeHome 不得再 mixin 平台监听。
///
/// - [focused]：桌面通知是否把窗口当作用户正在看（对应原 `IdeHome._windowFocused`）
/// - [minimized]：是否暂停全局 ticker（对应原 `MainApp._nativeWindowSuspended`）
/// - [maximized]：留给标题栏按钮；本轮消费方还不读它
@immutable
final class ZetaWindowSurfaceState {
  const ZetaWindowSurfaceState({
    this.focused = true,
    this.minimized = false,
    this.maximized = false,
  });

  final bool focused;
  final bool minimized;
  final bool maximized;

  ZetaWindowSurfaceState copyWith({
    bool? focused,
    bool? minimized,
    bool? maximized,
  }) {
    return ZetaWindowSurfaceState(
      focused: focused ?? this.focused,
      minimized: minimized ?? this.minimized,
      maximized: maximized ?? this.maximized,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ZetaWindowSurfaceState &&
        other.focused == focused &&
        other.minimized == minimized &&
        other.maximized == maximized;
  }

  @override
  int get hashCode => Object.hash(focused, minimized, maximized);
}

/// 全应用唯一的窗口 [WindowListener]。
///
/// 事件映射保持收敛前两处 Widget 的既有语义，不在这里「补齐」：
///
/// - ticker：minimize → 暂停；restore / maximize / focus / 全屏 / `show` → 恢复
/// - 通知焦点：只认 focus / blur / minimize / restore；maximize 不改 [focused]
final class ZetaWindowSurfaceNotifier extends Notifier<ZetaWindowSurfaceState>
    with WindowListener {
  @override
  ZetaWindowSurfaceState build() {
    final host = ref.watch(zetaWindowHostProvider);
    host.addListener(this);
    ref.onDispose(() => host.removeListener(this));
    return const ZetaWindowSurfaceState();
  }

  @override
  void onWindowMinimize() {
    _emit(state.copyWith(focused: false, minimized: true));
  }

  @override
  void onWindowRestore() {
    _emit(state.copyWith(focused: true, minimized: false));
  }

  @override
  void onWindowMaximize() {
    _emit(state.copyWith(minimized: false, maximized: true));
  }

  @override
  void onWindowUnmaximize() {
    _emit(state.copyWith(maximized: false));
  }

  @override
  void onWindowFocus() {
    _emit(state.copyWith(focused: true, minimized: false));
  }

  @override
  void onWindowBlur() {
    _emit(state.copyWith(focused: false));
  }

  @override
  void onWindowEnterFullScreen() {
    _emit(state.copyWith(minimized: false));
  }

  @override
  void onWindowEvent(String eventName) {
    // window_manager 0.5.x 会从 Windows WM_SHOWWINDOW 发出 show，
    // 但 WindowListener 尚无对应的强类型回调。
    if (eventName == 'show') {
      _emit(state.copyWith(minimized: false));
    }
  }

  void _emit(ZetaWindowSurfaceState next) {
    if (next == state) {
      return;
    }
    state = next;
  }
}

final zetaWindowSurfaceProvider =
    NotifierProvider<ZetaWindowSurfaceNotifier, ZetaWindowSurfaceState>(
      ZetaWindowSurfaceNotifier.new,
      name: 'zetaWindowSurface',
    );
