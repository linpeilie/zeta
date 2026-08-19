import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:zeta_storage/src/storage_exception.dart';

/// Zeta-owned current-schema paths below the user's home directory.
final class ZetaDataPaths {
  ZetaDataPaths._(this.rootDirectory, this._pathContext);

  /// Creates the `~/.zeta` path set from an absolute home directory.
  factory ZetaDataPaths.fromHomeDirectory(
    String homeDirectory, {
    bool? isWindows,
  }) {
    final windows = isWindows ?? Platform.isWindows;
    final context = path.Context(
      style: windows ? path.Style.windows : path.Style.posix,
    );
    final normalizedHome = context.normalize(homeDirectory.trim());
    if (homeDirectory.trim().isEmpty || !context.isAbsolute(normalizedHome)) {
      throw StoragePathException(
        path: homeDirectory,
        cause: ArgumentError.value(
          homeDirectory,
          'homeDirectory',
          'Home directory must be absolute',
        ),
      );
    }
    return ZetaDataPaths._(
      Directory(context.join(normalizedHome, '.zeta')),
      context,
    );
  }

  /// Creates the path set from platform home-directory environment variables.
  factory ZetaDataPaths.fromEnvironment({
    Map<String, String>? environment,
    bool? isWindows,
  }) {
    final windows = isWindows ?? Platform.isWindows;
    final home = resolveUserHomeDirectory(
      environment: environment ?? Platform.environment,
      isWindows: windows,
    );
    if (home == null) {
      throw StoragePathException(
        path: '',
        cause: StateError('User home directory is unavailable'),
      );
    }
    return ZetaDataPaths.fromHomeDirectory(home, isWindows: windows);
  }

  /// The `~/.zeta` root.
  final Directory rootDirectory;
  final path.Context _pathContext;

  /// Global configuration directory.
  Directory get configDirectory => Directory(_join('config'));

  /// Session state and derived-index directory.
  Directory get stateDirectory => Directory(_join('state'));

  /// Per-provider and per-thread session context directory.
  Directory get sessionStateDirectory => Directory(
    _pathContext.join(stateDirectory.path, 'session'),
  );

  /// Application log directory.
  Directory get logsDirectory => Directory(_join('logs'));

  /// Disposable, rebuildable cache directory.
  Directory get cacheDirectory => Directory(_join('cache'));

  /// Agent provider configuration file.
  File get providersFile => File(
    _pathContext.join(configDirectory.path, 'providers.json'),
  );

  /// Appearance settings file.
  File get appearanceFile => File(
    _pathContext.join(configDirectory.path, 'appearance.json'),
  );

  /// General settings file.
  File get generalSettingsFile => File(
    _pathContext.join(configDirectory.path, 'general.json'),
  );

  /// IDE session state file.
  File get ideSessionFile => File(
    _pathContext.join(stateDirectory.path, 'ide_session.json'),
  );

  /// Rebuildable usage-statistics index file.
  File get usageStatisticsIndexFile => File(
    _pathContext.join(stateDirectory.path, 'usage_statistics_index.json'),
  );

  /// Rebuildable Agent model-catalog cache file.
  File get agentModelCatalogCacheFile => File(
    _pathContext.join(cacheDirectory.path, 'agent_models_v1.json'),
  );

  /// Creates the current-schema top-level directories.
  Future<void> ensureDirectories() async {
    for (final directory in <Directory>[
      configDirectory,
      stateDirectory,
      logsDirectory,
      cacheDirectory,
    ]) {
      try {
        await directory.create(recursive: true);
      } on Object catch (error, stackTrace) {
        Error.throwWithStackTrace(
          StorageWriteException(
            operation: StorageOperation.createDirectory,
            path: directory.path,
            cause: error,
          ),
          stackTrace,
        );
      }
    }
  }

  String _join(String child) => _pathContext.join(rootDirectory.path, child);
}

/// Resolves a user home directory from explicit environment values.
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
  }
  return _nonEmpty(environment['HOME']);
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
