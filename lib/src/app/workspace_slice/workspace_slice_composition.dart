import 'package:zeta/src/app/workspace_slice/workspace_slice_runner.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_effect.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_store.dart';

/// Workspace 切片组合；store 是 flag 开启路径的唯一业务状态 owner。
final class WorkspaceSliceComposition {
  WorkspaceSliceComposition._(this.store);

  final WorkspaceSliceStore store;

  factory WorkspaceSliceComposition.create({
    required WorkspaceFileIndexController fileIndexController,
    DateTime Function()? now,
  }) {
    final deferredRunner = _DeferredWorkspaceSliceRunner();
    final store = WorkspaceSliceStore(
      initialState: WorkspaceSliceState(),
      effectRunner: deferredRunner,
    );
    deferredRunner.delegate = WorkspaceSliceRunner(
      store,
      fileIndexController,
      now: now,
    );
    return WorkspaceSliceComposition._(store);
  }

  void dispose() => store.dispose();
}

final class _DeferredWorkspaceSliceRunner
    implements WorkspaceSliceEffectRunner {
  WorkspaceSliceEffectRunner? delegate;

  @override
  void run(WorkspaceSliceEffect effect) => delegate?.run(effect);

  @override
  void close() => delegate?.close();
}
