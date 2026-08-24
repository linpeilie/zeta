import 'package:path_provider/path_provider.dart';

/// 提供 Zeta 运行所需的用户目录路径。
///
/// 目录由 Flutter 的 [path_provider] 负责按宿主平台解析；调用方不需要再
/// 读取 `HOME`、`USERPROFILE` 等环境变量。
abstract final class ZetaUserDirectory {
  /// 返回当前用户的应用文档目录路径。
  static Future<String> getUserDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
}
