import 'dart:io';

import 'package:flutter/services.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';

const String systemFontCatalogChannelName = 'zeta/system_fonts';

typedef NativeFontFamilyLoader =
    Future<List<Object?>> Function(String localeName);

/// 桌面系统字体目录服务。
abstract class SystemFontCatalogService {
  Future<List<SystemFontFamily>> uiFontFamilies();

  Future<List<SystemFontFamily>> codeFontFamilies();

  /// 按真实家族名、本地化名称或旧版文件名解析字体。
  Future<SystemFontFamily?> resolveFontFamily(String name);
}

/// 基于 DirectWrite、CoreText 和 Fontconfig 的系统字体目录实现。
class DesktopSystemFontCatalogService implements SystemFontCatalogService {
  DesktopSystemFontCatalogService({
    NativeFontFamilyLoader? loader,
    String? localeName,
  }) : _loader = loader ?? _loadFromNativeChannel,
       _localeName = localeName ?? Platform.localeName;

  final NativeFontFamilyLoader _loader;
  final String _localeName;
  Future<List<SystemFontFamily>>? _fontFamiliesFuture;
  Future<List<SystemFontFamily>>? _codeFontFamiliesFuture;

  @override
  Future<List<SystemFontFamily>> uiFontFamilies() {
    return _fontFamiliesFuture ??= _loadFontFamilies();
  }

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() {
    return _codeFontFamiliesFuture ??= uiFontFamilies().then(
      (families) => List<SystemFontFamily>.unmodifiable(
        families.where((family) => family.isMonospace),
      ),
    );
  }

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final family in await uiFontFamilies()) {
      if (family.familyName.toLowerCase() == normalized ||
          family.displayName.toLowerCase() == normalized ||
          family.aliases.any((alias) => alias.toLowerCase() == normalized)) {
        return family;
      }
    }
    return null;
  }

  Future<List<SystemFontFamily>> _loadFontFamilies() async {
    final rawFamilies = await _loader(_localeName);
    final unique = <String, SystemFontFamily>{};
    for (final raw in rawFamilies) {
      final family = SystemFontFamily.tryDecode(raw);
      if (family != null) {
        unique.putIfAbsent(family.id.toLowerCase(), () => family);
      }
    }
    final values = unique.values.toList(growable: false)
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return List<SystemFontFamily>.unmodifiable(values);
  }
}

Future<List<Object?>> _loadFromNativeChannel(String localeName) async {
  const channel = MethodChannel(systemFontCatalogChannelName);
  return await channel.invokeListMethod<Object?>(
        'listFontFamilies',
        <String, Object?>{'locale': localeName},
      ) ??
      const <Object?>[];
}
