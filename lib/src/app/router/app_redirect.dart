import 'package:zeta/src/app/router/app_route_location.dart';

/// redirect 的全部同步输入。无副作用，可矩阵测试。
final class AppRouteSnapshot {
  const AppRouteSnapshot({
    required this.restoreCompleted,
    required this.projectIds,
    required this.providerIds,
  });

  /// `ideSessionSliceProvider` 的 `initialRestoreCompleted`。
  final bool restoreCompleted;

  /// [ProjectIdMapping.allIds]。
  final Set<String> projectIds;

  /// 已登记 provider id 集合。
  final Set<String> providerIds;
}

/// 返回目标 location；无需重定向返回 `null`。
/// 目标等于当前位置时必须返回 `null`，防止回路。
String? resolveAppRedirect({
  required String location,
  required AppRouteSnapshot snapshot,
}) {
  final uri = Uri.parse(location);
  final path = uri.path.isEmpty ? '/' : uri.path;
  final current = parseAppRouteLocation(uri);

  if (!snapshot.restoreCompleted) {
    return path == '/' ? null : '/';
  }

  final canonical = current.toPath();
  if (path != canonical) {
    return canonical;
  }

  String? checkProject(String projectId) =>
      snapshot.projectIds.contains(projectId) ? null : '/';

  return switch (current) {
    GlobalHomeLocation() => null,
    SettingsLocation() => null,
    ProjectHomeLocation(:final projectId) => checkProject(projectId),
    ThreadLocation(:final projectId) => checkProject(projectId),
    DraftThreadLocation(:final projectId, :final providerId) =>
      checkProject(projectId) ??
          (snapshot.providerIds.contains(providerId)
              ? null
              : ProjectHomeLocation(projectId).toPath()),
  };
}
