import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/router/app_route_location.dart';

/// 可在 GoRouter 挂接后转发 `go` / `replace` 的导航端口。
///
/// 未 [attach] 时调用丢弃，避免拉起尚未存在的路由器。
final class MountableAppNavigationPort implements AppNavigationPort {
  GoRouter? _router;

  void attach(GoRouter router) {
    _router = router;
  }

  void detach() {
    _router = null;
  }

  @override
  void go(AppRouteLocation location) {
    _router?.go(location.toPath());
  }

  @override
  void replace(AppRouteLocation location) {
    _router?.replace(location.toPath());
  }
}

final appNavigationPortProvider = Provider<AppNavigationPort>(
  (ref) => MountableAppNavigationPort(),
  name: 'appNavigationPort',
);
