import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/router/route_refresh_bridge.dart';
import '../../testing/workspace_test_bindings.dart';

final _bridgeProvider = Provider<AppRouteRefreshBridge>((ref) {
  final mapping = ref.read(projectIdMappingProvider);
  final bridge = AppRouteRefreshBridge(ref: ref, mapping: mapping);
  ref.onDispose(bridge.dispose);
  return bridge;
});

void main() {
  test(
    'refresh bridge notifies only when the open project set changes',
    () async {
      final catalog = MemoryWorkspaceDirectoryCatalog(
        existingPaths: const <String>{'/alpha', '/beta'},
      );
      final bindings = WorkspaceTestBindings(catalog: catalog);
      addTearDown(bindings.dispose);

      final mapping = bindings.container.read(projectIdMappingProvider);
      final bridge = bindings.container.read(_bridgeProvider);
      var notifies = 0;
      bridge.addListener(() => notifies += 1);

      expect(await bindings.notifier.openOrActivate('/alpha'), isTrue);
      expect(notifies, 1);
      expect(mapping.idForPath('/alpha'), isNotNull);

      bindings.notifier.markProjectOpened('/alpha', DateTime(2026, 9, 7));
      bindings.notifier.clearActiveProject();
      expect(notifies, 1, reason: '非 openProjects 集合变化不得 notify');

      expect(await bindings.notifier.openOrActivate('/beta'), isTrue);
      expect(notifies, 2);
      expect(mapping.idForPath('/beta'), isNotNull);

      expect(await bindings.notifier.selectProject('/alpha'), isTrue);
      expect(notifies, 2, reason: '已打开项目之间切换不得 notify');

      expect(bindings.notifier.removeProject('/beta'), isTrue);
      expect(notifies, 3);
      expect(mapping.idForPath('/beta'), isNull);
    },
  );
}
