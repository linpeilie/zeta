import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_indexer.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

final _log = loggerFor('zeta.workspace.file_index');

/// 执行一次工作区遍历并返回扁平文件语料。
///
/// 生产默认走后台 isolate；测试可注入同步/伪实现以绕过真实 I/O 与 isolate。
typedef WorkspaceFileWalkRunner =
    Future<List<WorkspaceNode>> Function(String root);

/// 每个工作区根目录一份后台预建的文件语料缓存。
///
/// - **单飞**：同一 root 的遍历只会发起一次，重复 `index` 复用进行中的 walk。
/// - **generation 拒陈旧**：`invalidate`/新一轮 `index` 会使在途 walk 的结果失效，
///   快速切换项目 A→B 时 A 的慢 walk 不会覆盖 B 的语料。
/// - 遍历失败仅记日志，语料保持未就绪，调用方回退惰性目录树。
class WorkspaceFileIndexController {
  WorkspaceFileIndexController({WorkspaceFileWalkRunner? runWalk})
    : _runWalk = runWalk ?? _defaultRunWalk;

  final WorkspaceFileWalkRunner _runWalk;

  final Map<String, List<WorkspaceNode>> _corpora =
      <String, List<WorkspaceNode>>{};
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Map<String, int> _generations = <String, int>{};
  bool _disposed = false;

  static Future<List<WorkspaceNode>> _defaultRunWalk(String root) {
    return Isolate.run(
      () => buildWorkspaceFileCorpus(Directory(root)),
      debugName: 'zeta-workspace-file-index',
    );
  }

  /// 触发对 [root] 的（重新）索引；未就绪前 [filesFor] 返回 null。
  Future<void> index(String root) async {
    if (_disposed) {
      return;
    }
    final existing = _inFlight[root];
    if (existing != null) {
      await existing;
      return;
    }
    final generation = (_generations[root] ?? 0) + 1;
    _generations[root] = generation;
    final operation = () async {
      try {
        final files = await _runWalk(root);
        if (_disposed || (_generations[root] ?? 0) != generation) {
          return;
        }
        _corpora[root] = List<WorkspaceNode>.unmodifiable(files);
        _log.fine('Indexed workspace: $root (${files.length} files)');
      } catch (error, stackTrace) {
        _log.warning('Could not index workspace: $root', error, stackTrace);
      }
    }();
    _inFlight[root] = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlight[root], operation)) {
        _inFlight.remove(root);
      }
    }
  }

  /// 作废旧语料并让在途 walk 的结果失效（项目清除时调用）。
  void invalidate(String root) {
    _generations[root] = (_generations[root] ?? 0) + 1;
    _corpora.remove(root);
  }

  /// 就绪时返回扁平文件语料（不可变）；未就绪或已失效返回 null。
  List<WorkspaceNode>? filesFor(String root) => _corpora[root];

  /// 该 root 的语料是否已就绪。
  bool isReady(String root) => _corpora.containsKey(root);

  void dispose() {
    _disposed = true;
    _inFlight.clear();
    _corpora.clear();
    _generations.clear();
  }
}
