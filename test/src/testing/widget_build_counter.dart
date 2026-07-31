import 'package:flutter/widgets.dart';

/// 阶段 0 关注的关键 Widget runtimeType。
abstract final class AgentBuildTarget {
  static const String ideHome = 'IdeHome';
  static const String agentPane = 'AgentPane';
  static const String header = '_AgentHeader';
  static const String composer = '_AgentComposerSection';
  static const String liveTimeline = '_AgentConversationTimeline';

  static const Set<String> all = <String>{
    ideHome,
    agentPane,
    header,
    composer,
    liveTimeline,
  };
}

/// 仅供 Widget 测试使用的 dirty rebuild 观察器。
///
/// 它使用 Flutter debug callback 观察现有 Element，不向生产 Widget 注入 observer
/// 或额外 API。快照只包含 runtimeType 对应的计数。
final class TestWidgetBuildCounter {
  TestWidgetBuildCounter({Set<String> runtimeTypes = AgentBuildTarget.all})
    : _runtimeTypes = Set<String>.unmodifiable(runtimeTypes),
      _counts = <String, int>{
        for (final runtimeType in runtimeTypes) runtimeType: 0,
      };

  final Set<String> _runtimeTypes;
  final Map<String, int> _counts;
  late final RebuildDirtyWidgetCallback _callback = _handleRebuild;
  RebuildDirtyWidgetCallback? _previousCallback;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _previousCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = _callback;
  }

  void reset() {
    for (final runtimeType in _runtimeTypes) {
      _counts[runtimeType] = 0;
    }
  }

  TestWidgetBuildCountSnapshot snapshot() {
    return TestWidgetBuildCountSnapshot(_counts);
  }

  void dispose() {
    if (!_started) {
      return;
    }
    if (identical(debugOnRebuildDirtyWidget, _callback)) {
      debugOnRebuildDirtyWidget = _previousCallback;
    }
    _previousCallback = null;
    _started = false;
  }

  void _handleRebuild(Element element, bool builtOnce) {
    _previousCallback?.call(element, builtOnce);
    final runtimeType = element.widget.runtimeType.toString();
    if (_runtimeTypes.contains(runtimeType)) {
      _counts.update(runtimeType, (count) => count + 1);
    }
  }
}

/// 与可变计数器隔离的只读快照。
final class TestWidgetBuildCountSnapshot {
  TestWidgetBuildCountSnapshot(Map<String, int> counts)
    : counts = Map<String, int>.unmodifiable(counts);

  final Map<String, int> counts;

  int operator [](String runtimeType) => counts[runtimeType] ?? 0;

  @override
  String toString() => counts.toString();
}
