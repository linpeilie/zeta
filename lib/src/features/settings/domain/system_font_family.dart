import 'package:flutter/foundation.dart';

/// 操作系统字体目录中的一个字体家族。
///
/// [familyName] 是传给 Flutter 文本引擎的真实家族名，[displayName] 仅用于
/// 当前语言环境下的界面展示；二者必须分离，避免本地化名称污染持久化设置。
@immutable
class SystemFontFamily {
  const SystemFontFamily({
    required this.id,
    required this.familyName,
    required this.displayName,
    required this.aliases,
    required this.isMonospace,
  });

  /// 平台字体目录生成的稳定标识。
  final String id;

  /// Flutter 文本引擎用于匹配系统字体的家族名。
  final String familyName;

  /// 按当前系统语言解析的家族展示名。
  final String displayName;

  /// 其他本地化名称及旧版文件名，用于搜索和旧设置迁移。
  final List<String> aliases;

  /// 平台字体 API 给出的等宽属性。
  final bool isMonospace;

  /// 从平台通道的宽容响应中解析字体家族。
  static SystemFontFamily? tryDecode(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = Map<Object?, Object?>.from(raw);
    final familyName = _nonEmptyString(map['familyName']);
    if (familyName == null) {
      return null;
    }

    final displayName = _nonEmptyString(map['displayName']) ?? familyName;
    final id =
        _nonEmptyString(map['id']) ??
        'system:${familyName.trim().toLowerCase()}';
    final uniqueAliases = <String, String>{};
    for (final value in <Object?>[
      familyName,
      displayName,
      if (map['aliases'] is Iterable) ...(map['aliases'] as Iterable),
    ]) {
      final alias = _nonEmptyString(value);
      if (alias != null) {
        uniqueAliases.putIfAbsent(alias.toLowerCase(), () => alias);
      }
    }

    return SystemFontFamily(
      id: id,
      familyName: familyName,
      displayName: displayName,
      aliases: List<String>.unmodifiable(uniqueAliases.values),
      isMonospace: map['monospace'] == true,
    );
  }
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
