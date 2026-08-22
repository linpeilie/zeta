import 'dart:async';

import 'package:flutter/foundation.dart';

/// 共享 1 秒时钟：仅在 turn 执行中运行，供 header/卡片局部刷新 elapsed。
///
/// 不替代事件驱动的 typed header state；相位变化仍走类型化 UI 状态。
class AgentElapsedTicker extends ChangeNotifier {
  Timer? _timer;
  DateTime _now = DateTime.now();

  /// 最近一次 tick 的本地时间。
  DateTime get now => _now;

  bool get isRunning => _timer != null;

  /// 开始周期刷新；已在运行时仅刷新一次 [now]。
  void start() {
    _now = DateTime.now();
    if (_timer != null) {
      notifyListeners();
      return;
    }
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _now = DateTime.now();
      notifyListeners();
    });
  }

  /// 停止周期刷新（turn 结束或 dispose）。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
