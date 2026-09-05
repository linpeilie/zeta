import 'package:meta/meta.dart';

import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

/// IDE Session 的轻量运行态。
///
/// 持久化的 `IdeSessionState` 是跨 feature 白名单投影，不保存在这里，避免形成
/// 第二份 workspace/thread 业务状态。
@immutable
final class IdeSessionSliceState {
  const IdeSessionSliceState({
    this.isRestoring = false,
    this.restoreStatus,
    this.initialRestoreCompleted = false,
    this.workbenchLayout = const IdeWorkbenchLayoutState(),
  });

  final bool isRestoring;
  final IdeSessionRestoreStatus? restoreStatus;
  final bool initialRestoreCompleted;
  final IdeWorkbenchLayoutState workbenchLayout;

  IdeSessionSliceState copyWith({
    bool? isRestoring,
    IdeSessionRestoreStatus? restoreStatus,
    bool clearRestoreStatus = false,
    bool? initialRestoreCompleted,
    IdeWorkbenchLayoutState? workbenchLayout,
  }) {
    return IdeSessionSliceState(
      isRestoring: isRestoring ?? this.isRestoring,
      restoreStatus: clearRestoreStatus
          ? null
          : restoreStatus ?? this.restoreStatus,
      initialRestoreCompleted:
          initialRestoreCompleted ?? this.initialRestoreCompleted,
      workbenchLayout: workbenchLayout ?? this.workbenchLayout,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IdeSessionSliceState &&
        other.isRestoring == isRestoring &&
        other.restoreStatus == restoreStatus &&
        other.initialRestoreCompleted == initialRestoreCompleted &&
        other.workbenchLayout == workbenchLayout;
  }

  @override
  int get hashCode => Object.hash(
    isRestoring,
    restoreStatus,
    initialRestoreCompleted,
    workbenchLayout,
  );
}
