import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// `~/.zeta/cache/agent_models_v1.json` 的文件缓存实现。
class FileAgentModelCatalogCacheStore implements AgentModelCatalogCacheStore {
  FileAgentModelCatalogCacheStore({required File file})
    : _storage = AtomicTextFile(file);

  static const int _version = 1;
  final AtomicTextFile _storage;

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async {
    try {
      final content = await _storage.read();
      if (content == null || content.trim().isEmpty) {
        return const <AgentModelCatalogSnapshot>[];
      }
      final root = _objectMap(jsonDecode(content));
      if (root['version'] != _version || root['entries'] is! List<Object?>) {
        return const <AgentModelCatalogSnapshot>[];
      }
      final snapshots = <AgentModelCatalogSnapshot>[];
      for (final item in root['entries']! as List<Object?>) {
        final snapshot = _decodeSnapshot(item);
        if (snapshot != null) {
          snapshots.add(snapshot);
        }
      }
      return List<AgentModelCatalogSnapshot>.unmodifiable(snapshots);
    } on IOException {
      return const <AgentModelCatalogSnapshot>[];
    } on FormatException {
      return const <AgentModelCatalogSnapshot>[];
    }
  }

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) {
    return _storage.write(
      jsonEncode(<String, Object?>{
        'version': _version,
        'entries': snapshots.map(_encodeSnapshot).toList(growable: false),
      }),
    );
  }
}

/// 不访问用户文件的内存缓存，供测试和嵌入式宿主使用。
class MemoryAgentModelCatalogCacheStore implements AgentModelCatalogCacheStore {
  MemoryAgentModelCatalogCacheStore([
    List<AgentModelCatalogSnapshot> snapshots =
        const <AgentModelCatalogSnapshot>[],
  ]) : _snapshots = List<AgentModelCatalogSnapshot>.from(snapshots);

  List<AgentModelCatalogSnapshot> _snapshots;

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async =>
      List<AgentModelCatalogSnapshot>.unmodifiable(_snapshots);

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) async {
    _snapshots = List<AgentModelCatalogSnapshot>.from(snapshots);
  }
}

Map<String, Object?> _encodeSnapshot(AgentModelCatalogSnapshot snapshot) {
  return <String, Object?>{
    'providerId': snapshot.providerId,
    'configFingerprint': snapshot.configFingerprint,
    'includeHidden': snapshot.includeHidden,
    'fetchedAt': snapshot.fetchedAt.toUtc().toIso8601String(),
    'source': snapshot.source,
    'models': snapshot.models.models.map(_encodeModel).toList(growable: false),
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

AgentModelCatalogSnapshot? _decodeSnapshot(Object? value) {
  final map = _objectMap(value);
  final providerId = _string(map['providerId']);
  final fingerprint = _string(map['configFingerprint']);
  final fetchedAt = DateTime.tryParse(_string(map['fetchedAt']) ?? '');
  final source = _string(map['source']);
  final rawModels = map['models'];
  if (providerId == null ||
      fingerprint == null ||
      fetchedAt == null ||
      source == null ||
      rawModels is! List<Object?>) {
    return null;
  }
  final models = <AgentModelInfo>[];
  for (final item in rawModels) {
    final model = _decodeModel(item);
    if (model != null) {
      models.add(model);
    }
  }
  return AgentModelCatalogSnapshot(
    providerId: providerId,
    configFingerprint: fingerprint,
    includeHidden: map['includeHidden'] == true,
    models: AgentModelList(models: List<AgentModelInfo>.unmodifiable(models)),
    fetchedAt: fetchedAt.toUtc(),
    source: source,
  );
}

AgentModelInfo? _decodeModel(Object? value) {
  final map = _objectMap(value);
  final id = _string(map['id']);
  final model = _string(map['model']);
  final displayName = _string(map['displayName']);
  if (id == null || model == null || displayName == null) {
    return null;
  }

  final efforts = <AgentModelReasoningEffort>[];
  final rawEfforts = map['supportedReasoningEfforts'];
  if (rawEfforts is List<Object?>) {
    for (final item in rawEfforts) {
      final effortMap = _objectMap(item);
      final effort = _string(effortMap['effort']);
      if (effort != null) {
        efforts.add(
          AgentModelReasoningEffort(
            effort: effort,
            description: _string(effortMap['description']),
          ),
        );
      }
    }
  }

  final tiers = <AgentModelServiceTier>[];
  final rawTiers = map['serviceTiers'];
  if (rawTiers is List<Object?>) {
    for (final item in rawTiers) {
      final tierMap = _objectMap(item);
      final tierId = _string(tierMap['id']);
      final name = _string(tierMap['name']);
      if (tierId != null && name != null) {
        tiers.add(
          AgentModelServiceTier(
            id: tierId,
            name: name,
            description: _string(tierMap['description']),
            enabled: tierMap['enabled'] != false,
            unavailableReason: _string(tierMap['unavailableReason']),
          ),
        );
      }
    }
  }

  final contextWindow = map['contextWindowTokens'];
  return AgentModelInfo(
    id: id,
    model: model,
    displayName: displayName,
    description: _string(map['description']),
    hidden: map['hidden'] == true,
    supportedReasoningEfforts: List<AgentModelReasoningEffort>.unmodifiable(
      efforts,
    ),
    defaultReasoningEffort: _string(map['defaultReasoningEffort']),
    serviceTiers: List<AgentModelServiceTier>.unmodifiable(tiers),
    defaultServiceTier: _string(map['defaultServiceTier']),
    isDefault: map['isDefault'] == true,
    enabled: map['enabled'] != false,
    unavailableReason: _string(map['unavailableReason']),
    contextWindowTokens: contextWindow is int && contextWindow > 0
        ? contextWindow
        : null,
  );
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}

String? _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value;
}
