import 'dart:convert';

import 'package:settings_client/src/settings_codec.dart';
import 'package:settings_client/src/settings_document_storage.dart';
import 'package:settings_client/src/settings_responses.dart';

/// Current-schema general-settings persistence boundary.
abstract interface class GeneralSettingsStore {
  /// Loads settings, using the configured clean-install value when absent.
  Future<GeneralSettingsResponse> load();

  /// Atomically saves [settings].
  Future<void> save(GeneralSettingsResponse settings);

  /// Flushes and closes this store.
  Future<void> close();
}

/// JSON general-settings store backed by injected document storage.
final class FileGeneralSettingsStore implements GeneralSettingsStore {
  /// Creates a general-settings store.
  const FileGeneralSettingsStore({
    required this.storage,
    this.missingValue = const GeneralSettingsResponse(),
    this.codec = const GeneralSettingsCodec(),
  });

  /// External text storage.
  final SettingsDocumentStorage storage;

  /// Value returned for missing or empty clean-install files.
  final GeneralSettingsResponse missingValue;

  /// Current-schema codec.
  final GeneralSettingsCodec codec;

  @override
  Future<GeneralSettingsResponse> load() async {
    final source = await storage.read();
    if (source == null || source.trim().isEmpty) {
      return missingValue;
    }
    Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException {
      throw const SettingsDecodeException(
        document: SettingsDocumentKind.general,
        code: SettingsDecodeFailureCode.malformedJson,
      );
    }
    return codec.decode(raw);
  }

  @override
  Future<void> save(GeneralSettingsResponse settings) {
    return storage.write(jsonEncode(codec.encode(settings)));
  }

  @override
  Future<void> close() => storage.close();
}
