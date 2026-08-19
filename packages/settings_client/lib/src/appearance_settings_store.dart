import 'dart:convert';

import 'package:settings_client/src/settings_codec.dart';
import 'package:settings_client/src/settings_document_storage.dart';
import 'package:settings_client/src/settings_responses.dart';

/// Current-schema appearance-settings persistence boundary.
abstract interface class AppearanceSettingsStore {
  /// Loads settings, using defaults when the clean-install file is absent.
  Future<AppearanceSettingsResponse> load();

  /// Atomically saves [settings].
  Future<void> save(AppearanceSettingsResponse settings);

  /// Flushes and closes this store.
  Future<void> close();
}

/// JSON appearance-settings store backed by injected document storage.
final class FileAppearanceSettingsStore implements AppearanceSettingsStore {
  /// Creates an appearance-settings store.
  const FileAppearanceSettingsStore({
    required this.storage,
    this.missingValue = const AppearanceSettingsResponse(),
    this.codec = const AppearanceSettingsCodec(),
  });

  /// External text storage.
  final SettingsDocumentStorage storage;

  /// Value returned for missing or empty clean-install files.
  final AppearanceSettingsResponse missingValue;

  /// Current-schema codec.
  final AppearanceSettingsCodec codec;

  @override
  Future<AppearanceSettingsResponse> load() async {
    final source = await storage.read();
    if (source == null || source.trim().isEmpty) {
      return missingValue;
    }
    Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException {
      throw const SettingsDecodeException(
        document: SettingsDocumentKind.appearance,
        code: SettingsDecodeFailureCode.malformedJson,
      );
    }
    return codec.decode(raw);
  }

  @override
  Future<void> save(AppearanceSettingsResponse settings) {
    return storage.write(jsonEncode(codec.encode(settings)));
  }

  @override
  Future<void> close() => storage.close();
}
