import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

import '../../../testing/workspace_test_bindings.dart';

void main() {
  test(
    'workspace provider publishes notifier state without a mirror store',
    () async {
      final catalog = MemoryWorkspaceDirectoryCatalog(
        existingPaths: const <String>{'/repo'},
        childrenByPath: <String, List<WorkspaceNode>>{
          '/repo': const <WorkspaceNode>[],
        },
      );
      final bindings = WorkspaceTestBindings(
        catalog: catalog,
        now: () => DateTime(2026, 8, 23),
      );
      addTearDown(bindings.dispose);

      await bindings.notifier.openOrActivate('/repo');
      expect(
        bindings.container
            .read(workspaceProvider)
            .projectLastOpenedAtByPath
            .keys,
        <String>['/repo'],
      );
      expect(
        bindings.container.read(workspaceProvider).activeProjectPath,
        '/repo',
      );
    },
  );
}
