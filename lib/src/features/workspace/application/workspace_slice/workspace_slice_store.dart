import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_effect.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_intent.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_reducer.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// Workspace effect 的 app 组合层执行端口。
abstract interface class WorkspaceSliceEffectRunner {
  void run(WorkspaceSliceEffect effect);

  void close();
}

/// Workspace 的纯 Dart MVI owner。
final class WorkspaceSliceStore {
  WorkspaceSliceStore({
    required WorkspaceSliceState initialState,
    required this.effectRunner,
    OperationIdGenerator Function(String scope)? operationIdGeneratorFactory,
  }) : _state = initialState,
       _generatorFactory =
           operationIdGeneratorFactory ??
           ((scope) => OperationIdGenerator(scope: scope));

  static const String _loadScope = 'workspace/load-project';
  static const String _restoreScope = 'workspace/restore';

  final WorkspaceSliceEffectRunner effectRunner;
  final OperationIdGenerator Function(String scope) _generatorFactory;
  final Map<String, OperationIdGenerator> _generators =
      <String, OperationIdGenerator>{};
  final List<void Function()> _listeners = <void Function()>[];

  WorkspaceSliceState _state;
  bool _closed = false;
  int _dispatchDepth = 0;
  bool _notificationPending = false;
  int _staleResultCount = 0;
  OperationId? _loadOperationId;
  Completer<bool>? _loadCompleter;
  OperationId? _restoreOperationId;
  Completer<bool>? _restoreCompleter;

  WorkspaceSliceState get state => _state;

  bool get isClosed => _closed;

  int get staleResultCount => _staleResultCount;

  void addListener(void Function() listener) {
    if (_closed || _listeners.contains(listener)) {
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void Function() subscribe(void Function() listener) {
    addListener(listener);
    return () => removeListener(listener);
  }

  /// 读取项目顶层；新请求会让上一请求的 Future 以 false 正常结算。
  Future<bool> loadProject(String path) {
    _ensureOpen();
    _loadCompleter?.complete(false);
    final operationId = _nextOperationId(_loadScope);
    final completer = Completer<bool>();
    _loadOperationId = operationId;
    _loadCompleter = completer;
    _dispatch(WorkspaceProjectLoadRequested(operationId, path));
    return completer.future;
  }

  /// 从已清洗的 session 白名单投影恢复 workspace。
  Future<bool> restore(WorkspaceRestoreSnapshot snapshot) {
    _ensureOpen();
    _restoreCompleter?.complete(false);
    final operationId = _nextOperationId(_restoreScope);
    final completer = Completer<bool>();
    _restoreOperationId = operationId;
    _restoreCompleter = completer;
    _dispatch(WorkspaceRestoreRequested(operationId, snapshot));
    return completer.future;
  }

  void markProjectOpened(String path, DateTime openedAt) {
    _dispatch(WorkspaceProjectOpened(path, openedAt));
  }

  bool removeProject(String path) {
    if (!_state.projects.contains(path)) {
      return false;
    }
    _dispatch(WorkspaceProjectRemoved(path));
    return true;
  }

  void clearActiveWorkspace() {
    _loadCompleter?.complete(false);
    _loadCompleter = null;
    _loadOperationId = null;
    _dispatch(const WorkspaceActiveProjectCleared());
  }

  void clearCurrentFile() {
    _dispatch(const WorkspaceCurrentFileCleared());
  }

  void setDirectoryExpanded(String path, bool expanded) {
    _dispatch(WorkspaceTreeExpansionChanged(path, expanded));
  }

  /// 返回点击前命中的节点，供 Shell 判断是否需要同步 Agent 文件上下文。
  WorkspaceNode? selectTreeNode(String path) {
    final node = WorkspaceNode.findByPath(_state.tree, path);
    _dispatch(WorkspaceTreeNodeSelected(path));
    return node;
  }

  /// app runner 回流：项目顶层读取成功。
  void projectLoadSucceeded({
    required OperationId operationId,
    required String path,
    required List<WorkspaceNode> tree,
    required DateTime openedAt,
  }) {
    final current = _state.projectLoadOperationId == operationId;
    _dispatch(
      WorkspaceProjectLoadSucceeded(
        operationId: operationId,
        path: path,
        tree: List<WorkspaceNode>.unmodifiable(tree),
        openedAt: openedAt,
      ),
    );
    _settleLoad(operationId, current);
  }

  void projectLoadFailed(
    OperationId operationId,
    Object error,
    StackTrace stackTrace,
  ) {
    final current = _state.projectLoadOperationId == operationId;
    _dispatch(WorkspaceProjectLoadFailed(operationId, error, stackTrace));
    if (!current) {
      _settleLoad(operationId, false);
      return;
    }
    final completer = _takeLoadCompleter(operationId);
    completer?.completeError(error, stackTrace);
  }

  void restoreSucceeded({
    required OperationId operationId,
    required WorkspaceRestoreSnapshot snapshot,
    required List<WorkspaceNode> tree,
    required String? selectedTreePath,
  }) {
    final current = _state.restoreOperationId == operationId;
    _dispatch(
      WorkspaceRestoreSucceeded(
        operationId: operationId,
        snapshot: snapshot,
        tree: List<WorkspaceNode>.unmodifiable(tree),
        selectedTreePath: selectedTreePath,
      ),
    );
    _settleRestore(operationId, current);
  }

  void restoreFailed(
    OperationId operationId,
    Object error,
    StackTrace stackTrace,
  ) {
    final current = _state.restoreOperationId == operationId;
    _dispatch(WorkspaceRestoreFailed(operationId, error, stackTrace));
    if (!current) {
      _settleRestore(operationId, false);
      return;
    }
    final completer = _takeRestoreCompleter(operationId);
    completer?.completeError(error, stackTrace);
  }

  void directoryLoaded(String path, List<WorkspaceNode> children) {
    _dispatch(
      WorkspaceDirectoryLoaded(
        path,
        List<WorkspaceNode>.unmodifiable(children),
      ),
    );
  }

  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _loadCompleter?.complete(false);
    _restoreCompleter?.complete(false);
    _loadCompleter = null;
    _restoreCompleter = null;
    _loadOperationId = null;
    _restoreOperationId = null;
    _listeners.clear();
    effectRunner.close();
  }

  void _dispatch(WorkspaceSliceIntent intent) {
    if (_closed) {
      return;
    }
    _dispatchDepth += 1;
    try {
      final before = _state;
      final transition = workspaceSliceReduce(before, intent);
      if (!identical(transition.state, before)) {
        _state = transition.state;
        _notificationPending = true;
      }
      for (final effect in transition.effects) {
        effectRunner.run(effect);
      }
    } finally {
      _dispatchDepth -= 1;
      if (_dispatchDepth == 0 && _notificationPending) {
        _notificationPending = false;
        _notifyListeners();
      }
    }
  }

  void _settleLoad(OperationId operationId, bool value) {
    final completer = _takeLoadCompleter(operationId);
    if (completer == null) {
      _staleResultCount += 1;
      return;
    }
    completer.complete(value);
  }

  Completer<bool>? _takeLoadCompleter(OperationId operationId) {
    if (_loadOperationId != operationId) {
      return null;
    }
    final completer = _loadCompleter;
    _loadOperationId = null;
    _loadCompleter = null;
    return completer;
  }

  void _settleRestore(OperationId operationId, bool value) {
    final completer = _takeRestoreCompleter(operationId);
    if (completer == null) {
      _staleResultCount += 1;
      return;
    }
    completer.complete(value);
  }

  Completer<bool>? _takeRestoreCompleter(OperationId operationId) {
    if (_restoreOperationId != operationId) {
      return null;
    }
    final completer = _restoreCompleter;
    _restoreOperationId = null;
    _restoreCompleter = null;
    return completer;
  }

  OperationId _nextOperationId(String scope) {
    return _generators
        .putIfAbsent(scope, () => _generatorFactory(scope))
        .next();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('WorkspaceSliceStore is closed');
    }
  }

  void _notifyListeners() {
    for (final listener in List<void Function()>.of(_listeners)) {
      if (_listeners.contains(listener)) {
        listener();
      }
    }
  }
}
