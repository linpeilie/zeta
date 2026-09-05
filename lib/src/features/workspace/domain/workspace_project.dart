import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 规范化项目根路径：trim，并去掉尾部分隔符（根路径除外）。
///
/// 不 resolve symlink，以免 session 恢复对不上选择器返回的身份。
String normalizeWorkspaceProjectPath(String path) {
  var value = path.trim();
  if (value.isEmpty) {
    return value;
  }
  while (value.length > 1 && (value.endsWith('/') || value.endsWith('\\'))) {
    final withoutTrailing = value.substring(0, value.length - 1);
    if (withoutTrailing.length == 2 && withoutTrailing.endsWith(':')) {
      break;
    }
    value = withoutTrailing;
  }
  return value;
}

/// 从路径最后一段派生展示名。
String workspaceProjectNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return path;
  }
  return parts.last;
}

/// 工作区中的一个已打开项目。
///
/// [path] 是唯一标识；[name] 由文件夹名派生，不落盘、不可用户改。
@immutable
final class WorkspaceProject {
  const WorkspaceProject({required this.path, required this.name});

  factory WorkspaceProject.fromPath(String path) {
    final normalized = normalizeWorkspaceProjectPath(path);
    return WorkspaceProject(
      path: normalized,
      name: workspaceProjectNameFromPath(normalized),
    );
  }

  /// 目录选择器返回的绝对路径（已规范化）。
  final String path;

  /// 展示名，通常是 path 最后一段。
  final String name;

  @override
  bool operator ==(Object other) {
    return other is WorkspaceProject &&
        other.path == path &&
        other.name == name;
  }

  @override
  int get hashCode => Object.hash(path, name);
}

/// 工作区调度状态：打开的项目集合与当前激活项目。
///
/// 文件树不在这里；每个项目的树由 `workspaceFileTreeProvider(path)` 持有。
@immutable
final class WorkspaceState {
  WorkspaceState({
    List<WorkspaceProject> openProjects = const <WorkspaceProject>[],
    this.activeProjectPath,
    Map<String, DateTime> projectLastOpenedAtByPath =
        const <String, DateTime>{},
  }) : openProjects = List<WorkspaceProject>.unmodifiable(openProjects),
       projectLastOpenedAtByPath = Map<String, DateTime>.unmodifiable(
         projectLastOpenedAtByPath,
       );

  /// 有序列表，path 唯一。新打开的项目插到最前。
  final List<WorkspaceProject> openProjects;

  /// 当前激活项目；必须属于 [openProjects]，或为 null（首页）。
  final String? activeProjectPath;

  /// 供首页 MRU 排序。
  final Map<String, DateTime> projectLastOpenedAtByPath;

  /// 打开项目的路径列表（session / Shell 兼容投影）。
  List<String> get projectPaths => <String>[
    for (final project in openProjects) project.path,
  ];

  WorkspaceProject? get activeProject {
    final path = activeProjectPath;
    if (path == null) {
      return null;
    }
    for (final project in openProjects) {
      if (project.path == path) {
        return project;
      }
    }
    return null;
  }

  bool containsPath(String path) {
    for (final project in openProjects) {
      if (project.path == path) {
        return true;
      }
    }
    return false;
  }

  WorkspaceState copyWith({
    List<WorkspaceProject>? openProjects,
    String? activeProjectPath,
    bool clearActiveProjectPath = false,
    Map<String, DateTime>? projectLastOpenedAtByPath,
  }) {
    return WorkspaceState(
      openProjects: openProjects ?? this.openProjects,
      activeProjectPath: clearActiveProjectPath
          ? null
          : activeProjectPath ?? this.activeProjectPath,
      projectLastOpenedAtByPath:
          projectLastOpenedAtByPath ?? this.projectLastOpenedAtByPath,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceState &&
        zetaListEquals(other.openProjects, openProjects) &&
        other.activeProjectPath == activeProjectPath &&
        zetaMapEquals(
          other.projectLastOpenedAtByPath,
          projectLastOpenedAtByPath,
        );
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(openProjects),
    activeProjectPath,
    Object.hashAll(
      projectLastOpenedAtByPath.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}
