import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta/src/app/ide_session_slice/ide_session_slice_overrides.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

void main() {
  test('overrides route restored and failed results back to state', () async {
    final restoredStore = _FakeIdeSessionStore(
      initialSnapshot: const IdeSessionState(projectPaths: <String>['/repo']),
    );
    final restored = _createSlice(
      sessionStore: restoredStore,
      fileExists: (_) => true,
      directoryExists: (_) => true,
    );

    final restoredResult = await restored.restore();

    expect(restoredResult.status, IdeSessionRestoreStatus.restored);
    expect(restoredResult.snapshot?.projectPaths, <String>['/repo']);
    expect(restored.state.restoreStatus, IdeSessionRestoreStatus.restored);

    final failed = _createSlice(
      sessionStore: _FakeIdeSessionStore(loadError: StateError('fixture')),
      fileExists: (_) => true,
      directoryExists: (_) => true,
    );

    final failedResult = await failed.restore();

    expect(failedResult.status, IdeSessionRestoreStatus.failed);
    expect(failed.state.restoreStatus, IdeSessionRestoreStatus.failed);
  });

  test('overrides preserve latest save queued during restore', () async {
    final loadCompleter = Completer<IdeSessionState?>();
    final sessionStore = _FakeIdeSessionStore(loadFuture: loadCompleter.future);
    final slice = _createSlice(
      sessionStore: sessionStore,
      saveDelay: const Duration(milliseconds: 1),
      fileExists: (_) => true,
      directoryExists: (_) => true,
    );

    final restoreFuture = slice.restore();
    slice.requestSave(
      const IdeSessionState(
        workbenchLayout: IdeWorkbenchLayoutState(
          selectedAgentUsageProviderId: 'older',
        ),
      ),
    );
    slice.requestSave(
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

  test('overrides forward cancellation and saveNow semantics', () async {
    final loadCompleter = Completer<IdeSessionState?>();
    final sessionStore = _FakeIdeSessionStore(loadFuture: loadCompleter.future);
    final slice = _createSlice(
      sessionStore: sessionStore,
      saveDelay: const Duration(milliseconds: 20),
      fileExists: (_) => true,
      directoryExists: (_) => true,
    );

    final restoreFuture = slice.restore();
    slice.cancelPendingRestore();
    loadCompleter.complete(
      const IdeSessionState(projectPaths: <String>['/stale']),
    );

    expect((await restoreFuture).status, IdeSessionRestoreStatus.cancelled);

    slice.requestSave(
      const IdeSessionState(
        workbenchLayout: IdeWorkbenchLayoutState(
          selectedAgentUsageProviderId: 'delayed',
        ),
      ),
    );
    await slice.saveNow(
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

/// 按组合根的方式装配切片：容器持有所有权，`addTearDown` 只需要释放容器。
IdeSessionSliceNotifier _createSlice({
  required IdeSessionStore sessionStore,
  Duration saveDelay = const Duration(milliseconds: 1),
  bool Function(String path)? fileExists,
  bool Function(String path)? directoryExists,
}) {
  final container = ProviderContainer(
    overrides: <Override>[
      ideSessionStoreProvider.overrideWithValue(sessionStore),
      ...ideSessionSliceOverrides(
        saveDelay: saveDelay,
        fileExists: fileExists,
        directoryExists: directoryExists,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container.read(ideSessionSliceProvider.notifier);
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
