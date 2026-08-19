import 'package:settings_client/settings_client.dart';
import 'package:test/test.dart';

void main() {
  const generalCodec = GeneralSettingsCodec();
  const appearanceCodec = AppearanceSettingsCodec();

  group('GeneralSettingsCodec', () {
    test('round trips every current-schema value', () {
      const settings = GeneralSettingsResponse(
        sendMessageShortcut: MessageSendShortcutResponse.primaryModifierEnter,
        notifications: AgentNotificationSettingsResponse(
          enabled: false,
          turnTerminalEnabled: false,
          actionRequiredEnabled: false,
        ),
        appLanguage: AppLanguageResponse.english,
      );

      final encoded = generalCodec.encode(settings);
      expect(encoded['version'], GeneralSettingsCodec.currentVersion);
      expect(generalCodec.decode(encoded), settings);
      expect(
        generalCodec.decode(
          generalCodec.encode(const GeneralSettingsResponse()),
        ),
        const GeneralSettingsResponse(),
      );
    });

    test('rejects invalid roots and non-string map keys', () {
      expectDecodeFailure(
        () => generalCodec.decode(const <Object?>[]),
        SettingsDocumentKind.general,
        SettingsDecodeFailureCode.invalidRoot,
      );
      expectDecodeFailure(
        () => generalCodec.decode(<Object?, Object?>{1: 'value'}),
        SettingsDocumentKind.general,
        SettingsDecodeFailureCode.invalidRoot,
      );
    });

    test('rejects every unsupported historical or malformed version', () {
      for (final version in <Object?>[null, 1, 2, 4, '3']) {
        expectDecodeFailure(
          () => generalCodec.decode(<String, Object?>{'version': version}),
          SettingsDocumentKind.general,
          SettingsDecodeFailureCode.unsupportedVersion,
          field: 'version',
        );
      }
    });

    test('rejects malformed shortcut, notification, and language fields', () {
      final valid = generalCodec.encode(const GeneralSettingsResponse());
      expectInvalidGeneralField(
        generalCodec,
        <String, Object?>{...valid, 'sendMessageShortcut': 'space'},
        'sendMessageShortcut',
      );
      expectInvalidGeneralField(
        generalCodec,
        <String, Object?>{...valid, 'notifications': true},
        'notifications',
      );
      expectInvalidGeneralField(
        generalCodec,
        <String, Object?>{
          ...valid,
          'notifications': <Object?, Object?>{1: true},
        },
        'notifications',
      );
      for (final field in <String>[
        'enabled',
        'turnTerminalEnabled',
        'actionRequiredEnabled',
      ]) {
        final notifications = <String, Object?>{
          ...valid['notifications']! as Map<String, Object?>,
          field: 'true',
        };
        expectInvalidGeneralField(
          generalCodec,
          <String, Object?>{...valid, 'notifications': notifications},
          field,
        );
      }
      expectInvalidGeneralField(
        generalCodec,
        <String, Object?>{...valid, 'appLanguage': 'fr'},
        'appLanguage',
      );
    });
  });

  group('AppearanceSettingsCodec', () {
    test('round trips every theme and font-source kind', () {
      final cases = <AppearanceSettingsResponse>[
        const AppearanceSettingsResponse(),
        const AppearanceSettingsResponse(
          themeMode: AppearanceThemeModeResponse.light,
          uiFontChoice: AppearanceFontChoiceResponse.bundledJetBrainsMono(),
          codeFontChoice: AppearanceFontChoiceResponse.systemDefault(),
          uiFontSize: minUiFontSize,
          codeFontSize: minCodeFontSize,
        ),
        AppearanceSettingsResponse(
          themeMode: AppearanceThemeModeResponse.dark,
          uiFontChoice: AppearanceFontChoiceResponse.system(' Inter '),
          codeFontChoice: AppearanceFontChoiceResponse.system('Cascadia Code'),
          uiFontSize: maxUiFontSize,
          codeFontSize: maxCodeFontSize,
        ),
      ];

      for (final settings in cases) {
        final encoded = appearanceCodec.encode(settings);
        expect(encoded['version'], AppearanceSettingsCodec.currentVersion);
        expect(appearanceCodec.decode(encoded), settings);
      }
    });

    test('accepts integer and finite double font sizes', () {
      final raw = appearanceCodec.encode(const AppearanceSettingsResponse());
      final decoded = appearanceCodec.decode(<String, Object?>{
        ...raw,
        'uiFontSize': 11,
        'codeFontSize': 13.5,
      });

      expect(decoded.uiFontSize, 11);
      expect(decoded.codeFontSize, 13.5);
    });

    test('rejects invalid roots and versions', () {
      expectDecodeFailure(
        () => appearanceCodec.decode(null),
        SettingsDocumentKind.appearance,
        SettingsDecodeFailureCode.invalidRoot,
      );
      expectDecodeFailure(
        () => appearanceCodec.decode(<Object?, Object?>{1: 'value'}),
        SettingsDocumentKind.appearance,
        SettingsDecodeFailureCode.invalidRoot,
      );
      expectDecodeFailure(
        () => appearanceCodec.decode(<String, Object?>{'version': 2}),
        SettingsDocumentKind.appearance,
        SettingsDecodeFailureCode.unsupportedVersion,
        field: 'version',
      );
    });

    test('rejects invalid themes and font-choice shapes', () {
      final valid = appearanceCodec.encode(const AppearanceSettingsResponse());
      expectInvalidAppearanceField(
        appearanceCodec,
        <String, Object?>{...valid, 'themeMode': 'sepia'},
        'themeMode',
      );
      for (final rawChoice in <Object?>[
        true,
        <Object?, Object?>{1: 'system'},
        <String, Object?>{'kind': 'unknown'},
        <String, Object?>{'kind': 'system'},
        <String, Object?>{'kind': 'system', 'fontFamily': 7},
        <String, Object?>{'kind': 'system', 'fontFamily': '   '},
      ]) {
        expectInvalidAppearanceField(
          appearanceCodec,
          <String, Object?>{...valid, 'uiFontChoice': rawChoice},
          'uiFontChoice',
        );
      }
    });

    test('rejects non-numeric, non-finite, and out-of-range sizes', () {
      final valid = appearanceCodec.encode(const AppearanceSettingsResponse());
      for (final entry in <(String, Object?)>[
        ('uiFontSize', '12'),
        ('uiFontSize', double.nan),
        ('uiFontSize', minUiFontSize - 1),
        ('uiFontSize', maxUiFontSize + 1),
        ('codeFontSize', double.infinity),
        ('codeFontSize', minCodeFontSize - 1),
        ('codeFontSize', maxCodeFontSize + 1),
      ]) {
        expectInvalidAppearanceField(
          appearanceCodec,
          <String, Object?>{...valid, entry.$1: entry.$2},
          entry.$1,
        );
      }
    });

    test('rejects invalid values before encoding', () {
      for (final settings in <AppearanceSettingsResponse>[
        const AppearanceSettingsResponse(uiFontSize: double.nan),
        const AppearanceSettingsResponse(uiFontSize: minUiFontSize - 1),
        const AppearanceSettingsResponse(uiFontSize: maxUiFontSize + 1),
        const AppearanceSettingsResponse(codeFontSize: double.infinity),
        const AppearanceSettingsResponse(codeFontSize: minCodeFontSize - 1),
        const AppearanceSettingsResponse(codeFontSize: maxCodeFontSize + 1),
      ]) {
        expect(
          () => appearanceCodec.encode(settings),
          throwsA(isA<SettingsValidationException>()),
        );
      }
    });
  });

  test('typed exceptions contain stable metadata without document content', () {
    const decode = SettingsDecodeException(
      document: SettingsDocumentKind.general,
      code: SettingsDecodeFailureCode.malformedJson,
    );
    const validation = SettingsValidationException(
      document: SettingsDocumentKind.appearance,
      field: 'uiFontSize',
    );

    expect(decode.document, SettingsDocumentKind.general);
    expect(decode.code, SettingsDecodeFailureCode.malformedJson);
    expect(decode.field, isNull);
    expect(
      decode.toString(),
      'SettingsDecodeException(general, malformedJson, -)',
    );
    expect(validation.document, SettingsDocumentKind.appearance);
    expect(validation.field, 'uiFontSize');
    expect(
      validation.toString(),
      'SettingsValidationException(appearance, uiFontSize)',
    );
  });
}

void expectInvalidGeneralField(
  GeneralSettingsCodec codec,
  Object? raw,
  String field,
) {
  expectDecodeFailure(
    () => codec.decode(raw),
    SettingsDocumentKind.general,
    SettingsDecodeFailureCode.invalidField,
    field: field,
  );
}

void expectInvalidAppearanceField(
  AppearanceSettingsCodec codec,
  Object? raw,
  String field,
) {
  expectDecodeFailure(
    () => codec.decode(raw),
    SettingsDocumentKind.appearance,
    SettingsDecodeFailureCode.invalidField,
    field: field,
  );
}

void expectDecodeFailure(
  Object? Function() callback,
  SettingsDocumentKind document,
  SettingsDecodeFailureCode code, {
  String? field,
}) {
  expect(
    callback,
    throwsA(
      isA<SettingsDecodeException>()
          .having((error) => error.document, 'document', document)
          .having((error) => error.code, 'code', code)
          .having((error) => error.field, 'field', field),
    ),
  );
}
