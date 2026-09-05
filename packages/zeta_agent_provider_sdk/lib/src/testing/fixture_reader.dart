import 'dart:convert';
import 'dart:io';

String readFixtureText(String relativePath) {
  return File('test/fixtures/$relativePath').readAsStringSync();
}

Map<String, Object?> readFixtureJsonMap(String relativePath) {
  final decoded = jsonDecode(readFixtureText(relativePath));
  if (decoded is! Map) {
    throw StateError('Fixture $relativePath is not a JSON object');
  }
  return decoded.map(
    (key, value) => MapEntry(key.toString(), value as Object?),
  );
}

/// 按所属包解析测试资源，兼容包内 runner 与根目录指定包路径的 runner。
///
/// 不修改进程当前目录，避免并行测试之间相互影响；包不存在时显式失败。
final class ProviderTestFiles {
  const ProviderTestFiles(this.packageName);

  /// 在 package config 中登记的所属包名。
  final String packageName;

  /// 返回相对包根的路径；调用者只传入源码或脱敏 fixture 的固定相对位置。
  String path(String relativePath) {
    // flutter_tester 不支持 Isolate.resolvePackageUriSync；读取 runner 使用的
    // package config，同时适配 workspace 根和单包目录，不猜包的物理层级。
    var directory = Directory.current;
    while (true) {
      final config = File.fromUri(
        directory.uri.resolve('.dart_tool/package_config.json'),
      );
      if (config.existsSync()) {
        final decoded = jsonDecode(config.readAsStringSync()) as Map;
        for (final value in decoded['packages'] as List) {
          final entry = value as Map;
          if (entry['name'] != packageName) continue;
          final root = entry['rootUri'] as String;
          final rootUri = config.uri.resolve(
            root.endsWith('/') ? root : '$root/',
          );
          return rootUri.resolve(relativePath).toFilePath();
        }
        throw StateError('Cannot resolve test package $packageName');
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        throw StateError('Cannot find package config for $packageName');
      }
      directory = parent;
    }
  }

  /// 读取所属包 test/fixtures 下的脱敏文本。
  String readFixtureText(String relativePath) =>
      File(path('test/fixtures/$relativePath')).readAsStringSync();

  /// 读取 JSON object fixture；格式错误时明确失败。
  Map<String, Object?> readFixtureJsonMap(String relativePath) {
    final decoded = jsonDecode(readFixtureText(relativePath));
    if (decoded is! Map) {
      throw StateError('Fixture $relativePath is not a JSON object');
    }
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
  }
}
