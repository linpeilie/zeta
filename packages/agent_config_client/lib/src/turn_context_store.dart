import 'dart:convert';
import 'dart:io';

import 'package:agent_config_client/src/agent_config_decode_exception.dart';
import 'package:agent_config_client/src/codec_support.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:zeta_storage/zeta_storage.dart';

const AgentConfigDocumentKind _document = AgentConfigDocumentKind.turnContext;

/// Persistence boundary for per-thread, allowlisted turn metadata.
abstract interface class AgentTurnContextStore {
  /// Loads one thread context, or `null` when it has not been persisted.
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  });

  /// Atomically saves a complete thread context.
  Future<void> save(AgentThreadTurnContext context);
}

/// Current-schema JSON codec for [AgentThreadTurnContext].
final class AgentTurnContextCodec {
  /// Creates a current-schema codec.
  const AgentTurnContextCodec();

  /// Encodes allowlisted turn metadata only.
  String encode(AgentThreadTurnContext context) {
    if (context.version != AgentThreadTurnContext.currentVersion) {
      throw const AgentConfigDecodeException(
        document: _document,
        reason: AgentConfigDecodeReason.unsupportedVersion,
      );
    }
    return jsonEncode(<String, Object?>{
      'version': AgentThreadTurnContext.currentVersion,
      'providerId': context.providerId,
      'threadId': context.threadId,
      'turns': context.turns.map(_encodeTurn).toList(growable: false),
    });
  }

  /// Decodes only the current turn-context schema.
  AgentThreadTurnContext decode(String source) {
    final root = decodeJsonObject(source, _document);
    requireVersion(
      root,
      AgentThreadTurnContext.currentVersion,
      _document,
    );
    final turns = <AgentTurnContextRecord>[];
    final ids = <String>{};
    for (final value in requireList(root['turns'], _document)) {
      final turn = _decodeTurn(value);
      if (!ids.add(turn.turnId)) {
        duplicateIdentifier(_document);
      }
      turns.add(turn);
    }
    return AgentThreadTurnContext(
      providerId: requireString(root['providerId'], _document),
      threadId: requireString(root['threadId'], _document),
      turns: turns,
    );
  }
}

/// File implementation rooted at `state/session/<provider>/<thread>.json`.
final class FileAgentTurnContextStore implements AgentTurnContextStore {
  /// Creates a store below the supplied root directory.
  FileAgentTurnContextStore({
    required this._rootDirectory,
    this._codec = const AgentTurnContextCodec(),
  });

  final Directory _rootDirectory;
  final AgentTurnContextCodec _codec;
  final Map<String, AtomicTextFile> _files = <String, AtomicTextFile>{};

  @override
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  }) async {
    final normalizedProviderId = providerId.trim();
    final normalizedThreadId = threadId.trim();
    final source = await _fileFor(
      normalizedProviderId,
      normalizedThreadId,
    ).read();
    if (source == null) {
      return null;
    }
    final context = _codec.decode(source);
    if (context.providerId != normalizedProviderId ||
        context.threadId != normalizedThreadId) {
      throw const AgentConfigDecodeException(
        document: _document,
        reason: AgentConfigDecodeReason.identityMismatch,
      );
    }
    return context;
  }

  @override
  Future<void> save(AgentThreadTurnContext context) {
    return _fileFor(context.providerId, context.threadId).write(
      _codec.encode(context),
    );
  }

  AtomicTextFile _fileFor(String providerId, String threadId) {
    final providerSegment = encodeAgentTurnContextPathSegment(providerId);
    final threadSegment = encodeAgentTurnContextPathSegment(threadId);
    if (providerSegment == null || threadSegment == null) {
      throw StoragePathException(
        path: '<agent-turn-context>',
        cause: ArgumentError('Unsafe Agent turn-context identifier'),
      );
    }
    final path = <String>[
      _rootDirectory.path,
      providerSegment,
      '$threadSegment.json',
    ].join(Platform.pathSeparator);
    return _files.putIfAbsent(path, () => AtomicTextFile(File(path)));
  }
}

Map<String, Object?> _encodeTurn(AgentTurnContextRecord turn) {
  return <String, Object?>{
    'turnId': turn.turnId,
    'modelId': turn.modelId,
    'reasoningEffort': turn.reasoningEffort,
    'serviceTierId': turn.serviceTierId,
    'explicitFast': turn.explicitFast,
    'startedAt': turn.startedAt?.toUtc().toIso8601String(),
    'completedAt': turn.completedAt?.toUtc().toIso8601String(),
    'status': turn.status?.name,
  };
}

AgentTurnContextRecord _decodeTurn(Object? value) {
  final map = requireObject(value, _document);
  return AgentTurnContextRecord(
    turnId: requireString(map['turnId'], _document),
    modelId: requireNullableString(map['modelId'], _document),
    reasoningEffort: requireNullableString(map['reasoningEffort'], _document),
    serviceTierId: requireNullableString(map['serviceTierId'], _document),
    explicitFast: _nullableBool(map['explicitFast']),
    startedAt: _nullableDateTime(map['startedAt']),
    completedAt: _nullableDateTime(map['completedAt']),
    status: _nullableStatus(map['status']),
  );
}

bool? _nullableBool(Object? value) {
  if (value == null) {
    return null;
  }
  return requireBool(value, _document);
}

DateTime? _nullableDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  return requireDateTime(value, _document);
}

AgentHistoryTurnStatus? _nullableStatus(Object? value) {
  if (value == null) {
    return null;
  }
  final name = requireString(value, _document);
  final matches = AgentHistoryTurnStatus.values.where(
    (status) => status.name == name,
  );
  if (matches.length != 1) {
    throw const AgentConfigDecodeException(
      document: _document,
      reason: AgentConfigDecodeReason.invalidShape,
    );
  }
  return matches.single;
}

/// Encodes a Provider or thread id into one traversal-safe path segment.
String? encodeAgentTurnContextPathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 128 ||
      trimmed.contains('\n') ||
      trimmed.contains('\r') ||
      trimmed.contains('\u0000')) {
    return null;
  }
  final encoded = Uri.encodeComponent(trimmed);
  return encoded == '.' || encoded == '..' ? null : encoded;
}
