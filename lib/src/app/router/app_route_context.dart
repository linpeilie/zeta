import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/router/app_route_location.dart';

/// Widget 内读当前位置：`GoRouterState` 是 InheritedModel，与换页同帧。
extension AppRouteLocationContext on BuildContext {
  /// 最近一层路由的位置。壳内内容页用这个，避免读到压栈设置页。
  AppRouteLocation get routeLocation =>
      parseAppRouteLocation(GoRouterState.of(this).uri);

  /// 顶层位置（含根导航压栈页）。壳要判断设置是否盖住时用这个。
  AppRouteLocation get rootRouteLocation {
    final router = GoRouter.of(this);
    final configuration = router.routerDelegate.currentConfiguration;
    final uri = configuration.isEmpty
        ? router.routeInformationProvider.value.uri
        : router.state.uri;
    return parseAppRouteLocation(uri);
  }

  void goLocation(AppRouteLocation location) => go(location.toPath());

  /// 压在当前栈上。打开设置必须走这个，不能 `go`，否则会卸掉壳内内容路由。
  void pushLocation(AppRouteLocation location) {
    unawaited(push(location.toPath()));
  }

  /// 替换栈顶并复用 Page key。设置分区切换走这个，避免再压一层。
  void replaceLocation(AppRouteLocation location) {
    unawaited(GoRouter.of(this).replace(location.toPath()));
  }
}
