import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/router/app_route_location.dart';

/// 路由页区分冷开加载与打开失败的稳定原因码。不落路径或 id（G7）。
abstract final class RouteReconcileReason {
  static const conversationOpenFailed = 'conversationOpenFailed';
  static const projectUnavailable = 'projectUnavailable';
  static const providerUnavailable = 'providerUnavailable';
}

sealed class RouteReconcileStatus {
  const RouteReconcileStatus();
}

final class RouteReconcileIdle extends RouteReconcileStatus {
  const RouteReconcileIdle();

  @override
  bool operator ==(Object other) => other is RouteReconcileIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class RouteReconcileOpening extends RouteReconcileStatus {
  const RouteReconcileOpening(this.location);

  final AppRouteLocation location;

  @override
  bool operator ==(Object other) =>
      other is RouteReconcileOpening && other.location == location;

  @override
  int get hashCode => Object.hash(runtimeType, location);
}

final class RouteReconcileFailed extends RouteReconcileStatus {
  const RouteReconcileFailed(this.location, this.reasonKey);

  final AppRouteLocation location;

  /// [RouteReconcileReason] 常量；W4 页面再映射为文案。
  final String reasonKey;

  @override
  bool operator ==(Object other) =>
      other is RouteReconcileFailed &&
      other.location == location &&
      other.reasonKey == reasonKey;

  @override
  int get hashCode => Object.hash(runtimeType, location, reasonKey);
}

final class RouterReconcileStatusNotifier
    extends Notifier<RouteReconcileStatus> {
  @override
  RouteReconcileStatus build() => const RouteReconcileIdle();

  void set(RouteReconcileStatus next) {
    if (state != next) {
      state = next;
    }
  }
}

final routerReconcileStatusProvider =
    NotifierProvider<RouterReconcileStatusNotifier, RouteReconcileStatus>(
      RouterReconcileStatusNotifier.new,
      name: 'routerReconcileStatus',
    );
