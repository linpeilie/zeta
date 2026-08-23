import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';

/// IDE Session 持久化副作用描述。
sealed class IdeSessionSliceEffect {
  const IdeSessionSliceEffect();
}

final class RestoreIdeSessionEffect extends IdeSessionSliceEffect {
  const RestoreIdeSessionEffect();
}

final class CancelIdeSessionRestoreEffect extends IdeSessionSliceEffect {
  const CancelIdeSessionRestoreEffect();
}

final class RequestIdeSessionSaveEffect extends IdeSessionSliceEffect {
  const RequestIdeSessionSaveEffect(this.snapshot);

  final IdeSessionState snapshot;
}

final class SaveIdeSessionNowEffect extends IdeSessionSliceEffect {
  const SaveIdeSessionNowEffect(this.operationId, this.snapshot);

  final OperationId operationId;
  final IdeSessionState snapshot;
}
