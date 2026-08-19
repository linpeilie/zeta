import 'dart:convert';
import 'dart:io';

import 'package:agent_config_client/src/agent_config_decode_exception.dart';
import 'package:agent_config_client/src/codec_support.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:zeta_storage/zeta_storage.dart';

const AgentConfigDocumentKind _document =
    AgentConfigDocumentKind.modelCatalogCache;

/// Current-schema JSON codec for Provider model-catalog snapshots.
final class AgentModelCatalogCacheCodec {
  /// Creates a current-schema codec.
  const AgentModelCatalogCacheCodec();

  /// Current persisted model-catalog schema.
  static const int currentVersion = 1;

  /// Encodes complete catalog [snapshots].
  String encode(List<AgentModelCatalogSnapshot> snapshots) {
    return jsonEncode(<String, Object?>{
      'version': currentVersion,
      'entries': snapshots.map(_encodeSnapshot).toList(growable: false),
    });
  }

  /// Decodes only the current model-catalog schema.
  List<AgentModelCatalogSnapshot> decode(String source) {
    final root = decodeJsonObject(source, _document);
    requireVersion(root, currentVersion, _document);
    final entries = requireList(root['entries'], _document);
    final snapshots = <AgentModelCatalogSnapshot>[];
    final ids = <String>{};
    for (final entry in entries) {
      final snapshot = _decodeSnapshot(entry);
      final identity =
          '${snapshot.providerId}\u0000${snapshot.configFingerprint}'
          '\u0000${snapshot.includeHidden}';
      if (!ids.add(identity)) {
        duplicateIdentifier(_document);
      }
      snapshots.add(snapshot);
    }
    return List<AgentModelCatalogSnapshot>.unmodifiable(snapshots);
  }
}

/// Atomic file implementation of [AgentModelCatalogCacheStore].
final class FileAgentModelCatalogCacheStore
    implements AgentModelCatalogCacheStore {
  /// Creates a store for [file].
  FileAgentModelCatalogCacheStore({
    required File file,
    this._codec = const AgentModelCatalogCacheCodec(),
    AtomicTemporaryPathBuilder? temporaryPathBuilder,
    AtomicFileReplacer? replacer,
    AtomicTemporaryFileDeleter? temporaryFileDeleter,
  }) : _storage = AtomicTextFile(
         file,
         temporaryPathBuilder: temporaryPathBuilder,
         replacer: replacer,
         temporaryFileDeleter: temporaryFileDeleter,
       );

  final AgentModelCatalogCacheCodec _codec;
  final AtomicTextFile _storage;

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async {
    final source = await _storage.read();
    if (source == null) {
      return const <AgentModelCatalogSnapshot>[];
    }
    return _codec.decode(source);
  }

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) {
    return _storage.write(_codec.encode(snapshots));
  }
}

Map<String, Object?> _encodeSnapshot(AgentModelCatalogSnapshot snapshot) {
  return <String, Object?>{
    'providerId': snapshot.providerId,
    'configFingerprint': snapshot.configFingerprint,
    'includeHidden': snapshot.includeHidden,
    'fetchedAt': snapshot.fetchedAt.toUtc().toIso8601String(),
    'source': snapshot.source,
    'models': <String, Object?>{
      'items': snapshot.models.models.map(_encodeModel).toList(growable: false),
      'nextCursor': snapshot.models.nextCursor,
    },
  };
}

Map<String, Object?> _encodeModel(AgentModelInfo model) {
  return <String, Object?>{
    'id': model.id,
    'model': model.model,
    'displayName': model.displayName,
    'description': model.description,
    'hidden': model.hidden,
    'supportedReasoningEfforts': model.supportedReasoningEfforts
        .map(
          (effort) => <String, Object?>{
            'effort': effort.effort,
            'description': effort.description,
          },
        )
        .toList(growable: false),
    'defaultReasoningEffort': model.defaultReasoningEffort,
    'serviceTiers': model.serviceTiers
        .map(
          (tier) => <String, Object?>{
            'id': tier.id,
            'name': tier.name,
            'description': tier.description,
            'enabled': tier.enabled,
            'unavailableReason': tier.unavailableReason,
          },
        )
        .toList(growable: false),
    'defaultServiceTier': model.defaultServiceTier,
    'isDefault': model.isDefault,
    'enabled': model.enabled,
    'unavailableReason': model.unavailableReason,
    'contextWindowTokens': model.contextWindowTokens,
  };
}

AgentModelCatalogSnapshot _decodeSnapshot(Object? value) {
  final map = requireObject(value, _document);
  final modelDocument = requireObject(map['models'], _document);
  final models = requireList(
    modelDocument['items'],
    _document,
  ).map(_decodeModel).toList(growable: false);
  return AgentModelCatalogSnapshot(
    providerId: requireString(map['providerId'], _document),
    configFingerprint: requireString(map['configFingerprint'], _document),
    includeHidden: requireBool(map['includeHidden'], _document),
    models: AgentModelList(
      models: models,
      nextCursor: requireNullableString(
        modelDocument['nextCursor'],
        _document,
      ),
    ),
    fetchedAt: requireDateTime(map['fetchedAt'], _document),
    source: requireString(map['source'], _document),
  );
}

AgentModelInfo _decodeModel(Object? value) {
  final map = requireObject(value, _document);
  final efforts = requireList(map['supportedReasoningEfforts'], _document)
      .map((value) {
        final effort = requireObject(value, _document);
        return AgentModelReasoningEffort(
          effort: requireString(effort['effort'], _document),
          description: requireNullableString(
            effort['description'],
            _document,
          ),
        );
      })
      .toList(growable: false);
  final tiers = requireList(map['serviceTiers'], _document)
      .map((value) {
        final tier = requireObject(value, _document);
        return AgentModelServiceTier(
          id: requireString(tier['id'], _document),
          name: requireString(tier['name'], _document),
          description: requireNullableString(tier['description'], _document),
          enabled: requireBool(tier['enabled'], _document),
          unavailableReason: requireNullableString(
            tier['unavailableReason'],
            _document,
          ),
        );
      })
      .toList(growable: false);
  final contextWindowTokens = map['contextWindowTokens'];
  if (contextWindowTokens != null &&
      (contextWindowTokens is! int || contextWindowTokens <= 0)) {
    throw const AgentConfigDecodeException(
      document: _document,
      reason: AgentConfigDecodeReason.invalidShape,
    );
  }
  return AgentModelInfo(
    id: requireString(map['id'], _document),
    model: requireString(map['model'], _document),
    displayName: requireString(map['displayName'], _document),
    description: requireNullableString(map['description'], _document),
    hidden: requireBool(map['hidden'], _document),
    supportedReasoningEfforts: efforts,
    defaultReasoningEffort: requireNullableString(
      map['defaultReasoningEffort'],
      _document,
    ),
    serviceTiers: tiers,
    defaultServiceTier: requireNullableString(
      map['defaultServiceTier'],
      _document,
    ),
    isDefault: requireBool(map['isDefault'], _document),
    enabled: requireBool(map['enabled'], _document),
    unavailableReason: requireNullableString(
      map['unavailableReason'],
      _document,
    ),
    contextWindowTokens: contextWindowTokens as int?,
  );
}
