import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/router/app_route_location.dart';

/// Widget 内读当前位置：`GoRouterState.of` 是 InheritedModel，与换页同帧。
extension AppRouteLocationRead on BuildContext {
  AppRouteLocation get routeLocation =>
      parseAppRouteLocation(GoRouterState.of(this).uri);
}

extension AppRouteNavigation on BuildContext {
  void goLocation(AppRouteLocation location) => go(location.toPath());
}
