import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/router/restore_route_location.dart';
import 'package:zeta/src/app/router/route_reconcile_host.dart';
import 'package:zeta/src/app/router/route_reconcile_status.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';

/// 只做资源 reconcile：位置 → Shell 方法、串行化、过期检查、失败状态。
///
/// 不 import 组合根：Host / 导航端口 / provider id 由构造注入，避免与
/// `workbenchSessionProvider` / `appRouterProvider` 形成环。
final class RouterCoordinator {
  RouterCoordinator({
    required Ref ref,
    required ProjectIdMapping mapping,
    required RouteReconcileHost Function() readHost,
    required AppNavigationPort navigation,
    required Set<String> Function() readProviderIds,
  }) : this._(ref, mapping, readHost, navigation, readProviderIds);

  RouterCoordinator._(
    this._ref,
    this._mapping,
    this._readHost,
    this._navigation,
    this._readProviderIds,
  );

  final Ref _ref;
  final ProjectIdMapping _mapping;
  final RouteReconcileHost Function() _readHost;
  final AppNavigationPort _navigation;
  final Set<String> Function() _readProviderIds;

  GoRouter? _router;
  int _seq = 0;
  bool _disposed = false;
  AppRouteLocation? _settledLocation;
  final Map<int, Completer<bool>> _reconcileWaiters = <int, Completer<bool>>{};
  ProviderSubscription<bool>? _restoreSub;
  bool _restoreReplaceAttempted = false;

  static const Duration _deepLinkTimeout = Duration(seconds: 10);

  RouteReconcileHost get _host => _readHost();

  Set<String> get _providerIds => _readProviderIds();

  void attach(GoRouter router) {
    if (_disposed) {
      return;
    }
    detach();
    _router = router;
    router.routerDelegate.addListener(_onLocationChanged);
    _restoreSub = _ref.listen<bool>(
      ideSessionSliceProvider.select((state) => state.initialRestoreCompleted),
      (previous, completed) {
        if (_disposed || previous == true || !completed) {
          return;
        }
        _replaceAfterRestoreIfNeeded();
      },
    );
    if (router.routerDelegate.currentConfiguration.isNotEmpty) {
      unawaited(reconcile(parseAppRouteLocation(_routerUri(router))));
      _replaceAfterRestoreIfNeeded();
    }
  }

  void detach() {
    _restoreSub?.close();
    _restoreSub = null;
    _restoreReplaceAttempted = false;
    final router = _router;
    if (router == null) {
      return;
    }
    router.routerDelegate.removeListener(_onLocationChanged);
    _router = null;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    detach();
    _seq += 1;
    final pending = List<Completer<bool>>.of(_reconcileWaiters.values);
    _reconcileWaiters.clear();
    for (final waiter in pending) {
      waiter.complete(false);
    }
  }

  void _onLocationChanged() {
    final router = _router;
    if (_disposed || router == null) {
      return;
    }
    if (router.routerDelegate.currentConfiguration.isEmpty) {
      return;
    }
    unawaited(reconcile(parseAppRouteLocation(_routerUri(router))));
    _replaceAfterRestoreIfNeeded();
  }

  void _replaceAfterRestoreIfNeeded() {
    if (_restoreReplaceAttempted) {
      return;
    }
    final router = _router;
    if (_disposed || router == null) {
      return;
    }
    if (router.routerDelegate.currentConfiguration.isEmpty) {
      return;
    }
    if (!_ref.read(ideSessionSliceProvider).initialRestoreCompleted) {
      return;
    }
    _restoreReplaceAttempted = true;
    final current = parseAppRouteLocation(_routerUri(router));
    final canonical = _canonicalLocationAfterRestore();
    final target = restoreReplaceTarget(
      current: current,
      restoreCompleted: true,
      canonical: canonical,
    );
    if (target == null) {
      return;
    }
    _navigation.replace(target);
  }

  AppRouteLocation _canonicalLocationAfterRestore() {
    final workspace = _ref.read(workspaceProvider);
    _mapping.syncProjects(
      workspace.openProjects.map((project) => project.path),
    );
    return canonicalLocationAfterRestore(
      activeProjectPath: workspace.activeProjectPath,
      mapping: _mapping,
    );
  }

  /// 通知深链：恢复完成后再 `go` 到会话 URL，reconcile 打开资源。
  Future<bool> activateThreadFromDeepLink(
    String providerId,
    String threadId,
  ) async {
    await _host.initialRestoreDone;
    if (_disposed) {
      return false;
    }
    final projectPath = _host.projectPathForThread(
      threadId: threadId,
      providerIdHint: providerId,
    );
    if (projectPath == null) {
      return false;
    }
    var projectId = _mapping.idForPath(projectPath);
    if (projectId == null) {
      final workspace = _ref.read(workspaceProvider);
      _mapping.syncProjects(
        workspace.openProjects.map((project) => project.path),
      );
      projectId = _mapping.idForPath(projectPath);
    }
    if (projectId == null) {
      return false;
    }
    final location = ThreadLocation(projectId, threadId);
    final seqBefore = _seq;
    _navigation.go(location);
    if (_disposed) {
      return false;
    }
    if (_seq != seqBefore) {
      final waiter = _reconcileWaiters[_seq];
      if (waiter != null) {
        return waiter.future.timeout(_deepLinkTimeout, onTimeout: () => false);
      }
    }
    return reconcile(location);
  }

  /// GoRouter.state 在尚未解析首屏匹配时为空；此时读信息提供者上的 URI。
  Uri _routerUri(GoRouter router) {
    final configuration = router.routerDelegate.currentConfiguration;
    if (configuration.isEmpty) {
      return router.routeInformationProvider.value.uri;
    }
    return router.state.uri;
  }

  bool _stale(int seq) => _disposed || seq != _seq;

  /// 测试与 attach 共用：每次调用分配新 seq，进行中的 reconcile 作废。
  Future<bool> reconcile(AppRouteLocation location) {
    if (_disposed) {
      return Future<bool>.value(false);
    }
    final seq = ++_seq;
    final waiter = Completer<bool>();
    _reconcileWaiters[seq] = waiter;
    unawaited(_reconcile(location, seq));
    return waiter.future;
  }

  Future<void> _reconcile(AppRouteLocation location, int seq) async {
    final status = _ref.read(routerReconcileStatusProvider.notifier);
    try {
      if (_stale(seq)) {
        _settle(seq, false);
        return;
      }
      if (location == _settledLocation) {
        status.set(const RouteReconcileIdle());
        _settle(seq, true);
        return;
      }
      switch (location) {
        case GlobalHomeLocation():
        case SettingsLocation():
          status.set(const RouteReconcileIdle());
          _settledLocation = location;
          _settle(seq, true);
        case ProjectHomeLocation(:final projectId):
          await _openProjectHome(location, seq, projectId, status);
        case DraftThreadLocation(:final projectId, :final providerId):
          await _openDraft(location, seq, projectId, providerId, status);
        case ThreadLocation(:final projectId, :final threadId):
          await _openThread(location, seq, projectId, threadId, status);
      }
    } catch (_) {
      if (!_stale(seq)) {
        status.set(
          RouteReconcileFailed(
            location,
            RouteReconcileReason.conversationOpenFailed,
          ),
        );
        _settledLocation = null;
      }
      _settle(seq, false);
    }
  }

  Future<void> _openProjectHome(
    AppRouteLocation location,
    int seq,
    String projectId,
    RouterReconcileStatusNotifier status,
  ) async {
    status.set(RouteReconcileOpening(location));
    final path = _mapping.pathForId(projectId);
    if (path == null) {
      _navigation.go(const GlobalHomeLocation());
      if (!_stale(seq)) {
        status.set(
          RouteReconcileFailed(
            location,
            RouteReconcileReason.projectUnavailable,
          ),
        );
        _settledLocation = null;
      }
      _settle(seq, false);
      return;
    }
    if (_stale(seq)) {
      _settle(seq, false);
      return;
    }
    await _host.openProjectHomeFromRoute(path);
    if (_stale(seq)) {
      _settle(seq, false);
      return;
    }
    status.set(const RouteReconcileIdle());
    _settledLocation = location;
    _settle(seq, true);
  }

  Future<void> _openDraft(
    AppRouteLocation location,
    int seq,
    String projectId,
    String providerId,
    RouterReconcileStatusNotifier status,
  ) async {
    status.set(RouteReconcileOpening(location));
    if (!_providerIds.contains(providerId)) {
      _navigation.go(ProjectHomeLocation(projectId));
      if (!_stale(seq)) {
        status.set(
          RouteReconcileFailed(
            location,
            RouteReconcileReason.providerUnavailable,
          ),
        );
        _settledLocation = null;
      }
      _settle(seq, false);
      return;
    }
    final path = _mapping.pathForId(projectId);
    if (path == null) {
      _navigation.go(const GlobalHomeLocation());
      if (!_stale(seq)) {
        status.set(
          RouteReconcileFailed(
            location,
            RouteReconcileReason.projectUnavailable,
          ),
        );
        _settledLocation = null;
      }
      _settle(seq, false);
      return;
    }
    if (_stale(seq)) {
      _settle(seq, false);
      return;
    }
    await _host.startNewThreadForProject(path, providerId: providerId);
    if (_stale(seq)) {
      _settle(seq, false);
      return;
    }
    status.set(const RouteReconcileIdle());
    _settledLocation = location;
    _settle(seq, true);
  }

  Future<void> _openThread(
    AppRouteLocation location,
    int seq,
    String projectId,
    String threadId,
    RouterReconcileStatusNotifier status,
  ) async {
    status.set(RouteReconcileOpening(location));
    final path = _mapping.pathForId(projectId);
    if (path == null) {
      _navigation.go(const GlobalHomeLocation());
      if (!_stale(seq)) {
        status.set(
          RouteReconcileFailed(
            location,
            RouteReconcileReason.projectUnavailable,
          ),
        );
        _settledLocation = null;
      }
      _settle(seq, false);
      return;
    }
    if (_stale(seq)) {
      _settle(seq, false);
      return;
    }
    final ok = await _host.openThreadFromRoute(path, threadId);
    if (_stale(seq)) {
      _settle(seq, ok);
      return;
    }
    if (ok) {
      status.set(const RouteReconcileIdle());
      _settledLocation = location;
      _settle(seq, true);
      return;
    }
    status.set(
      RouteReconcileFailed(
        location,
        RouteReconcileReason.conversationOpenFailed,
      ),
    );
    _settledLocation = null;
    _settle(seq, false);
  }

  void _settle(int seq, bool ok) {
    _reconcileWaiters.remove(seq)?.complete(ok);
  }
}
