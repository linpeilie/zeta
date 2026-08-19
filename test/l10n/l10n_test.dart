import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/l10n/l10n.dart';

import '../helpers/helpers.dart';

void main() {
  group(AppLocalizations, () {
    group('ARB resources', () {
      test(
        'contain only en and zh with exactly 1035 matching message keys',
        () {
          final arbDirectory = Directory('lib/l10n/arb');
          final names = arbDirectory
              .listSync()
              .whereType<File>()
              .map((file) => file.uri.pathSegments.last)
              .toSet();

          expect(names, {'app_en.arb', 'app_zh.arb'});

          final en = _readArb(arbDirectory, 'app_en.arb');
          final zh = _readArb(arbDirectory, 'app_zh.arb');
          final enKeys = _messageKeys(en);
          final zhKeys = _messageKeys(zh);

          expect(en['@@locale'], 'en');
          expect(zh['@@locale'], 'zh');
          expect(enKeys, hasLength(1035));
          expect(zhKeys, enKeys);

          for (final key in enKeys) {
            final enMetadata = en['@$key'];
            final zhMetadata = zh['@$key'];
            expect(
              enMetadata,
              isA<Map<String, dynamic>>(),
              reason: 'Missing English metadata for $key',
            );
            expect(
              zhMetadata,
              isA<Map<String, dynamic>>(),
              reason: 'Missing Chinese metadata for $key',
            );
            expect(
              _placeholderKeys(zhMetadata),
              _placeholderKeys(enMetadata),
              reason: 'Placeholder mismatch for $key',
            );
          }
        },
      );
    });

    group('generated localizations', () {
      test('support only English and Chinese', () {
        expect(AppLocalizations.supportedLocales, const [
          Locale('en'),
          Locale('zh'),
        ]);
      });

      test(
        'resolve the localization contract greeting in both locales',
        () async {
          final en = await AppLocalizations.delegate.load(const Locale('en'));
          final zh = await AppLocalizations.delegate.load(const Locale('zh'));

          expect(en.localizationContractGreeting('Ada'), 'Hello Ada');
          expect(zh.localizationContractGreeting('Ada'), '你好 Ada');
        },
      );
    });
  });

  group('AppLocalizationsX', () {
    testWidgets('l10nOrNull returns null without localization delegates', (
      tester,
    ) async {
      AppLocalizations? localization;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              localization = context.l10nOrNull;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(localization, isNull);
    });

    testWidgets('l10n and l10nOrNull return the installed localization', (
      tester,
    ) async {
      AppLocalizations? requiredLocalization;
      AppLocalizations? optionalLocalization;

      await tester.pumpApp(
        Builder(
          builder: (context) {
            requiredLocalization = context.l10n;
            optionalLocalization = context.l10nOrNull;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(requiredLocalization?.appTitle, 'Zeta');
      expect(optionalLocalization, same(requiredLocalization));
    });
  });
}

Map<String, dynamic> _readArb(Directory directory, String name) {
  return jsonDecode(File('${directory.path}/$name').readAsStringSync())
      as Map<String, dynamic>;
}

Set<String> _messageKeys(Map<String, dynamic> arb) {
  return arb.keys.where((key) => !key.startsWith('@')).toSet();
}

Set<String> _placeholderKeys(Object? metadata) {
  if (metadata is! Map<String, dynamic>) {
    return const {};
  }
  final placeholders = metadata['placeholders'];
  if (placeholders is! Map<String, dynamic>) {
    return const {};
  }
  return placeholders.keys.toSet();
}
