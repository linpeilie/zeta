import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;

  group('system font native channel', () {
    for (final path in <String>[
      'macos/Runner/MainFlutterWindow.swift',
      'windows/runner/system_font_catalog_channel.cpp',
      'linux/runner/system_font_catalog_channel.cc',
    ]) {
      test('$path exposes the frozen response schema', () {
        final source = File('${root.path}/$path').readAsStringSync();
        expect(source, contains('zeta/system_fonts'));
        expect(source, contains('listFontFamilies'));
        for (final key in <String>[
          'id',
          'familyName',
          'displayName',
          'aliases',
          'monospace',
        ]) {
          expect(source, contains(key), reason: '$path must emit $key');
        }
      });
    }
  });

  group('desktop attention native channel', () {
    for (final path in <String>[
      'macos/Runner/MainFlutterWindow.swift',
      'windows/runner/desktop_attention_channel.cpp',
      'linux/runner/desktop_attention_channel.cc',
    ]) {
      test('$path supports badge and attention methods', () {
        final source = File('${root.path}/$path').readAsStringSync();
        expect(source, contains('zeta/desktop_attention'));
        expect(source, contains('setUnreadCount'));
        expect(source, contains('requestAttention'));
      });
    }
  });

  test(
    'macOS menu implements configuration, enablement, and command event',
    () {
      final source = File(
        '${root.path}/macos/Runner/AppDelegate.swift',
      ).readAsStringSync();
      expect(source, contains('zeta/menu'));
      expect(source, contains('case "configure"'));
      expect(source, contains('case "setEnabled"'));
      expect(source, contains('version == 1'));
      expect(source, contains('commandId == "openProject"'));
      expect(source, contains('invokeMethod("openProject"'));
    },
  );

  test('Windows registers both channels and links DirectWrite', () {
    final window = File(
      '${root.path}/windows/runner/flutter_window.cpp',
    ).readAsStringSync();
    final cmake = File(
      '${root.path}/windows/runner/CMakeLists.txt',
    ).readAsStringSync();
    expect(window, contains('CreateSystemFontCatalogChannel'));
    expect(window, contains('DesktopAttentionChannel'));
    expect(cmake, contains('system_font_catalog_channel.cpp'));
    expect(cmake, contains('desktop_attention_channel.cpp'));
    expect(cmake, contains('dwrite.lib'));
  });

  test('Linux registers both channels and links Fontconfig', () {
    final application = File(
      '${root.path}/linux/runner/my_application.cc',
    ).readAsStringSync();
    final runnerCmake = File(
      '${root.path}/linux/runner/CMakeLists.txt',
    ).readAsStringSync();
    final rootCmake = File(
      '${root.path}/linux/CMakeLists.txt',
    ).readAsStringSync();
    expect(application, contains('create_system_font_catalog_channel'));
    expect(application, contains('create_desktop_attention_channel'));
    expect(runnerCmake, contains('system_font_catalog_channel.cc'));
    expect(runnerCmake, contains('desktop_attention_channel.cc'));
    expect(runnerCmake, contains('PkgConfig::FONTCONFIG'));
    expect(rootCmake, contains('fontconfig'));
  });
}
