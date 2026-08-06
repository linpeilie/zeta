import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_indexer.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_rules.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

final _log = loggerFor('zeta.workspace.file_index');

/// 执行一次工作区遍历并返回扁平文件语料。
///
/// 生产默认走后台 isolate；测试可注入同步/伪实现以绕过真实 I/O 与 isolate。
typedef WorkspaceFileWalkRunner =
    Future<List<WorkspaceNode>> Function(String root);

/// 为工作区根目录创建递归文件系统事件流。
///
/// 生产默认 `Directory.watch(recursive: true)`；测试可注入受控 [Stream]。
typedef WorkspaceDirectoryWatchFactory =
    Stream<FileSystemEvent> Function(String root);

/// 每个工作区根目录一份后台预建的文件语料缓存。
///
/// - **单飞**：同一 root 的遍历只会发起一次，重复 `index` 复用进行中的 walk。
/// - **generation 拒陈旧**：`invalidate`/新一轮 `index` 会使在途 walk 的结果失效，
///   快速切换项目 A→B 时 A 的慢 walk 不会覆盖 B 的语料。
/// - **join 后补跑**：若 await 到的 walk 因 invalidate/失败/脏标记未提交最终语料，
///   后续 `index` 会重新发起 walk。
/// - **Directory.watch**：`index` 后对 root 递归监听 create/delete/move；
///   防抖后全量重扫，并经 [ChangeNotifier] 通知 @mention 等监听者。
/// - 遍历失败仅记日志，语料保持未就绪，调用方回退惰性目录树。
class WorkspaceFileIndexController extends ChangeNotifier {
  WorkspaceFileIndexController({
    WorkspaceFileWalkRunner? runWalk,
    WorkspaceDirectoryWatchFactory? watchDirectory,
    this.reindexDebounce = const Duration(milliseconds: 400),
  }) : _runWalk = runWalk ?? _defaultRunWalk,
       _watchDirectory = watchDirectory ?? _defaultWatchDirectory;

  final WorkspaceFileWalkRunner _runWalk;
  final WorkspaceDirectoryWatchFactory _watchDirectory;

  /// 文件系统结构变化后触发全量重扫的防抖间隔。
  final Duration reindexDebounce;

  final Map<String, List<WorkspaceNode>> _corpora =
      <String, List<WorkspaceNode>>{};
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Map<String, int> _generations = <String, int>{};
  final Map<String, StreamSubscription<FileSystemEvent>> _watches =
      <String, StreamSubscription<FileSystemEvent>>{};
  final Map<String, Timer> _reindexTimers = <String, Timer>{};

  /// 在途 walk 期间或防抖窗口内又收到相关 FS 事件时置位，walk 结束后再扫一轮。
  final Set<String> _dirtyRoots = <String>{};
  bool _disposed = false;

  static Future<List<WorkspaceNode>> _defaultRunWalk(String root) {
    return Isolate.run(
      () => buildWorkspaceFileCorpus(Directory(root)),
      debugName: 'zeta-workspace-file-index',
    );
  }

  static Stream<FileSystemEvent> _defaultWatchDirectory(String root) {
    return Directory(root).watch(recursive: true);
  }

  /// 触发对 [root] 的（重新）索引；未就绪前 [filesFor] 返回 null。
  ///
  /// 成功调用后会开始（或保持）对该 root 的递归目录监听。
  Future<void> index(String root) async {
    if (_disposed) {
      return;
    }
    _ensureWatching(root);

    // 单飞：先加入进行中的 walk。结束后若仍脏或未就绪，再开新一轮。
    final existing = _inFlight[root];
    if (existing != null) {
      await existing;
      if (_disposed) {
        return;
      }
      if (_dirtyRoots.contains(root) || !isReady(root)) {
        return index(root);
      }
      return;
    }

    // 开始本轮 walk 前清脏；walk 期间的新事件会再次置脏。
    _dirtyRoots.remove(root);
    final generation = (_generations[root] ?? 0) + 1;
    _generations[root] = generation;
    final operation = () async {
      try {
        final files = await _runWalk(root);
        if (_disposed || (_generations[root] ?? 0) != generation) {
          return;
        }
        final previous = _corpora[root];
        final next = List<WorkspaceNode>.unmodifiable(files);
        _corpora[root] = next;
        _log.t('Indexed workspace: $root (${files.length} files)');
        // 首次就绪，或路径集合变化时通知；无变化的重扫不打扰 UI。
        if (previous == null || !_sameFilePaths(previous, next)) {
          _notifyChanged();
        }
      } catch (error, stackTrace) {
        _log.w(
          'Could not index workspace: $root',
          error: error,
          stackTrace: stackTrace,
        );
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

    // walk 期间又有 FS 事件：防抖后补扫，避免漏掉中途创建的文件。
    if (!_disposed && _dirtyRoots.contains(root)) {
      _scheduleReindex(root);
    }
  }

  /// 作废旧语料、停止目录监听，并让在途 walk 的结果失效。
  void invalidate(String root) {
    _stopWatching(root);
    _generations[root] = (_generations[root] ?? 0) + 1;
    final hadCorpus = _corpora.remove(root) != null;
    if (hadCorpus) {
      _notifyChanged();
    }
  }

  /// 就绪时返回扁平文件语料（不可变）；未就绪或已失效返回 null。
  List<WorkspaceNode>? filesFor(String root) => _corpora[root];

  /// 该 root 的语料是否已就绪。
  bool isReady(String root) => _corpora.containsKey(root);

  void _ensureWatching(String root) {
    if (_disposed || _watches.containsKey(root)) {
      return;
    }
    try {
      final stream = _watchDirectory(root);
      _watches[root] = stream.listen(
        (event) => _handleWatchEvent(root, event),
        onError: (Object error, StackTrace stackTrace) {
          _log.w(
            'Workspace watch error: $root',
            error: error,
            stackTrace: stackTrace,
          );
        },
        cancelOnError: false,
      );
      _log.t('Watching workspace for file-index: $root');
    } catch (error, stackTrace) {
      _log.w(
        'Could not watch workspace: $root',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _stopWatching(String root) {
    final subscription = _watches.remove(root);
    unawaited(subscription?.cancel());
    _reindexTimers.remove(root)?.cancel();
    _dirtyRoots.remove(root);
  }

  void _handleWatchEvent(String root, FileSystemEvent event) {
    if (_disposed) {
      return;
    }
    if (!_isStructuralWatchEvent(event)) {
      return;
    }
    // 源路径落在忽略树内则跳过；move 出忽略树/改名仍以源 path 判定噪声。
    if (_isIgnoredWatchPath(event.path)) {
      return;
    }
    _dirtyRoots.add(root);
    _scheduleReindex(root);
  }

  void _scheduleReindex(String root) {
    _reindexTimers[root]?.cancel();
    _reindexTimers[root] = Timer(reindexDebounce, () {
      _reindexTimers.remove(root);
      if (_disposed || !_dirtyRoots.contains(root)) {
        return;
      }
      unawaited(index(root));
    });
  }

  /// 仅结构变化会改 mention 文件列表；纯内容 modify 忽略。
  static bool _isStructuralWatchEvent(FileSystemEvent event) {
    return event is FileSystemCreateEvent ||
        event is FileSystemDeleteEvent ||
        event is FileSystemMoveEvent;
  }

  /// 路径任一路径段落在 Zeta 硬编码忽略名中则跳过（降低 build/node_modules 噪声）。
  static bool _isIgnoredWatchPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty) {
        continue;
      }
      if (isIgnoredWorkspaceEntryName(segment)) {
        return true;
      }
    }
    return false;
  }

  static bool _sameFilePaths(
    List<WorkspaceNode> previous,
    List<WorkspaceNode> next,
  ) {
    if (previous.length != next.length) {
      return false;
    }
    // 顺序由 DFS 决定；长度相同且逐 path 相等即视为未变。
    for (var i = 0; i < previous.length; i++) {
      if (previous[i].path != next[i].path) {
        return false;
      }
    }
    return true;
  }

  void _notifyChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _reindexTimers.values) {
      timer.cancel();
    }
    _reindexTimers.clear();
    for (final subscription in _watches.values) {
      unawaited(subscription.cancel());
    }
    _watches.clear();
    _dirtyRoots.clear();
    _inFlight.clear();
    _corpora.clear();
    _generations.clear();
    super.dispose();
  }
}
