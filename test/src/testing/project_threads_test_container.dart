import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/project_threads_slice/project_threads_slice_composition.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_dependencies.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';

/// Container and teardown only; all business goes through the production owner.
ProviderContainer projectThreadsTestContainer({
  required ProjectThreadsSliceState initialState,
  required ProjectThreadsSliceEffectRunner effectRunner,
  DateTime Function()? now,
}) {
  final container = ProviderContainer(
    overrides: [
      projectThreadsSliceDependenciesProvider.overrideWithValue(
        ProjectThreadsSliceDependencies(initialState: initialState, now: now),
      ),
      projectThreadsRunnerFactoryProvider.overrideWithValue(
        (_) => effectRunner,
      ),
    ],
  );
  addTearDown(() => closeProjectThreadsTestContainer(container));
  return container;
}

ProviderContainer projectThreadsAppTestContainer(
  ProjectThreadsCompositionInputs inputs,
) {
  final container = ProviderContainer(
    overrides: [
      ...projectThreadsSliceOverrides(),
      projectThreadsCompositionInputsProvider.overrideWithValue(inputs),
    ],
  );
  container.read(projectThreadsSliceProvider);
  return container;
}

Future<void> closeProjectThreadsTestContainer(
  ProviderContainer container,
) async {
  final owner = container.read(projectThreadsSliceProvider.notifier);
  owner.stopAcceptingCommandsAndSettleWaiters();
  await owner.drainExecutions();
  container.dispose();
}
