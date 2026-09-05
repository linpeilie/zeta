import 'dart:async';

import 'package:meta/meta.dart';

/// 中立内核使用的无参数状态监听回调。
typedef AgentListener = void Function();

/// 不依赖 Flutter 的最小监听协议。
abstract interface class AgentListenable {
  /// 注册状态变化监听器。
  void addListener(AgentListener listener);

  /// 取消监听；未注册过的监听器会被忽略。
  void removeListener(AgentListener listener);
}

/// 携带同步快照的纯 Dart 监听协议。
abstract interface class AgentValueListenable<T> implements AgentListenable {
  /// 当前同步快照。
  T get value;
}

/// 内核状态对象共享的轻量通知基类。
///
/// 通知时复制监听器列表，允许回调安全地增删订阅。重复注册与 Flutter
/// `ChangeNotifier` 一致，会收到对应次数的通知；每次移除只移除一个注册项。
abstract class AgentChangeNotifier implements AgentListenable {
  List<AgentListener>? _listeners = <AgentListener>[];

  /// 当前是否至少有一个监听器。
  bool get hasListeners => _listeners?.isNotEmpty ?? false;

  @override
  void addListener(AgentListener listener) {
    final listeners = _listeners;
    if (listeners == null) {
      throw StateError('$runtimeType is disposed');
    }
    listeners.add(listener);
  }

  @override
  void removeListener(AgentListener listener) {
    _listeners?.remove(listener);
  }

  /// 同步通知注册时序快照中的监听器。
  @protected
  void notifyListeners() {
    final listeners = _listeners;
    if (listeners == null || listeners.isEmpty) {
      return;
    }
    final failures = <({Object error, StackTrace stackTrace})>[];
    for (final listener in List<AgentListener>.of(listeners)) {
      // 回调若已在本轮通知中被移除，就不再调用；重复注册仍按剩余次数执行。
      if (_listeners?.contains(listener) ?? false) {
        try {
          listener();
        } catch (error, stackTrace) {
          // 与 Flutter ChangeNotifier 一样，单个坏监听器不得截断其余监听器。
          // 延后到本轮通知结束再交给当前 Zone，既不静默吞错，也避免报告端
          // 自身抛错破坏后续回调的投递。
          failures.add((error: error, stackTrace: stackTrace));
        }
      }
    }
    for (final failure in failures) {
      Zone.current.handleUncaughtError(failure.error, failure.stackTrace);
    }
  }

  /// 释放全部监听器；重复释放安全。
  @mustCallSuper
  void dispose() {
    _listeners = null;
  }
}

/// 与 [AgentValueListenable] 配套的可写同步信号。
final class AgentValueNotifier<T> extends AgentChangeNotifier
    implements AgentValueListenable<T> {
  AgentValueNotifier(this._value);

  T _value;

  @override
  T get value => _value;

  set value(T next) {
    if (_value == next) {
      return;
    }
    _value = next;
    notifyListeners();
  }
}
