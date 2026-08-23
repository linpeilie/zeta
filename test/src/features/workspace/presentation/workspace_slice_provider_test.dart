import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_effect.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_store.dart';
import 'package:zeta/src/features/workspace/presentation/workspace_slice/workspace_slice_providers.dart';

void main() {
  test(
    'Riverpod mirror publishes store state without owning its lifecycle',
    () async {
      final store = WorkspaceSliceStore(
        initialState: WorkspaceSliceState(),
        effectRunner: _NoopRunner(),
      );
      addTearDown(store.dispose);
      final container = ProviderContainer(
        overrides: [workspaceSliceStoreProvider.overrideWithValue(store)],
      );
      final subscription = container.listen(
        workspaceSliceProvider,
        (_, _) {},
        fireImmediately: true,
      );

      store.markProjectOpened('/repo', DateTime(2026, 8, 23));
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(workspaceSliceProvider).projectLastOpenedAtByPath.keys,
        <String>['/repo'],
      );

      subscription.close();
      container.dispose();
      expect(store.isClosed, isFalse);
    },
  );
}

final class _NoopRunner implements WorkspaceSliceEffectRunner {
  @override
  void run(WorkspaceSliceEffect effect) {}

  @override
  void close() {}
}
