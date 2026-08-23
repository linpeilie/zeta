import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_effect.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_intent.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart';

/// IDE Session 的纯同步 reducer。
Transition<IdeSessionSliceState, IdeSessionSliceEffect> ideSessionSliceReduce(
  IdeSessionSliceState state,
  IdeSessionSliceIntent intent,
) {
  switch (intent) {
    case IdeSessionRestoreRequested():
      return Transition(
        state.copyWith(isRestoring: true, clearRestoreStatus: true),
        const <IdeSessionSliceEffect>[RestoreIdeSessionEffect()],
      );

    case IdeSessionRestoreResultReceived():
      return Transition.stateOnly(
        state.copyWith(isRestoring: false, restoreStatus: intent.result.status),
      );

    case IdeSessionRestoreCancellationRequested():
      return Transition(
        state.isRestoring
            ? state.copyWith(
                isRestoring: false,
                restoreStatus: IdeSessionRestoreStatus.cancelled,
              )
            : state,
        const <IdeSessionSliceEffect>[CancelIdeSessionRestoreEffect()],
      );

    case IdeSessionInitialRestoreCompleted():
      return state.initialRestoreCompleted
          ? Transition.none(state)
          : Transition.stateOnly(state.copyWith(initialRestoreCompleted: true));

    case IdeSessionSaveRequested():
      return Transition(state, <IdeSessionSliceEffect>[
        RequestIdeSessionSaveEffect(intent.snapshot),
      ]);

    case IdeSessionSaveNowRequested():
      return Transition(state, <IdeSessionSliceEffect>[
        SaveIdeSessionNowEffect(intent.operationId, intent.snapshot),
      ]);

    case IdeSessionSaveNowCompleted():
      return Transition.none(state);

    case IdeSessionWorkbenchLayoutChanged():
      return intent.layout == state.workbenchLayout
          ? Transition.none(state)
          : Transition.stateOnly(
              state.copyWith(workbenchLayout: intent.layout),
            );
  }
}
