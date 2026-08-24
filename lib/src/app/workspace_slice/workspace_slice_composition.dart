import 'package:zeta/src/app/workspace_slice/workspace_slice_runner.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_effect.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_file_corpus.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_store.dart';

/// Workspace 切片组合；store 是项目与文件树业务状态的唯一 owner。
final class WorkspaceSliceComposition {
  WorkspaceSliceComposition._(this.store, this.fileCorpus);

  final WorkspaceSliceStore store;

  /// 活动工作区的 @mention 文件语料；只读端口，调用方不得知道索引实现。
  final WorkspaceFileCorpusPort fileCorpus;

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
    return WorkspaceSliceComposition._(
      store,
      WorkspaceSliceFileCorpus(
        store: store,
        fileIndexController: fileIndexController,
      ),
    );
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
