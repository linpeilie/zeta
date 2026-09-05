import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/window/zeta_window_surface.dart';

/// 按应用生命周期与窗口最小化状态开关全局 ticker。
///
/// 从 `MainApp` 拆出：窗口监听归 [zetaWindowSurfaceProvider]，生命周期观察只为
/// [TickerMode] 服务。两者合在这一层，调用点不再 mixin 平台窗口监听。
final class ZetaTickerGate extends ConsumerStatefulWidget {
  const ZetaTickerGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ZetaTickerGate> createState() => ZetaTickerGateState();
}

/// ticker 闸门的 State。widget test 测生命周期时直接调
/// [didChangeAppLifecycleState]：走 `binding.handleAppLifecycleStateChanged`
/// 会在测试里关掉 frames，随后的 `pump` 不再重建。
final class ZetaTickerGateState extends ConsumerState<ZetaTickerGate>
    with WidgetsBindingObserver {
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lifecycle == state) {
      return;
    }
    setState(() => _lifecycle = state);
  }

  @override
  Widget build(BuildContext context) {
    final minimized = ref.watch(
      zetaWindowSurfaceProvider.select((state) => state.minimized),
    );
    final lifecycleAllowsTickers =
        _lifecycle == null ||
        _lifecycle == AppLifecycleState.resumed ||
        _lifecycle == AppLifecycleState.inactive;
    return TickerMode(
      enabled: lifecycleAllowsTickers && !minimized,
      child: widget.child,
    );
  }
}
