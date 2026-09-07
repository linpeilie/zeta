import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/router/app_route_location.dart';

/// 路由尚未挂到 `ShadcnApp.router` 时的导航端口。
///
/// 调用被丢弃，避免拉起未使用的 GoRouter。W4 挂接后由
/// [appNavigationPortProvider] 换成真实实现。
final class UnmountedAppNavigationPort implements AppNavigationPort {
  const UnmountedAppNavigationPort();

  @override
  void go(AppRouteLocation location) {}

  @override
  void replace(AppRouteLocation location) {}
}

final appNavigationPortProvider = Provider<AppNavigationPort>(
  (ref) => const UnmountedAppNavigationPort(),
  name: 'appNavigationPort',
);
