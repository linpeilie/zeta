import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/app/router/app_redirect.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/app_routes.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/router/registered_provider_ids.dart';
import 'package:zeta/src/app/router/route_refresh_bridge.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

/// GoRouter 单例。plain Provider，非 autoDispose；任何路径不得重建该实例。
///
/// 本步尚未接入 `ShadcnApp.router`（W4）。redirect 只 `ref.read`。
final appRouterProvider = Provider<GoRouter>((ref) {
  final mapping = ref.read(projectIdMappingProvider);
  final bridge = AppRouteRefreshBridge(ref: ref, mapping: mapping);
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
  final coordinator = ref.read(routerCoordinatorProvider);
  coordinator.attach(router);
  ref.onDispose(() {
    coordinator.detach();
    router.dispose();
    bridge.dispose();
  });
  return router;
}, name: 'appRouter');
