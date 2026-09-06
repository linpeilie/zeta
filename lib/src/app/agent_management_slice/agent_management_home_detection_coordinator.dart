import 'dart:async';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_operations.dart';

/// 工作台启动条件属于 app；视图卸载不改变探测或近期 thread 预热的生命周期。
final class AgentManagementHomeDetectionCoordinator {
  AgentManagementHomeDetectionCoordinator(this.shell, this.management);
  final IdeShellController shell;
  final AgentManagementOperations management;
  bool _closed = false;
  bool _homeThreadsPrewarmed = false;
  void start() {
    shell.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (_closed) return;
    if (shell.activeProjectPath != null) {
      _homeThreadsPrewarmed = false;
      return;
    }
    if (!shell.initialRestoreCompleted) return;
    // Shell 可能在 Widget 事件中同步发布；业务写入放在同一 app 会话的微任务。
    scheduleMicrotask(() {
      if (_closed ||
          !shell.initialRestoreCompleted ||
          shell.activeProjectPath != null) {
        return;
      }
      unawaited(management.ensureDetected());
      if (!_homeThreadsPrewarmed) {
        _homeThreadsPrewarmed = true;
        unawaited(shell.refreshRecentHomeData());
      }
    });
  }

  void close() {
    if (_closed) return;
    _closed = true;
    shell.removeListener(_changed);
  }
}
