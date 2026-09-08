import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/app/router/app_navigation.dart';
import 'package:zeta/src/app/router/app_redirect.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/app_routes.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/router/registered_provider_ids.dart';
import 'package:zeta/src/app/router/route_refresh_bridge.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';

/// GoRouter 单例。plain Provider，非 autoDispose；任何路径不得重建该实例。
///
/// `ShadcnApp.router` 是根上唯一合法的 `watch`。redirect 只 `ref.read`。
/// NavigatorKey 跟 Router 实例走，禁止顶层全局 key，以免测试重挂第二棵树时串位。
final appRouterProvider = Provider<GoRouter>(
  (ref) {
    final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
    final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');
    final mapping = ref.read(projectIdMappingProvider);
    final bridge = AppRouteRefreshBridge(ref: ref, mapping: mapping);
    final navigation = ref.read(appNavigationPortProvider);
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: const GlobalHomeLocation().toPath(),
      refreshListenable: bridge,
      redirectLimit: 5,
      redirect: (context, state) {
        return resolveAppRedirect(
          location: state.uri.toString(),
          snapshot: AppRouteSnapshot(
            restoreCompleted: ref
                .read(ideSessionSliceProvider)
                .initialRestoreCompleted,
            projectIds: mapping.allIds,
            providerIds: ref.read(registeredProviderIdsProvider),
          ),
        );
      },
      routes: buildAppRoutes(
        rootNavigatorKey: rootNavigatorKey,
        shellNavigatorKey: shellNavigatorKey,
      ),
    );
    if (navigation is MountableAppNavigationPort) {
      navigation.attach(router);
    }
    final coordinator = ref.read(routerCoordinatorProvider);
    coordinator.attach(router);
    ref.onDispose(() {
      coordinator.detach();
      if (navigation is MountableAppNavigationPort) {
        navigation.detach();
      }
      router.dispose();
      bridge.dispose();
    });
    return router;
  },
  name: 'appRouter',
  dependencies: [ideSessionSliceProvider, routerCoordinatorProvider],
);
