/// 按当前平台规则从环境变量中解析用户主目录。
///
/// Windows 优先使用 `USERPROFILE`，并兼容 `HOMEDRIVE` + `HOMEPATH`；
/// 其他平台使用 `HOME`。测试可显式传入平台标记，避免依赖宿主机。
String? resolveUserHomeDirectory({
  required Map<String, String> environment,
  required bool isWindows,
}) {
  if (isWindows) {
    final userProfile = _nonEmpty(environment['USERPROFILE']);
    if (userProfile != null) {
      return userProfile;
    }
    final homeDrive = _nonEmpty(environment['HOMEDRIVE']);
    final homePath = _nonEmpty(environment['HOMEPATH']);
    if (homeDrive != null && homePath != null) {
      return '$homeDrive$homePath';
    }
    return _nonEmpty(environment['HOME']);
  }
  return _nonEmpty(environment['HOME']);
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
