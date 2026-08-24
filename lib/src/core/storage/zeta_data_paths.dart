/// Zeta 自有数据在用户主目录下的统一路径集合（纯路径描述，无本机 IO）。
///
/// 这里只描述 Zeta 的配置、状态、日志与缓存目录，不包含任何 Agent CLI 的
/// 配置目录或会话历史目录。目录创建、文件读写等宿主 IO 由 app 组合层完成；
/// 平台差异（路径分隔符、环境变量）由调用方显式传入。
class ZetaDataPaths {
  ZetaDataPaths._(this.rootPath, this._isWindows);

  /// 以指定用户主目录创建 `~/.zeta` 路径集合。
  factory ZetaDataPaths.fromHomeDirectory(
    String homeDirectory, {
    required bool isWindows,
  }) {
    final normalizedHome = homeDirectory.trim();
    if (normalizedHome.isEmpty || !_isAbsolutePath(normalizedHome, isWindows)) {
      throw ArgumentError.value(
        homeDirectory,
        'homeDirectory',
        '用户主目录必须是绝对路径。',
      );
    }
    return ZetaDataPaths._(
      _joinPath(normalizedHome, '.zeta', isWindows),
      isWindows,
    );
  }

  /// 按平台规则从给定环境变量解析用户主目录并创建路径集合。
  ///
  /// 环境变量与平台标记必须由调用方显式传入（宿主侧读取 `Platform`），
  /// 本类因此保持纯 Dart、可在任何测试环境构造。
  factory ZetaDataPaths.fromEnvironment({
    required Map<String, String> environment,
    required bool isWindows,
  }) {
    final home = resolveUserHomeDirectory(
      environment: environment,
      isWindows: isWindows,
    );
    if (home == null) {
      throw StateError('无法解析用户主目录，不能初始化 ~/.zeta。');
    }
    return ZetaDataPaths.fromHomeDirectory(home, isWindows: isWindows);
  }

  /// `~/.zeta` 根目录路径。
  final String rootPath;

  final bool _isWindows;

  /// Zeta 全局配置目录路径。
  String get configDirectoryPath => _joinPath(rootPath, 'config', _isWindows);

  /// Zeta 会话状态与派生索引目录路径。
  String get stateDirectoryPath => _joinPath(rootPath, 'state', _isWindows);

  /// Zeta 发起 turn 时记录的会话上下文根目录路径。
  ///
  /// 实际文件为 `state/session/<providerId>/<threadId>.json`，子目录在首次
  /// 写入时创建。
  String get sessionStateDirectoryPath =>
      _joinPath(stateDirectoryPath, 'session', _isWindows);

  /// Zeta 应用日志目录路径。
  String get logsDirectoryPath => _joinPath(rootPath, 'logs', _isWindows);

  /// 预留的 Zeta 缓存目录路径。
  String get cacheDirectoryPath => _joinPath(rootPath, 'cache', _isWindows);

  /// 全局 Agent provider 配置文件路径。
  String get providersFilePath =>
      _joinPath(configDirectoryPath, 'providers.json', _isWindows);

  /// 全局外观设置文件路径。
  String get appearanceFilePath =>
      _joinPath(configDirectoryPath, 'appearance.json', _isWindows);

  /// 全局常规设置文件路径。
  String get generalSettingsFilePath =>
      _joinPath(configDirectoryPath, 'general.json', _isWindows);

  /// IDE 会话状态文件路径。
  String get ideSessionFilePath =>
      _joinPath(stateDirectoryPath, 'ide_session.json', _isWindows);

  /// 可重建的使用统计派生索引文件路径。
  String get usageStatisticsIndexFilePath =>
      _joinPath(stateDirectoryPath, 'usage_statistics_index.json', _isWindows);

  /// 可丢弃、可重建的 Agent 模型目录缓存文件路径。
  String get agentModelCatalogCacheFilePath =>
      _joinPath(cacheDirectoryPath, 'agent_models_v1.json', _isWindows);
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

String _joinPath(String parent, String child, bool isWindows) {
  final normalized = parent.endsWith('/') || parent.endsWith('\\')
      ? parent.substring(0, parent.length - 1)
      : parent;
  final separator = isWindows ? r'\' : '/';
  return '$normalized$separator$child';
}
