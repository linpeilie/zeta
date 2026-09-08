import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';
import 'package:zeta/src/features/workspace/domain/workspace_project.dart';

/// 单输入 refresh 桥：只在打开项目集合变化时重估 redirect。
///
/// 同时承担 [ProjectIdMapping] 的同步。恢复完成标记不作为监听源。
final class AppRouteRefreshBridge extends ChangeNotifier {
  AppRouteRefreshBridge({required Ref ref, required this.mapping}) {
    mapping.syncProjects(_openPaths(ref.read(workspaceProvider)));
    _sub = ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
      final prev = previous == null ? const <String>{} : _openPaths(previous);
      final curr = _openPaths(next);
      if (prev.length == curr.length && prev.containsAll(curr)) {
        return;
      }
      mapping.syncProjects(curr);
      notifyListeners();
    });
  }

  static Set<String> _openPaths(WorkspaceState state) =>
      state.openProjects.map((project) => project.path).toSet();

  final ProjectIdMapping mapping;
  late final ProviderSubscription<WorkspaceState> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
