import 'package:flutter/scheduler.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 基于 [SchedulerBinding] 的生产 frame 调度实现。
///
/// application 层的 [AgentUiUpdateScheduler] 只依赖 [AgentFrameScheduler] 端口；
/// 这个 Flutter 适配器由组合根 / ViewModel 注入。
final class SchedulerBindingAgentFrameScheduler implements AgentFrameScheduler {
  const SchedulerBindingAgentFrameScheduler();

  @override
  bool get isInBuildPhase =>
      SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;

  @override
  void scheduleNextFrame(VoidCallback callback) {
    final binding = SchedulerBinding.instance;
    binding.scheduleFrameCallback((_) => callback());
    binding.ensureVisualUpdate();
  }
}
