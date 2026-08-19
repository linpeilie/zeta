import 'package:settings_client/src/settings_responses.dart';

/// Settings document identities used in typed failures.
enum SettingsDocumentKind {
  /// The general-settings document.
  general,

  /// The appearance-settings document.
  appearance,
}

/// Stable current-schema decode failure codes.
enum SettingsDecodeFailureCode {
  /// The document is not valid JSON.
  malformedJson,

  /// The JSON root is not a string-keyed object.
  invalidRoot,

  /// The document is not the supported current schema version.
  unsupportedVersion,

  /// A required field has an invalid value or shape.
  invalidField,
}

/// A settings document could not be decoded as the current schema.
final class SettingsDecodeException implements Exception {
  /// Creates a content-free typed decode failure.
  const SettingsDecodeException({
    required this.document,
    required this.code,
    this.field,
  });

  /// Failed settings document.
  final SettingsDocumentKind document;

  /// Stable failure code.
  final SettingsDecodeFailureCode code;

  /// Stable field name, when applicable.
  final String? field;

  @override
  String toString() {
    return 'SettingsDecodeException('
        '${document.name}, ${code.name}, ${field ?? '-'})';
  }
}

/// A settings value could not be encoded safely.
final class SettingsValidationException implements Exception {
  /// Creates a content-free validation failure.
  const SettingsValidationException({
    required this.document,
    required this.field,
  });

  /// Failed settings document.
  final SettingsDocumentKind document;

  /// Stable invalid field name.
  final String field;

  @override
  String toString() => 'SettingsValidationException(${document.name}, $field)';
}

/// Codec for the current `general.json` schema only.
final class GeneralSettingsCodec {
  /// Creates a current-schema codec.
  const GeneralSettingsCodec();

  /// Current general-settings schema version.
  static const currentVersion = 3;

  /// Encodes [settings] to a JSON-compatible map.
  Map<String, Object?> encode(GeneralSettingsResponse settings) {
    return <String, Object?>{
      'version': currentVersion,
      'sendMessageShortcut': switch (settings.sendMessageShortcut) {
        MessageSendShortcutResponse.enter => 'enter',
        MessageSendShortcutResponse.primaryModifierEnter =>
          'primaryModifierEnter',
      },
      'notifications': <String, Object?>{
        'enabled': settings.notifications.enabled,
        'turnTerminalEnabled': settings.notifications.turnTerminalEnabled,
        'actionRequiredEnabled': settings.notifications.actionRequiredEnabled,
      },
      'appLanguage': switch (settings.appLanguage) {
        AppLanguageResponse.english => 'en',
        AppLanguageResponse.simplifiedChinese => 'zh-Hans',
      },
    };
  }

  /// Decodes the exact current schema or throws [SettingsDecodeException].
  GeneralSettingsResponse decode(Object? raw) {
    const document = SettingsDocumentKind.general;
    final map = _rootMap(raw, document);
    _requireVersion(map, currentVersion, document);
    final notifications = _fieldMap(map, 'notifications', document);
    return GeneralSettingsResponse(
      sendMessageShortcut: switch (map['sendMessageShortcut']) {
        'enter' => MessageSendShortcutResponse.enter,
        'primaryModifierEnter' =>
          MessageSendShortcutResponse.primaryModifierEnter,
        _ => throw _invalidField(document, 'sendMessageShortcut'),
      },
      notifications: AgentNotificationSettingsResponse(
        enabled: _boolField(notifications, 'enabled', document),
        turnTerminalEnabled: _boolField(
          notifications,
          'turnTerminalEnabled',
          document,
        ),
        actionRequiredEnabled: _boolField(
          notifications,
          'actionRequiredEnabled',
          document,
        ),
      ),
      appLanguage: switch (map['appLanguage']) {
        'en' => AppLanguageResponse.english,
        'zh-Hans' => AppLanguageResponse.simplifiedChinese,
        _ => throw _invalidField(document, 'appLanguage'),
      },
    );
  }
}

/// Codec for the current `appearance.json` schema only.
final class AppearanceSettingsCodec {
  /// Creates a current-schema codec.
  const AppearanceSettingsCodec();

  /// Current appearance-settings schema version.
  static const currentVersion = 1;

  /// Encodes [settings] to a JSON-compatible map.
  Map<String, Object?> encode(AppearanceSettingsResponse settings) {
    _validateFontSize(
      settings.uiFontSize,
      minUiFontSize,
      maxUiFontSize,
      'uiFontSize',
    );
    _validateFontSize(
      settings.codeFontSize,
      minCodeFontSize,
      maxCodeFontSize,
      'codeFontSize',
    );
    return <String, Object?>{
      'version': currentVersion,
      'themeMode': switch (settings.themeMode) {
        AppearanceThemeModeResponse.system => 'system',
        AppearanceThemeModeResponse.light => 'light',
        AppearanceThemeModeResponse.dark => 'dark',
      },
      'uiFontChoice': _encodeFontChoice(settings.uiFontChoice),
      'codeFontChoice': _encodeFontChoice(settings.codeFontChoice),
      'uiFontSize': settings.uiFontSize,
      'codeFontSize': settings.codeFontSize,
    };
  }

  /// Decodes the exact current schema or throws [SettingsDecodeException].
  AppearanceSettingsResponse decode(Object? raw) {
    const document = SettingsDocumentKind.appearance;
    final map = _rootMap(raw, document);
    _requireVersion(map, currentVersion, document);
    return AppearanceSettingsResponse(
      themeMode: switch (map['themeMode']) {
        'system' => AppearanceThemeModeResponse.system,
        'light' => AppearanceThemeModeResponse.light,
        'dark' => AppearanceThemeModeResponse.dark,
        _ => throw _invalidField(document, 'themeMode'),
      },
      uiFontChoice: _decodeFontChoice(map['uiFontChoice'], 'uiFontChoice'),
      codeFontChoice: _decodeFontChoice(
        map['codeFontChoice'],
        'codeFontChoice',
      ),
      uiFontSize: _decodeFontSize(
        map['uiFontSize'],
        minUiFontSize,
        maxUiFontSize,
        'uiFontSize',
      ),
      codeFontSize: _decodeFontSize(
        map['codeFontSize'],
        minCodeFontSize,
        maxCodeFontSize,
        'codeFontSize',
      ),
    );
  }
}

Map<String, Object?> _encodeFontChoice(AppearanceFontChoiceResponse choice) {
  return <String, Object?>{
    'kind': switch (choice.kind) {
      AppearanceFontChoiceKindResponse.systemDefault => 'systemDefault',
      AppearanceFontChoiceKindResponse.system => 'system',
      AppearanceFontChoiceKindResponse.bundledJetBrainsMono =>
        'bundledJetBrainsMono',
    },
    if (choice.fontFamily != null) 'fontFamily': choice.fontFamily,
  };
}

AppearanceFontChoiceResponse _decodeFontChoice(Object? raw, String field) {
  const document = SettingsDocumentKind.appearance;
  final map = _fieldMap(<String, Object?>{field: raw}, field, document);
  switch (map['kind']) {
    case 'systemDefault':
      return const AppearanceFontChoiceResponse.systemDefault();
    case 'bundledJetBrainsMono':
      return const AppearanceFontChoiceResponse.bundledJetBrainsMono();
    case 'system':
      final family = map['fontFamily'];
      if (family is String && family.trim().isNotEmpty) {
        return AppearanceFontChoiceResponse.system(family);
      }
      throw _invalidField(document, field);
    default:
      throw _invalidField(document, field);
  }
}

Map<String, Object?> _rootMap(Object? raw, SettingsDocumentKind document) {
  if (raw is! Map) {
    throw SettingsDecodeException(
      document: document,
      code: SettingsDecodeFailureCode.invalidRoot,
    );
  }
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) {
      throw SettingsDecodeException(
        document: document,
        code: SettingsDecodeFailureCode.invalidRoot,
      );
    }
    result[key] = entry.value;
  }
  return result;
}

Map<String, Object?> _fieldMap(
  Map<String, Object?> parent,
  String field,
  SettingsDocumentKind document,
) {
  final value = parent[field];
  if (value is! Map) {
    throw _invalidField(document, field);
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw _invalidField(document, field);
    }
    result[key] = entry.value;
  }
  return result;
}

void _requireVersion(
  Map<String, Object?> map,
  int expected,
  SettingsDocumentKind document,
) {
  if (map['version'] != expected) {
    throw SettingsDecodeException(
      document: document,
      code: SettingsDecodeFailureCode.unsupportedVersion,
      field: 'version',
    );
  }
}

bool _boolField(
  Map<String, Object?> map,
  String field,
  SettingsDocumentKind document,
) {
  final value = map[field];
  if (value is! bool) {
    throw _invalidField(document, field);
  }
  return value;
}

double _decodeFontSize(
  Object? raw,
  double minimum,
  double maximum,
  String field,
) {
  if (raw is! num) {
    throw _invalidField(SettingsDocumentKind.appearance, field);
  }
  final value = raw.toDouble();
  if (!value.isFinite || value < minimum || value > maximum) {
    throw _invalidField(SettingsDocumentKind.appearance, field);
  }
  return value;
}

void _validateFontSize(
  double value,
  double minimum,
  double maximum,
  String field,
) {
  if (!value.isFinite || value < minimum || value > maximum) {
    throw SettingsValidationException(
      document: SettingsDocumentKind.appearance,
      field: field,
    );
  }
}

SettingsDecodeException _invalidField(
  SettingsDocumentKind document,
  String field,
) {
  return SettingsDecodeException(
    document: document,
    code: SettingsDecodeFailureCode.invalidField,
    field: field,
  );
}
