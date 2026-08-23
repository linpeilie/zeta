import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_effect.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_intent.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_reducer.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

void main() {
  test('reducer keeps persistent snapshot out of runtime state', () {
    const snapshot = IdeSessionState(projectPaths: <String>['/repo']);

    final requested = ideSessionSliceReduce(
      const IdeSessionSliceState(),
      const IdeSessionRestoreRequested(),
    );
    final received = ideSessionSliceReduce(
      requested.state,
      const IdeSessionRestoreResultReceived(
        IdeSessionRestoreResult.restored(snapshot),
      ),
    );

    expect(requested.state.isRestoring, isTrue);
    expect(requested.state.restoreStatus, isNull);
    expect(requested.effects.single, isA<RestoreIdeSessionEffect>());
    expect(received.state.isRestoring, isFalse);
    expect(received.state.restoreStatus, IdeSessionRestoreStatus.restored);
    expect(received.effects, isEmpty);
  });

  test('reducer separates cancellation, completion and layout intent', () {
    const layout = IdeWorkbenchLayoutState(
      leftSidebarVisible: false,
      leftSidebarWidth: 320,
      selectedAgentUsageProviderId: 'grok',
    );
    final restoring = ideSessionSliceReduce(
      const IdeSessionSliceState(),
      const IdeSessionRestoreRequested(),
    ).state;

    final cancelled = ideSessionSliceReduce(
      restoring,
      const IdeSessionRestoreCancellationRequested(),
    );
    final completed = ideSessionSliceReduce(
      cancelled.state,
      const IdeSessionInitialRestoreCompleted(),
    );
    final layoutChanged = ideSessionSliceReduce(
      completed.state,
      const IdeSessionWorkbenchLayoutChanged(layout),
    );

    expect(cancelled.state.isRestoring, isFalse);
    expect(cancelled.state.restoreStatus, IdeSessionRestoreStatus.cancelled);
    expect(cancelled.effects.single, isA<CancelIdeSessionRestoreEffect>());
    expect(completed.state.initialRestoreCompleted, isTrue);
    expect(layoutChanged.state.workbenchLayout, layout);
  });

  test('store exposes typed restore and save operation futures', () async {
    final runner = _RecordingIdeSessionRunner();
    final store = IdeSessionSliceStore(
      initialState: const IdeSessionSliceState(),
      effectRunner: runner,
    );
    addTearDown(store.dispose);
    var notifications = 0;
    store.addListener(() => notifications += 1);

    final restoreFuture = store.restore();
    expect(runner.effects.single, isA<RestoreIdeSessionEffect>());
    expect(store.state.isRestoring, isTrue);

    store.restoreResultReceived(const IdeSessionRestoreResult.empty());
    expect((await restoreFuture).status, IdeSessionRestoreStatus.empty);
    expect(store.state.restoreStatus, IdeSessionRestoreStatus.empty);

    const snapshot = IdeSessionState(
      workbenchLayout: IdeWorkbenchLayoutState(leftSidebarVisible: false),
    );
    store.requestSave(snapshot);
    expect(runner.effects.last, isA<RequestIdeSessionSaveEffect>());

    final saveFuture = store.saveNow(snapshot);
    final saveEffect = runner.effects.last as SaveIdeSessionNowEffect;
    expect(saveEffect.snapshot, same(snapshot));
    store.saveNowCompleted(saveEffect.operationId);
    await saveFuture;

    expect(notifications, 2);
  });

  test('initial wait can release before restore lifecycle completes', () async {
    final runner = _RecordingIdeSessionRunner();
    final store = IdeSessionSliceStore(
      initialState: const IdeSessionSliceState(),
      effectRunner: runner,
    );
    addTearDown(store.dispose);

    store.releaseInitialRestoreWait();
    await store.initialRestoreDone;

    expect(store.state.initialRestoreCompleted, isFalse);
    store.completeInitialRestore();
    expect(store.state.initialRestoreCompleted, isTrue);
  });

  test('dispose settles pending operations and closes runner', () async {
    final runner = _RecordingIdeSessionRunner();
    final store = IdeSessionSliceStore(
      initialState: const IdeSessionSliceState(),
      effectRunner: runner,
    );
    final restoreFuture = store.restore();
    final saveFuture = store.saveNow(const IdeSessionState());

    store.dispose();

    expect((await restoreFuture).status, IdeSessionRestoreStatus.cancelled);
    await saveFuture;
    await store.initialRestoreDone;
    expect(runner.closed, isTrue);
    expect(() => store.restore(), throwsStateError);
  });
}

final class _RecordingIdeSessionRunner implements IdeSessionSliceEffectRunner {
  final List<IdeSessionSliceEffect> effects = <IdeSessionSliceEffect>[];
  bool closed = false;

  @override
  void run(IdeSessionSliceEffect effect) {
    effects.add(effect);
  }

  @override
  void close() {
    closed = true;
  }
}
