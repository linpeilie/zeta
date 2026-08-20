import 'dart:async';

import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:equatable/equatable.dart';
import 'package:settings_client/settings_client.dart';
import 'package:settings_repository/src/settings_models.dart';

// Public dependency names intentionally differ from private fields.
// ignore_for_file: prefer_initializing_formals

/// Stable operation categories for settings Repository failures.
enum SettingsRepositoryOperation {
  /// Load the general-settings document.
  initializeGeneral,

  /// Load the appearance-settings document.
  initializeAppearance,

  /// Persist the general-settings document.
  persistGeneral,

  /// Persist the appearance-settings document.
  persistAppearance,

  /// Load the external system-font catalog.
  fontFamilies,

  /// Flush and close all owned stores.
  close,
}

/// Stable settings Repository failure categories.
enum SettingsRepositoryFailureCode {
  /// Current-schema Data could not be decoded.
  invalidData,

  /// A caller supplied an invalid domain input.
  invalidInput,

  /// External persistence or platform IO failed.
  externalFailure,

  /// The Repository has already closed.
  closed,
}

/// A content-free settings Repository failure.
final class SettingsRepositoryFailure extends Equatable {
  /// Creates a typed settings failure.
  const SettingsRepositoryFailure({
    required this.operation,
    required this.code,
    required this.diagnosticCode,
  });

  /// Operation that failed.
  final SettingsRepositoryOperation operation;

  /// Stable failure category.
  final SettingsRepositoryFailureCode code;

  /// Stable, non-localized diagnostic code.
  final String diagnosticCode;

  @override
  List<Object?> get props => <Object?>[operation, code, diagnosticCode];
}

/// A typed exception retaining private diagnostic context.
final class SettingsRepositoryException implements Exception {
  /// Creates a settings Repository exception.
  const SettingsRepositoryException({
    required this.failure,
    required this.cause,
    required this.stackTrace,
  });

  /// Vendor-neutral failure exposed to the application layer.
  final SettingsRepositoryFailure failure;

  /// Original exception retained for sanitized diagnostic logging only.
  final Object cause;

  /// Original stack trace retained for sanitized diagnostic logging only.
  final StackTrace stackTrace;

  @override
  String toString() =>
      'SettingsRepositoryException('
      '${failure.operation.name}, ${failure.code.name}, '
      '${failure.diagnosticCode})';
}

/// Owns persisted settings snapshots and converts the external font catalog.
class SettingsRepository {
  /// Creates the Repository and immediately starts loading both stores.
  SettingsRepository({
    required GeneralSettingsStore generalStore,
    required AppearanceSettingsStore appearanceStore,
    required SystemFontCatalogApi fontCatalog,
  }) : _generalStore = generalStore,
       _appearanceStore = appearanceStore,
       _fontCatalog = fontCatalog {
    _ready = _initialize();
  }

  final GeneralSettingsStore _generalStore;
  final AppearanceSettingsStore _appearanceStore;
  final SystemFontCatalogApi _fontCatalog;
  final StreamController<SettingsSnapshot> _changes =
      StreamController<SettingsSnapshot>.broadcast(sync: true);

  late final Future<void> _ready;
  SettingsSnapshot _settings = SettingsSnapshot.initial;
  Future<void> _writeQueue = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closed = false;

  /// Completes after both current-schema settings documents load.
  Future<void> get ready => _ready;

  /// Most recently loaded or persisted immutable settings snapshot.
  SettingsSnapshot get settings => _settings;

  /// Emits after initial load and every successful persistence operation.
  Stream<SettingsSnapshot> get settingsChanges => _changes.stream;

  /// Persists exactly one settings document and then publishes a snapshot.
  ///
  /// Failed writes never replace the in-memory snapshot. Calls are serialized
  /// so concurrent Bloc events cannot publish out of order.
  Future<SettingsPersistResult> persist(SettingsUpdate update) {
    return _enqueue(() async {
      await ready;
      _ensureOpen(
        switch (update) {
          GeneralSettingsUpdate() => SettingsRepositoryOperation.persistGeneral,
          AppearanceSettingsUpdate() =>
            SettingsRepositoryOperation.persistAppearance,
        },
      );
      return switch (update) {
        GeneralSettingsUpdate() => _persistGeneral(update.value),
        AppearanceSettingsUpdate() => _persistAppearance(update.value),
      };
    });
  }

  /// Loads and converts installed system-font families.
  Future<List<SettingsFontFamily>> fontFamilies({
    required String localeName,
    bool monospaceOnly = false,
  }) async {
    _ensureOpen(SettingsRepositoryOperation.fontFamilies);
    final normalizedLocale = localeName.trim();
    if (normalizedLocale.isEmpty) {
      _fail(
        operation: SettingsRepositoryOperation.fontFamilies,
        code: SettingsRepositoryFailureCode.invalidInput,
        diagnosticCode: 'locale_name_missing',
        cause: ArgumentError.value(localeName, 'localeName'),
      );
    }
    try {
      final responses = await _fontCatalog.listFontFamilies(
        localeName: normalizedLocale,
      );
      final byId = <String, SettingsFontFamily>{};
      for (final response in responses) {
        if (monospaceOnly && !response.isMonospace) {
          continue;
        }
        final family = _mapSystemFontFamily(response);
        byId.putIfAbsent(family.id, () => family);
      }
      final result = byId.values.toList()
        ..sort((left, right) {
          final display = left.displayName.toLowerCase().compareTo(
            right.displayName.toLowerCase(),
          );
          return display == 0 ? left.id.compareTo(right.id) : display;
        });
      return List<SettingsFontFamily>.unmodifiable(result);
    } on _InvalidFontCatalogException catch (error, stackTrace) {
      throw _exception(
        operation: SettingsRepositoryOperation.fontFamilies,
        code: SettingsRepositoryFailureCode.invalidData,
        diagnosticCode: 'font_catalog_invalid',
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw _exception(
        operation: SettingsRepositoryOperation.fontFamilies,
        code: SettingsRepositoryFailureCode.externalFailure,
        diagnosticCode: 'font_catalog_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Flushes and closes both stores and the external-data stream.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _initialize() async {
    final generalResponse = await _loadGeneral();
    final appearanceResponse = await _loadAppearance();
    if (_closed) {
      return;
    }
    _settings = SettingsSnapshot(
      general: _mapGeneral(generalResponse),
      appearance: _mapAppearance(appearanceResponse),
      revision: 1,
    );
    _changes.add(_settings);
  }

  Future<GeneralSettingsResponse> _loadGeneral() async {
    try {
      return await _generalStore.load();
    } on SettingsDecodeException catch (error, stackTrace) {
      throw _exception(
        operation: SettingsRepositoryOperation.initializeGeneral,
        code: SettingsRepositoryFailureCode.invalidData,
        diagnosticCode: 'general_settings_invalid',
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw _exception(
        operation: SettingsRepositoryOperation.initializeGeneral,
        code: SettingsRepositoryFailureCode.externalFailure,
        diagnosticCode: 'general_settings_load_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AppearanceSettingsResponse> _loadAppearance() async {
    try {
      return await _appearanceStore.load();
    } on SettingsDecodeException catch (error, stackTrace) {
      throw _exception(
        operation: SettingsRepositoryOperation.initializeAppearance,
        code: SettingsRepositoryFailureCode.invalidData,
        diagnosticCode: 'appearance_settings_invalid',
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw _exception(
        operation: SettingsRepositoryOperation.initializeAppearance,
        code: SettingsRepositoryFailureCode.externalFailure,
        diagnosticCode: 'appearance_settings_load_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<SettingsPersistResult> _persistGeneral(GeneralSettings value) async {
    if (_settings.general == value) {
      return SettingsPersistResult.unchanged;
    }
    try {
      await _generalStore.save(_mapGeneralResponse(value));
    } on Object catch (error, stackTrace) {
      throw _exception(
        operation: SettingsRepositoryOperation.persistGeneral,
        code: SettingsRepositoryFailureCode.externalFailure,
        diagnosticCode: 'general_settings_save_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    _settings = SettingsSnapshot(
      general: value,
      appearance: _settings.appearance,
      revision: _settings.revision + 1,
    );
    _changes.add(_settings);
    return SettingsPersistResult.applied;
  }

  Future<SettingsPersistResult> _persistAppearance(
    AppearanceSettings value,
  ) async {
    if (_settings.appearance == value) {
      return SettingsPersistResult.unchanged;
    }
    try {
      await _appearanceStore.save(_mapAppearanceResponse(value));
    } on Object catch (error, stackTrace) {
      throw _exception(
        operation: SettingsRepositoryOperation.persistAppearance,
        code: SettingsRepositoryFailureCode.externalFailure,
        diagnosticCode: 'appearance_settings_save_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    _settings = SettingsSnapshot(
      general: _settings.general,
      appearance: value,
      revision: _settings.revision + 1,
    );
    _changes.add(_settings);
    return SettingsPersistResult.applied;
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _close() async {
    _closed = true;
    ({Object error, StackTrace stackTrace})? firstFailure;

    try {
      await ready;
    } on Object catch (error, stackTrace) {
      firstFailure = (error: error, stackTrace: stackTrace);
    }
    await _writeQueue;
    for (final closeStore in <Future<void> Function()>[
      _generalStore.close,
      _appearanceStore.close,
    ]) {
      try {
        await closeStore();
      } on Object catch (error, stackTrace) {
        firstFailure ??= (error: error, stackTrace: stackTrace);
      }
    }
    await _changes.close();
    if (firstFailure != null) {
      throw _exception(
        operation: SettingsRepositoryOperation.close,
        code: SettingsRepositoryFailureCode.externalFailure,
        diagnosticCode: 'settings_close_failed',
        cause: firstFailure.error,
        stackTrace: firstFailure.stackTrace,
      );
    }
  }

  void _ensureOpen(SettingsRepositoryOperation operation) {
    if (_closed) {
      _fail(
        operation: operation,
        code: SettingsRepositoryFailureCode.closed,
        diagnosticCode: 'repository_closed',
        cause: StateError('Settings Repository is closed'),
      );
    }
  }
}

GeneralSettings _mapGeneral(GeneralSettingsResponse response) {
  return GeneralSettings(
    sendMessageShortcut: switch (response.sendMessageShortcut) {
      MessageSendShortcutResponse.enter => MessageSendShortcut.enter,
      MessageSendShortcutResponse.primaryModifierEnter =>
        MessageSendShortcut.primaryModifierEnter,
    },
    notifications: AgentNotificationSettings(
      enabled: response.notifications.enabled,
      turnTerminalEnabled: response.notifications.turnTerminalEnabled,
      actionRequiredEnabled: response.notifications.actionRequiredEnabled,
    ),
    appLanguage: switch (response.appLanguage) {
      AppLanguageResponse.english => AppLanguage.english,
      AppLanguageResponse.simplifiedChinese => AppLanguage.simplifiedChinese,
    },
  );
}

GeneralSettingsResponse _mapGeneralResponse(GeneralSettings value) {
  return GeneralSettingsResponse(
    sendMessageShortcut: switch (value.sendMessageShortcut) {
      MessageSendShortcut.enter => MessageSendShortcutResponse.enter,
      MessageSendShortcut.primaryModifierEnter =>
        MessageSendShortcutResponse.primaryModifierEnter,
    },
    notifications: AgentNotificationSettingsResponse(
      enabled: value.notifications.enabled,
      turnTerminalEnabled: value.notifications.turnTerminalEnabled,
      actionRequiredEnabled: value.notifications.actionRequiredEnabled,
    ),
    appLanguage: switch (value.appLanguage) {
      AppLanguage.english => AppLanguageResponse.english,
      AppLanguage.simplifiedChinese => AppLanguageResponse.simplifiedChinese,
    },
  );
}

AppearanceSettings _mapAppearance(AppearanceSettingsResponse response) {
  return AppearanceSettings(
    themeMode: switch (response.themeMode) {
      AppearanceThemeModeResponse.system => SettingsThemeMode.system,
      AppearanceThemeModeResponse.light => SettingsThemeMode.light,
      AppearanceThemeModeResponse.dark => SettingsThemeMode.dark,
    },
    uiFontChoice: _mapFontChoice(response.uiFontChoice),
    codeFontChoice: _mapFontChoice(response.codeFontChoice),
    uiFontSize: response.uiFontSize,
    codeFontSize: response.codeFontSize,
  );
}

AppearanceSettingsResponse _mapAppearanceResponse(AppearanceSettings value) {
  return AppearanceSettingsResponse(
    themeMode: switch (value.themeMode) {
      SettingsThemeMode.system => AppearanceThemeModeResponse.system,
      SettingsThemeMode.light => AppearanceThemeModeResponse.light,
      SettingsThemeMode.dark => AppearanceThemeModeResponse.dark,
    },
    uiFontChoice: _mapFontChoiceResponse(value.uiFontChoice),
    codeFontChoice: _mapFontChoiceResponse(value.codeFontChoice),
    uiFontSize: value.uiFontSize,
    codeFontSize: value.codeFontSize,
  );
}

SettingsFontChoice _mapFontChoice(AppearanceFontChoiceResponse response) {
  return switch (response.kind) {
    AppearanceFontChoiceKindResponse.systemDefault =>
      const SettingsFontChoice.systemDefault(),
    AppearanceFontChoiceKindResponse.system => SettingsFontChoice.system(
      response.fontFamily!,
    ),
    AppearanceFontChoiceKindResponse.bundledJetBrainsMono =>
      const SettingsFontChoice.bundledJetBrainsMono(),
  };
}

AppearanceFontChoiceResponse _mapFontChoiceResponse(SettingsFontChoice value) {
  return switch (value.kind) {
    SettingsFontChoiceKind.systemDefault =>
      const AppearanceFontChoiceResponse.systemDefault(),
    SettingsFontChoiceKind.system => AppearanceFontChoiceResponse.system(
      value.fontFamily!,
    ),
    SettingsFontChoiceKind.bundledJetBrainsMono =>
      const AppearanceFontChoiceResponse.bundledJetBrainsMono(),
  };
}

SettingsFontFamily _mapSystemFontFamily(SystemFontFamily response) {
  if (response.id.trim().isEmpty ||
      response.familyName.trim().isEmpty ||
      response.displayName.trim().isEmpty ||
      response.aliases.any((alias) => alias.trim().isEmpty)) {
    throw const _InvalidFontCatalogException();
  }
  return SettingsFontFamily(
    id: response.id,
    familyName: response.familyName,
    displayName: response.displayName,
    aliases: response.aliases,
    isMonospace: response.isMonospace,
  );
}

Never _fail({
  required SettingsRepositoryOperation operation,
  required SettingsRepositoryFailureCode code,
  required String diagnosticCode,
  required Object cause,
}) {
  throw _exception(
    operation: operation,
    code: code,
    diagnosticCode: diagnosticCode,
    cause: cause,
    stackTrace: StackTrace.current,
  );
}

SettingsRepositoryException _exception({
  required SettingsRepositoryOperation operation,
  required SettingsRepositoryFailureCode code,
  required String diagnosticCode,
  required Object cause,
  required StackTrace stackTrace,
}) {
  return SettingsRepositoryException(
    failure: SettingsRepositoryFailure(
      operation: operation,
      code: code,
      diagnosticCode: diagnosticCode,
    ),
    cause: cause,
    stackTrace: stackTrace,
  );
}

final class _InvalidFontCatalogException implements Exception {
  const _InvalidFontCatalogException();
}
