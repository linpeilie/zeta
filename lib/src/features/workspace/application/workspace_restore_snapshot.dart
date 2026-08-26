import 'package:meta/meta.dart';

/// 从 IDE session 投影到 workspace 的白名单恢复快照。
@immutable
final class WorkspaceRestoreSnapshot {
  WorkspaceRestoreSnapshot({
    required List<String> projects,
    required this.activeProjectPath,
    required this.currentFilePath,
    required Set<String> expandedDirectoryPaths,
    required this.selectedTreePath,
    required Map<String, DateTime> projectLastOpenedAtByPath,
  }) : projects = List<String>.unmodifiable(projects),
       expandedDirectoryPaths = Set<String>.unmodifiable(
         expandedDirectoryPaths,
       ),
       projectLastOpenedAtByPath = Map<String, DateTime>.unmodifiable(
         projectLastOpenedAtByPath,
       );

  final List<String> projects;
  final String? activeProjectPath;
  final String? currentFilePath;
  final Set<String> expandedDirectoryPaths;
  final String? selectedTreePath;
  final Map<String, DateTime> projectLastOpenedAtByPath;
}
