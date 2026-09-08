import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';

/// 启动恢复完成后的落点：有活动项目则项目首页，否则全局首页。
///
/// 不自动打开上次会话。会话映射只用于之后用户点开会话；与
/// `IdeShellController` 恢复时进入项目首页、不选中旧 Thread 的语义对齐。
AppRouteLocation canonicalLocationAfterRestore({
  required String? activeProjectPath,
  required ProjectIdMapping mapping,
}) {
  if (activeProjectPath == null || activeProjectPath.isEmpty) {
    return const GlobalHomeLocation();
  }
  final projectId = mapping.idForPath(activeProjectPath);
  if (projectId == null) {
    return const GlobalHomeLocation();
  }
  return ProjectHomeLocation(projectId);
}

/// 恢复完成后是否需要显式 `replace`。
///
/// 仅当仍停在全局首页时改写；深链已先行离开 `/` 则不打扰。
AppRouteLocation? restoreReplaceTarget({
  required AppRouteLocation current,
  required bool restoreCompleted,
  required AppRouteLocation canonical,
}) {
  if (!restoreCompleted) {
    return null;
  }
  if (current is! GlobalHomeLocation) {
    return null;
  }
  if (canonical is GlobalHomeLocation) {
    return null;
  }
  return canonical;
}
