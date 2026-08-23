import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/ide_session_slice/ide_session_slice_composition.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

void main() {
  test(
    'composition routes restored and failed results back to state',
    () async {
      final restoredStore = _FakeIdeSessionStore(
        initialSnapshot: const IdeSessionState(projectPaths: <String>['/repo']),
      );
      final restored = IdeSessionSliceComposition.create(
        sessionStore: restoredStore,
        fileExists: (_) => true,
        directoryExists: (_) => true,
      );
      addTearDown(restored.dispose);

      final restoredResult = await restored.store.restore();

      expect(restoredResult.status, IdeSessionRestoreStatus.restored);
      expect(restoredResult.snapshot?.projectPaths, <String>['/repo']);
      expect(
        restored.store.state.restoreStatus,
        IdeSessionRestoreStatus.restored,
      );

      final failed = IdeSessionSliceComposition.create(
        sessionStore: _FakeIdeSessionStore(loadError: StateError('fixture')),
        fileExists: (_) => true,
        directoryExists: (_) => true,
      );
      addTearDown(failed.dispose);

      final failedResult = await failed.store.restore();

      expect(failedResult.status, IdeSessionRestoreStatus.failed);
      expect(failed.store.state.restoreStatus, IdeSessionRestoreStatus.failed);
    },
  );

  test('composition preserves latest save queued during restore', () async {
    final loadCompleter = Completer<IdeSessionState?>();
    final sessionStore = _FakeIdeSessionStore(loadFuture: loadCompleter.future);
    final composition = IdeSessionSliceComposition.create(
      sessionStore: sessionStore,
      saveDelay: const Duration(milliseconds: 1),
      fileExists: (_) => true,
      directoryExists: (_) => true,
    );
    addTearDown(composition.dispose);

    final restoreFuture = composition.store.restore();
    composition.store.requestSave(
      const IdeSessionState(
        workbenchLayout: IdeWorkbenchLayoutState(
          selectedAgentUsageProviderId: 'older',
        ),
      ),
    );
    composition.store.requestSave(
      const IdeSessionState(
        workbenchLayout: IdeWorkbenchLayoutState(
          selectedAgentUsageProviderId: 'latest',
        ),
      ),
    );

    loadCompleter.complete(null);
    await restoreFuture;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(sessionStore.savedSnapshots, hasLength(1));
    expect(
      sessionStore
          .savedSnapshots
          .single
          .workbenchLayout
          .selectedAgentUsageProviderId,
      'latest',
    );
  });

  test('composition forwards cancellation and saveNow semantics', () async {
    final loadCompleter = Completer<IdeSessionState?>();
    final sessionStore = _FakeIdeSessionStore(loadFuture: loadCompleter.future);
    final composition = IdeSessionSliceComposition.create(
      sessionStore: sessionStore,
      saveDelay: const Duration(milliseconds: 20),
      fileExists: (_) => true,
      directoryExists: (_) => true,
    );
    addTearDown(composition.dispose);

    final restoreFuture = composition.store.restore();
    composition.store.cancelPendingRestore();
    loadCompleter.complete(
      const IdeSessionState(projectPaths: <String>['/stale']),
    );

    expect((await restoreFuture).status, IdeSessionRestoreStatus.cancelled);

    composition.store.requestSave(
      const IdeSessionState(
        workbenchLayout: IdeWorkbenchLayoutState(
          selectedAgentUsageProviderId: 'delayed',
        ),
      ),
    );
    await composition.store.saveNow(
      const IdeSessionState(
        workbenchLayout: IdeWorkbenchLayoutState(
          selectedAgentUsageProviderId: 'now',
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(sessionStore.savedSnapshots, hasLength(1));
    expect(
      sessionStore
          .savedSnapshots
          .single
          .workbenchLayout
          .selectedAgentUsageProviderId,
      'now',
    );
  });
}

final class _FakeIdeSessionStore implements IdeSessionStore {
  _FakeIdeSessionStore({this.initialSnapshot, this.loadFuture, this.loadError});

  final IdeSessionState? initialSnapshot;
  final Future<IdeSessionState?>? loadFuture;
  final Object? loadError;
  final List<IdeSessionState> savedSnapshots = <IdeSessionState>[];

  @override
  Future<IdeSessionState?> load() async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return loadFuture ?? initialSnapshot;
  }

  @override
  Future<void> save(IdeSessionState state) async {
    savedSnapshots.add(state);
  }
}
