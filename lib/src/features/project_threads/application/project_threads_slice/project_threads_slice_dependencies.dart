import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import '../project_threads_state_owner.dart';
import 'project_threads_slice_effect.dart';
import 'project_threads_slice_state.dart';

typedef ProjectThreadsRunnerFactory =
    ProjectThreadsSliceEffectRunner Function(ProjectThreadsStateOwner owner);

abstract interface class ProjectThreadsOwnerLifecycle {
  void stopAcceptingCommandsAndSettleWaiters();
  Future<void> drainExecutions();
}

abstract interface class ProjectThreadsSliceEffectRunner {
  void run(ProjectThreadsSliceEffect effect);
  void close();
  Future<void> drainExecutions();
}

final class ProjectThreadsSliceDependencies {
  ProjectThreadsSliceDependencies({
    required this.initialState,
    DateTime Function()? now,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : now = now ?? DateTime.now,
       operationIdGeneratorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  final ProjectThreadsSliceState initialState;
  final DateTime Function() now;
  final OperationIdGenerator Function(String scope) operationIdGeneratorFactory;
}

final projectThreadsSliceDependenciesProvider =
    Provider<ProjectThreadsSliceDependencies>(
      (ref) =>
          throw StateError('Project Threads dependencies are not installed'),
      name: 'projectThreadsSliceDependencies',
    );

final projectThreadsRunnerFactoryProvider =
    Provider<ProjectThreadsRunnerFactory>(
      (ref) =>
          throw StateError('Project Threads runner factory is not installed'),
      name: 'projectThreadsRunnerFactory',
    );
