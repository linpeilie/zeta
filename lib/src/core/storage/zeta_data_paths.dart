import 'dart:io';

/// Zeta 自有数据在用户主目录下的统一路径集合。
///
/// 这里只描述 Zeta 的配置、状态、日志与缓存目录，不包含任何 Agent CLI 的
/// 配置目录或会话历史目录。
class ZetaDataPaths {
  ZetaDataPaths._(this.rootDirectory);

  /// 以指定用户主目录创建 `~/.zeta` 路径集合。
  factory ZetaDataPaths.fromHomeDirectory(
    String homeDirectory, {
    bool? isWindows,
  }) {
    final normalizedHome = homeDirectory.trim();
    final windows = isWindows ?? Platform.isWindows;
    if (normalizedHome.isEmpty || !_isAbsolutePath(normalizedHome, windows)) {
      throw ArgumentError.value(
        homeDirectory,
        'homeDirectory',
        '用户主目录必须是绝对路径。',
      );
    }
    return ZetaDataPaths._(Directory(_joinPath(normalizedHome, '.zeta')));
  }

  /// 从当前平台环境变量解析用户主目录。
  factory ZetaDataPaths.fromEnvironment({
    Map<String, String>? environment,
    bool? isWindows,
  }) {
    final values = environment ?? Platform.environment;
    final windows = isWindows ?? Platform.isWindows;
    final home = resolveUserHomeDirectory(
      environment: values,
      isWindows: windows,
    );
    if (home == null) {
      throw StateError('无法解析用户主目录，不能初始化 ~/.zeta。');
    }
    return ZetaDataPaths.fromHomeDirectory(home, isWindows: windows);
  }

  /// `~/.zeta` 根目录。
  final Directory rootDirectory;

  /// Zeta 全局配置目录。
  Directory get configDirectory =>
      Directory(_joinPath(rootDirectory.path, 'config'));

  /// Zeta 会话状态与派生索引目录。
  Directory get stateDirectory =>
      Directory(_joinPath(rootDirectory.path, 'state'));

  /// Zeta 应用日志目录。
  Directory get logsDirectory =>
      Directory(_joinPath(rootDirectory.path, 'logs'));

  /// 预留的 Zeta 缓存目录。
  Directory get cacheDirectory =>
      Directory(_joinPath(rootDirectory.path, 'cache'));

  /// 全局 Agent provider 配置文件。
  File get providersFile =>
      File(_joinPath(configDirectory.path, 'providers.json'));

  /// 全局外观设置文件。
  File get appearanceFile =>
      File(_joinPath(configDirectory.path, 'appearance.json'));

  /// 全局常规设置文件。
  File get generalSettingsFile =>
      File(_joinPath(configDirectory.path, 'general.json'));

  /// IDE 会话状态文件。
  File get ideSessionFile =>
      File(_joinPath(stateDirectory.path, 'ide_session.json'));

  /// 退役 Cursor 遗留的受保护会话索引路径；运行时不得读写。
  File get cursorSessionsFile =>
      File(_joinPath(stateDirectory.path, 'cursor_sessions.json'));

  /// 可重建的使用统计派生索引文件。
  File get usageStatisticsIndexFile =>
      File(_joinPath(stateDirectory.path, 'usage_statistics_index.json'));

  /// 一次性存储迁移完成标记文件。
  File get migrationMarkerFile =>
      File(_joinPath(stateDirectory.path, 'migration_marker.json'));

  /// 创建 Zeta 当前使用及预留的全部一级目录。
  Future<void> ensureDirectories() async {
    await Future.wait(<Future<Directory>>[
      configDirectory.create(recursive: true),
      stateDirectory.create(recursive: true),
      logsDirectory.create(recursive: true),
      cacheDirectory.create(recursive: true),
    ]);
  }
}

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

bool _isAbsolutePath(String value, bool isWindows) {
  if (isWindows) {
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
        value.startsWith(r'\\');
  }
  return value.startsWith('/');
}

String _joinPath(String parent, String child) {
  final normalized = parent.endsWith('/') || parent.endsWith('\\')
      ? parent.substring(0, parent.length - 1)
      : parent;
  return '$normalized${Platform.pathSeparator}$child';
}
