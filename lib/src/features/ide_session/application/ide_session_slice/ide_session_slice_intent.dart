import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

sealed class IdeSessionSliceIntent {
  const IdeSessionSliceIntent();
}

final class IdeSessionRestoreRequested extends IdeSessionSliceIntent {
  const IdeSessionRestoreRequested();
}

final class IdeSessionRestoreResultReceived extends IdeSessionSliceIntent {
  const IdeSessionRestoreResultReceived(this.result);

  final IdeSessionRestoreResult result;
}

final class IdeSessionRestoreCancellationRequested
    extends IdeSessionSliceIntent {
  const IdeSessionRestoreCancellationRequested();
}

final class IdeSessionInitialRestoreCompleted extends IdeSessionSliceIntent {
  const IdeSessionInitialRestoreCompleted();
}

final class IdeSessionSaveRequested extends IdeSessionSliceIntent {
  const IdeSessionSaveRequested(this.snapshot);

  final IdeSessionState snapshot;
}

final class IdeSessionSaveNowRequested extends IdeSessionSliceIntent {
  const IdeSessionSaveNowRequested(this.operationId, this.snapshot);

  final OperationId operationId;
  final IdeSessionState snapshot;
}

final class IdeSessionSaveNowCompleted extends IdeSessionSliceIntent {
  const IdeSessionSaveNowCompleted(this.operationId);

  final OperationId operationId;
}

final class IdeSessionWorkbenchLayoutChanged extends IdeSessionSliceIntent {
  const IdeSessionWorkbenchLayoutChanged(this.layout);

  final IdeWorkbenchLayoutState layout;
}
