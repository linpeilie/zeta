import 'dart:io';

import 'package:zeta/src/core/storage/zeta_data_paths.dart';

/// 确保 [ZetaDataPaths] 描述的一级目录全部存在。
///
/// `~/.zeta` 路径集合本身是纯路径描述（core）；目录创建属于宿主 IO，
/// 由 app 组合层在启动引导时执行。
Future<void> ensureZetaDataDirectories(ZetaDataPaths paths) async {
  await Future.wait(<Future<Directory>>[
    Directory(paths.configDirectoryPath).create(recursive: true),
    Directory(paths.stateDirectoryPath).create(recursive: true),
    Directory(paths.logsDirectoryPath).create(recursive: true),
    Directory(paths.cacheDirectoryPath).create(recursive: true),
  ]);
}
