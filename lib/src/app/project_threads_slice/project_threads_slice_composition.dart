import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/project_threads_slice/project_threads_slice_runner.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_effect.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_state.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_store.dart';

/// Project Threads 页面切片组合；store 是唯一状态 owner。
final class ProjectThreadsSliceComposition {
  ProjectThreadsSliceComposition._(this.store);

  final ProjectThreadsSliceStore store;

  factory ProjectThreadsSliceComposition.create({
    required AgentProviderSettingsPort providerController,
    required AgentProviderGlobalRuntime globalRuntime,
    required AgentConversationBindingManager bindingManager,
    required AgentUiTextCatalog textCatalog,
    DateTime Function()? now,
  }) {
    final deferredRunner = _DeferredProjectThreadsSliceRunner();
    final store = ProjectThreadsSliceStore(
      initialState: ProjectThreadsSliceState(),
      effectRunner: deferredRunner,
      now: now,
    );
    final runner = ProjectThreadsSliceRunner(
      providerController: providerController,
      globalRuntime: globalRuntime,
      bindingManager: bindingManager,
      stateOwner: store,
      textCatalog: textCatalog,
    );
    deferredRunner.delegate = runner;
    runner.onActiveThreadCleared = (projectPath, threadId) {
      store.onActiveThreadCleared?.call(projectPath, threadId);
    };
    return ProjectThreadsSliceComposition._(store);
  }
}

final class _DeferredProjectThreadsSliceRunner
    implements ProjectThreadsSliceEffectRunner {
  ProjectThreadsSliceEffectRunner? delegate;

  @override
  void run(ProjectThreadsSliceEffect effect) => delegate?.run(effect);

  @override
  void close() => delegate?.close();
}
