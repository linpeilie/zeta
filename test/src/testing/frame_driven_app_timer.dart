import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Tests advance app timers with frames. Unlike Widget timers these may outlive
/// the Widget tree; app.close still cancels them before container disposal.
final class FrameDrivenAppTimer implements Timer {
  FrameDrivenAppTimer(Duration duration, void Function() callback)
    : this.periodic(duration, (_) => callback(), repeat: false);
  FrameDrivenAppTimer.periodic(
    this.duration,
    this.callback, {
    this.repeat = true,
  }) {
    _deadline = _binding.clock.now().add(duration);
    _schedule();
  }
  final Duration duration;
  final void Function(Timer) callback;
  final bool repeat;
  final _binding = TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime _deadline;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void _schedule() {
    _binding.addPostFrameCallback((_) {
      if (!_active) return;
      final now = _binding.clock.now();
      if (!now.isBefore(_deadline)) {
        _tick++;
        if (!repeat) _active = false;
        _deadline = now.add(duration);
        callback(this);
      }
      if (_active) _schedule();
    });
  }
}

final class FrameDrivenAgentElapsedTicker extends AgentElapsedTicker {
  Timer? _frameTimer;
  DateTime _frameNow = DateTime.now();
  @override
  DateTime get now => _frameNow;
  @override
  bool get isRunning => _frameTimer != null;
  @override
  void start() {
    _frameNow = TestWidgetsFlutterBinding.ensureInitialized().clock.now();
    notifyListeners();
    _frameTimer ??= FrameDrivenAppTimer.periodic(const Duration(seconds: 1), (
      _,
    ) {
      _frameNow = TestWidgetsFlutterBinding.ensureInitialized().clock.now();
      notifyListeners();
    });
  }

  @override
  void stop() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }
}
