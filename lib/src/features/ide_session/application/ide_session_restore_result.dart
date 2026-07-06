import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';

enum IdeSessionRestoreStatus { restored, empty, failed, cancelled }

/// IDE 会话恢复的应用层结果。
class IdeSessionRestoreResult {
  const IdeSessionRestoreResult._({required this.status, this.snapshot});

  const IdeSessionRestoreResult.restored(IdeSessionState snapshot)
    : this._(status: IdeSessionRestoreStatus.restored, snapshot: snapshot);

  const IdeSessionRestoreResult.empty()
    : this._(status: IdeSessionRestoreStatus.empty);

  const IdeSessionRestoreResult.failed()
    : this._(status: IdeSessionRestoreStatus.failed);

  const IdeSessionRestoreResult.cancelled()
    : this._(status: IdeSessionRestoreStatus.cancelled);

  final IdeSessionRestoreStatus status;
  final IdeSessionState? snapshot;

  bool get shouldApplySnapshot => snapshot != null;

  bool get shouldRequestSave =>
      status == IdeSessionRestoreStatus.restored ||
      status == IdeSessionRestoreStatus.failed;
}
