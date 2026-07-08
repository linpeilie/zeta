import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:system_fonts/system_fonts.dart';

/// 桌面系统字体目录服务。
abstract class SystemFontCatalogService {
  Future<List<String>> uiFontFamilies();

  Future<List<String>> codeFontFamilies();

  Future<bool> ensureFontLoaded(String fontFamily);
}

/// 基于 `system_fonts` 的系统字体目录实现。
class DesktopSystemFontCatalogService implements SystemFontCatalogService {
  DesktopSystemFontCatalogService({
    SystemFonts? systemFonts,
    this.measurementText = 'iIl1WMmw0O._-',
    this.fontSize = 20,
    this.widthTolerance = 0.01,
  }) : _systemFonts = systemFonts ?? SystemFonts();

  final SystemFonts _systemFonts;
  final String measurementText;
  final double fontSize;
  final double widthTolerance;
  final Set<String> _loadedFonts = <String>{};
  final Map<String, bool> _monospaceCache = <String, bool>{};
  Future<List<String>>? _uiFontFamiliesFuture;
  Future<List<String>>? _codeFontFamiliesFuture;

  @override
  Future<List<String>> uiFontFamilies() {
    return _uiFontFamiliesFuture ??= Future<List<String>>.value(
      _sortedFontFamilies(),
    );
  }

  @override
  Future<List<String>> codeFontFamilies() {
    return _codeFontFamiliesFuture ??= _computeCodeFontFamilies();
  }

  @override
  Future<bool> ensureFontLoaded(String fontFamily) async {
    if (_loadedFonts.contains(fontFamily)) {
      return true;
    }
    final path = _systemFonts.getFontMap()[fontFamily];
    if (path == null || !File(path).existsSync()) {
      return false;
    }

    try {
      final bytes = await File(path).readAsBytes();
      final loader = FontLoader(fontFamily)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loadedFonts.add(fontFamily);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> _computeCodeFontFamilies() async {
    final candidates = await uiFontFamilies();
    final monospaceFonts = <String>[];
    for (final fontFamily in candidates) {
      final cached = _monospaceCache[fontFamily];
      if (cached == true) {
        monospaceFonts.add(fontFamily);
        continue;
      }
      if (cached == false) {
        continue;
      }
      final isMonospace = await _isMonospace(fontFamily);
      _monospaceCache[fontFamily] = isMonospace;
      if (isMonospace) {
        monospaceFonts.add(fontFamily);
      }
    }
    return monospaceFonts;
  }

  Future<bool> _isMonospace(String fontFamily) async {
    if (!await ensureFontLoaded(fontFamily)) {
      return false;
    }

    final widths = measurementText
        .split('')
        .map((character) {
          final painter = TextPainter(
            text: TextSpan(
              text: character,
              style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          return painter.width;
        })
        .toList(growable: false);

    if (widths.isEmpty) {
      return false;
    }
    final firstWidth = widths.first;
    for (final width in widths.skip(1)) {
      if ((width - firstWidth).abs() > widthTolerance) {
        return false;
      }
    }
    return true;
  }

  List<String> _sortedFontFamilies() {
    final names = _systemFonts.getFontList();
    final unique = <String, String>{};
    for (final name in names) {
      final normalized = name.trim();
      if (normalized.isEmpty) {
        continue;
      }
      unique.putIfAbsent(normalized.toLowerCase(), () => normalized);
    }
    final values = unique.values.toList(growable: false);
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }
}
