import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

void main() {
  final arbDir = Directory('lib/src/ui/localization/arb');
  final generatedDir = Directory('lib/src/ui/localization/generated');

  Map<String, dynamic> readArb(String name) {
    return jsonDecode(File('${arbDir.path}/$name').readAsStringSync())
        as Map<String, dynamic>;
  }

  Set<String> messageKeys(Map<String, dynamic> arb) {
    return arb.keys.where((key) => !key.startsWith('@')).toSet();
  }

  String fingerprintDirectory(Directory directory) {
    final files = directory.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final bytes = <int>[];
    for (final file in files) {
      bytes.addAll(utf8.encode(file.uri.pathSegments.last));
      bytes.addAll(file.readAsBytesSync());
    }
    return sha256.convert(bytes).toString();
  }

  test(
    'ARB files declare only en and zh with matching keys and placeholders',
    () {
      final names = arbDir
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toSet();
      expect(names, {'app_en.arb', 'app_zh.arb'});

      final en = readArb('app_en.arb');
      final zh = readArb('app_zh.arb');
      expect(en['@@locale'], 'en');
      expect(zh['@@locale'], 'zh');
      expect(messageKeys(zh), messageKeys(en));

      for (final key in messageKeys(en)) {
        final enMeta = en['@$key'];
        final zhMeta = zh['@$key'];
        expect(enMeta, isA<Map<String, dynamic>>(), reason: 'en @$key');
        expect(zhMeta, isA<Map<String, dynamic>>(), reason: 'zh @$key');
        final enPlaceholders =
            ((enMeta as Map<String, dynamic>)['placeholders'] as Map?) ??
            const {};
        final zhPlaceholders =
            ((zhMeta as Map<String, dynamic>)['placeholders'] as Map?) ??
            const {};
        expect(zhPlaceholders.keys.toSet(), enPlaceholders.keys.toSet());
      }
    },
  );

  test('ARB resources do not use plural, date, or number formatters', () {
    for (final file in arbDir.listSync().whereType<File>()) {
      final arb = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final key in messageKeys(arb)) {
        final value = arb[key] as String;
        expect(
          value.contains(', plural,'),
          isFalse,
          reason: '${file.path} $key',
        );
        expect(
          value.contains(', select,'),
          isFalse,
          reason: '${file.path} $key',
        );
        final meta = arb['@$key'] as Map<String, dynamic>;
        final placeholders = meta['placeholders'] as Map<String, dynamic>?;
        if (placeholders == null) {
          continue;
        }
        for (final placeholder in placeholders.values) {
          final spec = placeholder as Map<String, dynamic>;
          expect(
            spec.containsKey('format'),
            isFalse,
            reason: '${file.path} $key',
          );
          expect(spec['type'], anyOf(isNull, 'String'));
        }
      }
    }
  });

  test('generated AppLocalizations only expose en and zh', () {
    expect(AppLocalizations.supportedLocales, const [
      Locale('en'),
      Locale('zh'),
    ]);
  });

  test('generated getters resolve contract greeting in both locales', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(en.localizationContractGreeting('Ada'), 'Hello Ada');
    expect(zh.localizationContractGreeting('Ada'), '你好 Ada');
  });

  test('second flutter gen-l10n run does not change generated sources', () {
    expect(generatedDir.existsSync(), isTrue);
    final before = fingerprintDirectory(generatedDir);
    final result = Process.runSync('flutter', ['gen-l10n']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(fingerprintDirectory(generatedDir), before);
  });
}
