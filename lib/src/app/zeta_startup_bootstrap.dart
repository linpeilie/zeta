import 'package:zeta/src/app/storage/zeta_data_file_system.dart';
import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';

/// 启动阶段准备 Zeta 文件持久化的可观察结果。
class ZetaStartupBootstrapResult {
  const ZetaStartupBootstrapResult({required this.filePersistenceEnabled});

  /// 本次是否可以使用 `~/.zeta` 文件持久化。
  final bool filePersistenceEnabled;
}

/// 准备 Zeta 文件持久化目录。
class ZetaStartupBootstrap {
  ZetaStartupBootstrap({required this.paths});

  final ZetaDataPaths paths;

  Future<ZetaStartupBootstrapResult> run() async {
    try {
      await ensureZetaDataDirectories(paths);
      return ZetaStartupBootstrapResult(filePersistenceEnabled: true);
    } catch (error, stackTrace) {
      loggerFor('zeta.storage').w(
        'Could not prepare the Zeta data directory',
        error: error,
        stackTrace: stackTrace,
      );
      return ZetaStartupBootstrapResult(filePersistenceEnabled: false);
    }
  }
}
