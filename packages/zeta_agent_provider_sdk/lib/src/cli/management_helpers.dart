import 'dart:io';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 比较常规语义化版本；无法解析时保守返回 false。
bool isNewerVersion(String candidate, String current) {
  List<int>? parse(String value) {
    final core = value.split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    if (parts.length < 3) {
      return null;
    }
    final numbers = parts.take(3).map(int.tryParse).toList();
    if (numbers.any((number) => number == null)) {
      return null;
    }
    return numbers.cast<int>();
  }

  final left = parse(candidate);
  final right = parse(current);
  if (left == null || right == null) {
    return false;
  }
  for (var index = 0; index < 3; index++) {
    if (left[index] != right[index]) {
      return left[index] > right[index];
    }
  }
  return false;
}

/// 默认遮挡常见敏感 TOML 字段的值。
String maskSensitiveConfiguration(String content) {
  final sensitive = RegExp(
    r'^(\s*(?:api[_-]?key|token|secret|password|authorization|access[_-]?token|refresh[_-]?token)\s*=\s*)([^\r\n#]+)',
    caseSensitive: false,
    multiLine: true,
  );
  final tomlMasked = content.replaceAllMapped(
    sensitive,
    (match) => '${match.group(1)}"••••••"',
  );
  final jsonSensitive = RegExp(
    r'("(?:api[_-]?key|token|secret|password|authorization|access[_-]?token|refresh[_-]?token)"\s*:\s*)"[^"]*"',
    caseSensitive: false,
  );
  return tomlMasked.replaceAllMapped(
    jsonSensitive,
    (match) => '${match.group(1)}"••••••"',
  );
}

/// 在日志进入 UI 前遮挡凭证、Authorization 值和用户目录。
String redactLogLine(String line) {
  return redactSensitiveText(
    line,
    homeDirectory: resolveUserHomeDirectory(
      environment: Platform.environment,
      isWindows: Platform.isWindows,
    ),
  );
}
