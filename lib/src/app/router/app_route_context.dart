import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/router/app_route_location.dart';

/// Widget 内读当前位置：`GoRouterState` 是 InheritedModel，与换页同帧。
extension AppRouteLocationContext on BuildContext {
  AppRouteLocation get routeLocation =>
      parseAppRouteLocation(GoRouterState.of(this).uri);

  void goLocation(AppRouteLocation location) => go(location.toPath());
}
