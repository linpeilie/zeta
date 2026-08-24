import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

/// Shell 可消费的 IDE Session application 操作口。
abstract interface class IdeSessionSliceOperations {
  IdeSessionSliceState get state;

  Future<IdeSessionRestoreResult> restore();

  void cancelPendingRestore();

  void requestSave(IdeSessionState snapshot);

  Future<void> saveNow(IdeSessionState snapshot);

  void setWorkbenchLayout(IdeWorkbenchLayoutState layout);

  /// 用户主动打开项目时释放冷启动等待，但不伪造 restore I/O 已完成。
  void releaseInitialRestoreWait();

  /// restore I/O 的 finally 已收敛，允许无项目首页稳定显示。
  void completeInitialRestore();

  Future<void> get initialRestoreDone;

  /// 订阅状态变化；返回取消订阅的回调。
  ///
  /// 纯 Dart 端口：presentation 因此能定向监听 IDE Session，而不必去监听
  /// 整个 Shell。
  void Function() subscribe(void Function() listener);
}
