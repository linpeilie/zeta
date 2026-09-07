import 'package:zeta/src/features/settings/domain/settings_section.dart';

/// URL 路径参数允许的字符集（[开发者指南 §8]）。
final _routeIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

bool _isRouteId(String value) => _routeIdPattern.hasMatch(value);

/// URL 是位置唯一真源。本文件是 URL ↔ 位置对象的唯一编解码点。
///
/// 本库不 import `go_router`：application 只依赖位置对象与
/// [AppNavigationPort]，由组合根接上 GoRouter。
sealed class AppRouteLocation {
  const AppRouteLocation();

  String toPath();
}

final class GlobalHomeLocation extends AppRouteLocation {
  const GlobalHomeLocation();

  @override
  String toPath() => '/';

  @override
  bool operator ==(Object other) => other is GlobalHomeLocation;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class ProjectHomeLocation extends AppRouteLocation {
  const ProjectHomeLocation(this.projectId);

  final String projectId;

  @override
  String toPath() => '/project/$projectId';

  @override
  bool operator ==(Object other) =>
      other is ProjectHomeLocation && other.projectId == projectId;

  @override
  int get hashCode => Object.hash(runtimeType, projectId);
}

/// 草稿会话：身份 = project+provider（`ensureDraftEntry` 去重粒度）。
final class DraftThreadLocation extends AppRouteLocation {
  const DraftThreadLocation(this.projectId, this.providerId);

  final String projectId;
  final String providerId;

  @override
  String toPath() => '/project/$projectId/draft/$providerId';

  @override
  bool operator ==(Object other) =>
      other is DraftThreadLocation &&
      other.projectId == projectId &&
      other.providerId == providerId;

  @override
  int get hashCode => Object.hash(runtimeType, projectId, providerId);
}

final class ThreadLocation extends AppRouteLocation {
  const ThreadLocation(this.projectId, this.threadId);

  final String projectId;
  final String threadId;

  @override
  String toPath() => '/project/$projectId/thread/$threadId';

  @override
  bool operator ==(Object other) =>
      other is ThreadLocation &&
      other.projectId == projectId &&
      other.threadId == threadId;

  @override
  int get hashCode => Object.hash(runtimeType, projectId, threadId);
}

final class SettingsLocation extends AppRouteLocation {
  const SettingsLocation(this.section);

  final SettingsSection section;

  @override
  String toPath() => '/settings/${section.name}';

  @override
  bool operator ==(Object other) =>
      other is SettingsLocation && other.section == section;

  @override
  int get hashCode => Object.hash(runtimeType, section);
}

/// 解析入口：路由 builder、redirect、coordinator 共用。
/// 非法或缺失参数回落到合法位置对象，不抛异常。
AppRouteLocation parseAppRouteLocation(Uri uri) {
  final segs = uri.pathSegments;
  if (segs.isEmpty) {
    return const GlobalHomeLocation();
  }
  if (segs[0] == 'settings') {
    final name = segs.length > 1 ? segs[1] : SettingsSection.general.name;
    final section = SettingsSection.values.asNameMap()[name];
    return SettingsLocation(section ?? SettingsSection.general);
  }
  if (segs[0] == 'project' && segs.length >= 2) {
    final projectId = segs[1];
    if (!_isRouteId(projectId)) {
      return const GlobalHomeLocation();
    }
    if (segs.length == 2) {
      return ProjectHomeLocation(projectId);
    }
    if (segs.length == 4 && segs[2] == 'draft') {
      final providerId = segs[3];
      if (!_isRouteId(providerId)) {
        return ProjectHomeLocation(projectId);
      }
      return DraftThreadLocation(projectId, providerId);
    }
    if (segs.length == 4 && segs[2] == 'thread') {
      final threadId = segs[3];
      if (!_isRouteId(threadId)) {
        return ProjectHomeLocation(projectId);
      }
      return ThreadLocation(projectId, threadId);
    }
  }
  return const GlobalHomeLocation();
}

/// 非 widget 层的导航出口。组合根用 GoRouter 装配；app 层对象只依赖本端口。
abstract interface class AppNavigationPort {
  void go(AppRouteLocation location);

  void replace(AppRouteLocation location);
}
