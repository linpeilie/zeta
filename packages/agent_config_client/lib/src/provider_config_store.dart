import 'dart:convert';
import 'dart:io';

import 'package:agent_config_client/src/agent_config_decode_exception.dart';
import 'package:agent_config_client/src/codec_support.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:zeta_storage/zeta_storage.dart';

const AgentConfigDocumentKind _document =
    AgentConfigDocumentKind.providerConfig;

/// Persistence boundary for the global Provider definitions.
abstract interface class ProviderConfigStore {
  /// Reads all Provider definitions, or an empty list when no file exists.
  Future<List<AgentProviderConfig>> read();

  /// Atomically replaces all Provider definitions.
  Future<void> write(List<AgentProviderConfig> configs);
}

/// Current-schema JSON codec for Provider definitions.
final class ProviderConfigCodec {
  /// Creates a current-schema codec.
  const ProviderConfigCodec();

  /// Encodes [configs] without active-provider selection state.
  String encode(List<AgentProviderConfig> configs) {
    return jsonEncode(<String, Object?>{
      'version': AgentProviderSettings.currentVersion,
      'providers': configs.map((config) => config.toJson()).toList(),
    });
  }

  /// Decodes only the current Provider schema.
  List<AgentProviderConfig> decode(String source) {
    final root = decodeJsonObject(source, _document);
    requireVersion(root, AgentProviderSettings.currentVersion, _document);
    final values = requireList(root['providers'], _document);
    final result = <AgentProviderConfig>[];
    final ids = <String>{};
    for (final value in values) {
      final config = _decodeProvider(value);
      if (!ids.add(config.id)) {
        duplicateIdentifier(_document);
      }
      result.add(config);
    }
    return List<AgentProviderConfig>.unmodifiable(result);
  }
}

/// File-backed [ProviderConfigStore] using same-directory atomic replacement.
final class FileProviderConfigStore implements ProviderConfigStore {
  /// Creates a store for [file].
  FileProviderConfigStore({
    required File file,
    this._codec = const ProviderConfigCodec(),
    AtomicTemporaryPathBuilder? temporaryPathBuilder,
    AtomicFileReplacer? replacer,
    AtomicTemporaryFileDeleter? temporaryFileDeleter,
  }) : _storage = AtomicTextFile(
         file,
         temporaryPathBuilder: temporaryPathBuilder,
         replacer: replacer,
         temporaryFileDeleter: temporaryFileDeleter,
       );

  final ProviderConfigCodec _codec;
  final AtomicTextFile _storage;

  @override
  Future<List<AgentProviderConfig>> read() async {
    final source = await _storage.read();
    if (source == null) {
      return const <AgentProviderConfig>[];
    }
    return _codec.decode(source);
  }

  @override
  Future<void> write(List<AgentProviderConfig> configs) {
    return _storage.write(_codec.encode(configs));
  }
}

AgentProviderConfig _decodeProvider(Object? value) {
  final map = requireObject(value, _document);
  final id = requireString(map['id'], _document);
  final kindName = requireString(map['kind'], _document);
  final kind = AgentProviderKind.values.where((item) => item.name == kindName);
  if (kind.length != 1) {
    throw const AgentConfigDecodeException(
      document: _document,
      reason: AgentConfigDecodeReason.invalidShape,
    );
  }

  final arguments = requireList(
    map['arguments'],
    _document,
  ).map((item) => requireString(item, _document)).toList(growable: false);
  final environmentMap = requireObject(map['environment'], _document);
  final environment = <String, String>{
    for (final entry in environmentMap.entries)
      requireString(entry.key, _document): requireString(
        entry.value,
        _document,
      ),
  };
  final preferencesMap = requireObject(map['modelPreferences'], _document);
  final preferences = <String, AgentModelPreference>{};
  for (final entry in preferencesMap.entries) {
    final key = requireString(entry.key, _document);
    final preference = _decodePreference(entry.value);
    if (preference.modelId != key) {
      throw const AgentConfigDecodeException(
        document: _document,
        reason: AgentConfigDecodeReason.invalidShape,
      );
    }
    preferences[key] = preference;
  }

  return AgentProviderConfig(
    id: id,
    displayName: requireString(map['displayName'], _document),
    kind: kind.single,
    command: requireString(map['command'], _document),
    arguments: arguments,
    environment: environment,
    defaultModel: requireNullableString(map['defaultModel'], _document),
    selectedModel: requireNullableString(map['selectedModel'], _document),
    selectedReasoningEffort: requireNullableString(
      map['selectedReasoningEffort'],
      _document,
    ),
    selectedServiceTier: requireNullableString(
      map['selectedServiceTier'],
      _document,
    ),
    modelPreferences: preferences,
    selectedPermissionOptionId: requireNullableString(
      map['selectedPermissionOptionId'],
      _document,
    ),
    enabled: requireBool(map['enabled'], _document),
    extra: requireObject(map['extra'], _document),
  );
}

AgentModelPreference _decodePreference(Object? value) {
  final map = requireObject(value, _document);
  final version = map['version'];
  if (version != AgentModelPreference.currentVersion) {
    throw const AgentConfigDecodeException(
      document: _document,
      reason: AgentConfigDecodeReason.unsupportedVersion,
    );
  }
  return AgentModelPreference(
    modelId: requireString(map['modelId'], _document),
    reasoningEffort: requireNullableString(
      map['reasoningEffort'],
      _document,
    ),
    fastEnabled: requireBool(map['fastEnabled'], _document),
    serviceTierId: requireNullableString(map['serviceTierId'], _document),
    updatedAt: requireDateTime(map['updatedAt'], _document),
  );
}
