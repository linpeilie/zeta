import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_effect.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_intent.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_reducer.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
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

  test('notifier exposes typed restore and save operation futures', () async {
    final runner = _RecordingIdeSessionRunner();
    final container = _createContainer(runner);
    final store = container.read(ideSessionSliceProvider.notifier);
    var notifications = 0;
    container.listen(ideSessionSliceProvider, (_, _) => notifications += 1);

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

    // 保存不改运行态，因此从 restore 开始到这里只提交过两次状态，且都落在同一个
    // microtask 窗口内——广播被合并成一次。
    expect(notifications, 1);

    store.setWorkbenchLayout(
      const IdeWorkbenchLayoutState(selectedAgentUsageProviderId: 'codex'),
    );
    expect(
      store.state.workbenchLayout.selectedAgentUsageProviderId,
      'codex',
      reason: '命令入口读到的必须是已提交值，不受广播调度影响',
    );
    await Future<void>.microtask(() {});
    expect(notifications, 2);
  });

  test('initial wait can release before restore lifecycle completes', () async {
    final container = _createContainer(_RecordingIdeSessionRunner());
    final store = container.read(ideSessionSliceProvider.notifier);

    store.releaseInitialRestoreWait();
    await store.initialRestoreDone;

    expect(store.state.initialRestoreCompleted, isFalse);
    store.completeInitialRestore();
    expect(store.state.initialRestoreCompleted, isTrue);
  });

  test('container dispose settles every pending operation', () async {
    final runner = _RecordingIdeSessionRunner();
    final container = ProviderContainer(
      overrides: [
        ideSessionSliceEffectRunnerFactoryProvider.overrideWithValue(
          (_) => runner,
        ),
      ],
    );
    final store = container.read(ideSessionSliceProvider.notifier);
    final restoreFuture = store.restore();
    final saveFuture = store.saveNow(const IdeSessionState());

    container.dispose();

    expect((await restoreFuture).status, IdeSessionRestoreStatus.cancelled);
    await saveFuture;
    await store.initialRestoreDone;
    expect(runner.closed, isTrue);
    expect(() => store.restore(), throwsStateError);
  });
}

/// 纯 Dart 容器：application 层用 `package:riverpod`，因此这里不需要 widget
/// binding 就能把切片完整跑起来（工程规范 §3.0）。
ProviderContainer _createContainer(IdeSessionSliceEffectRunner runner) {
  final container = ProviderContainer(
    overrides: [
      ideSessionSliceEffectRunnerFactoryProvider.overrideWithValue(
        (_) => runner,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
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
