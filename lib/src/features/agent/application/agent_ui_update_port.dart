import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';

/// Application 向 presentation 发布类型化 UI 更新请求的端口。
///
/// 端口不依赖 Flutter binding；具体的帧合并策略由 presentation 实现。
abstract interface class AgentUiUpdatePort {
  /// 提交一个不可变 UI 更新请求。
  void publish(AgentUiUpdateRequest request);
}

/// Presentation 帧调度实现所需的最小可注入端口。
///
/// 该契约只使用 [VoidCallback]，不引用 `SchedulerBinding`；生产适配器和测试 fake
/// 分别位于 presentation 与测试支持代码中。
abstract interface class AgentFrameScheduler {
  /// 当前是否位于 Widget build/layout/paint 所在的 persistent callback 阶段。
  bool get isInBuildPhase;

  /// 将回调排入下一 Flutter frame 的 transient callback 阶段。
  void scheduleNextFrame(VoidCallback callback);
}
