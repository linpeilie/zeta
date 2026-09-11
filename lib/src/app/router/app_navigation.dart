import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/router/app_route_location.dart';

/// 导航请求只等待实际提交，不提前执行目标页的资源副作用。
final class MountableAppNavigationPort implements AppNavigationPort {
  GoRouter? _router;
  _NavigationRequest? _pending;

  void attach(GoRouter router) {
    detach();
    _router = router;
    router.routerDelegate.addListener(_onCommitted);
    router.routeInformationProvider.addListener(_onRequested);
  }

  void detach() {
    _router?.routerDelegate.removeListener(_onCommitted);
    _router?.routeInformationProvider.removeListener(_onRequested);
    _router = null;
    _finish(NavigationOutcome.unavailable);
  }

  @override
  void go(AppRouteLocation location) {
    final router = _router;
    if (router == null) throw StateError('Navigation is not attached');
    router.go(location.toPath());
  }

  @override
  void replace(AppRouteLocation location) {
    final router = _router;
    if (router == null) throw StateError('Navigation is not attached');
    unawaited(router.replace(location.toPath()));
  }

  @override
  Future<NavigationOutcome> navigateTo(AppRouteLocation location) {
    _finish(NavigationOutcome.superseded);
    final router = _router;
    if (router == null) return Future.value(NavigationOutcome.unavailable);
    if (router.routerDelegate.currentConfiguration.isNotEmpty &&
        parseAppRouteLocation(router.state.uri) == location) {
      router.go(location.toPath());
      return Future.value(NavigationOutcome.reached);
    }
    final request = _NavigationRequest(location);
    _pending = request;
    request.timer = Timer(const Duration(seconds: 10), () {
      if (identical(_pending, request)) _finish(NavigationOutcome.timedOut);
    });
    router.go(location.toPath());
    return request.completer.future;
  }

  /// 冻结本次拦截对应的请求；迟到确认不能批准或拒绝另一条导航。
  Future<bool> confirmExit(Future<bool> Function() confirm) async {
    final router = _router;
    final information = router?.routeInformationProvider.value;
    final request = _pending;
    final allowed = await confirm();
    if (router != _router ||
        information != router?.routeInformationProvider.value ||
        (request != null && !identical(request, _pending))) {
      return false;
    }
    if (!allowed && identical(request, _pending)) {
      _finish(NavigationOutcome.blocked);
    }
    return allowed;
  }

  void _onRequested() {
    final pending = _pending;
    final router = _router;
    if (pending != null &&
        router != null &&
        parseAppRouteLocation(router.routeInformationProvider.value.uri) !=
            pending.target) {
      _finish(NavigationOutcome.superseded);
    }
  }

  void _onCommitted() {
    final pending = _pending;
    final router = _router;
    if (pending == null ||
        router == null ||
        router.routerDelegate.currentConfiguration.isEmpty) {
      return;
    }
    _finish(
      parseAppRouteLocation(router.state.uri) == pending.target
          ? NavigationOutcome.reached
          : NavigationOutcome.superseded,
    );
  }

  void _finish(NavigationOutcome outcome) {
    final pending = _pending;
    _pending = null;
    pending?.timer?.cancel();
    pending?.completer.complete(outcome);
  }
}

final class _NavigationRequest {
  _NavigationRequest(this.target);
  final AppRouteLocation target;
  final completer = Completer<NavigationOutcome>();
  Timer? timer;
}

final appNavigationPortProvider = Provider<AppNavigationPort>((ref) {
  final navigation = MountableAppNavigationPort();
  ref.onDispose(navigation.detach);
  return navigation;
}, name: 'appNavigationPort');
