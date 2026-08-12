import 'dart:convert';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 测试用的中立文件变更 envelope。
///
/// 它只投影 Provider 已经规范化完成的 typed event，避免共享 Buffer/Pipeline
/// 合同测试读取 Provider raw payload 或引入 Provider adapter。
final class AgentFileChangeCanonicalEnvelope {
  const AgentFileChangeCanonicalEnvelope({
    required this.ownerType,
    required this.ownerId,
    required this.sessionId,
    required this.turnId,
    required this.status,
    required this.snapshot,
  });

  final String ownerType;
  final String ownerId;
  final String? sessionId;
  final String? turnId;
  final String status;
  final AgentFileChangeSnapshot snapshot;

  /// owner、终态与完整 snapshot 的稳定签名；session/turn scope 不参与跨路径
  /// 比较，因为 history 可合法使用自己的本地 turn identity。
  String get signature => jsonEncode(<String, Object?>{
    'ownerType': ownerType,
    'ownerId': ownerId,
    'status': status,
    'snapshot': _canonicalSnapshot(snapshot),
  });

  /// 对完整累计 snapshot 做稳定投影，便于逐次确认 detail/status/terminal
  /// 携带的是同一份证据，而不是仅含本次增量的 partial payload。
  String get snapshotSignature => canonicalAgentFileChangeSnapshot(snapshot);
}

/// 把一个带 typed snapshot 的 tool 投影为 canonical envelope。
AgentFileChangeCanonicalEnvelope canonicalFileChangeToolCall(
  AgentToolCall toolCall,
) {
  final snapshot = toolCall.fileChanges;
  if (snapshot == null) {
    throw StateError('tool ${toolCall.id} does not carry file changes');
  }
  return AgentFileChangeCanonicalEnvelope(
    ownerType: 'tool',
    ownerId: toolCall.id,
    sessionId: toolCall.sessionId,
    turnId: toolCall.turnId,
    status: toolCall.status.name,
    snapshot: snapshot,
  );
}

/// 从中立事件序列提取所有明确携带文件变更 snapshot 的 owner envelope。
List<AgentFileChangeCanonicalEnvelope> canonicalFileChangeEnvelopes(
  Iterable<AgentEvent> events,
) {
  final envelopes = <AgentFileChangeCanonicalEnvelope>[];
  for (final event in events) {
    if (event is AgentToolCallEvent) {
      final toolCall = event.toolCall;
      final snapshot = toolCall.fileChanges;
      if (snapshot == null) {
        continue;
      }
      envelopes.add(canonicalFileChangeToolCall(toolCall));
      continue;
    }
    if (event is AgentTurnFileChangesEvent) {
      envelopes.add(
        AgentFileChangeCanonicalEnvelope(
          ownerType: 'turn',
          ownerId: event.turnId,
          sessionId: event.sessionId,
          turnId: event.turnId,
          status: 'snapshot',
          snapshot: event.snapshot,
        ),
      );
    }
  }
  return List<AgentFileChangeCanonicalEnvelope>.unmodifiable(envelopes);
}

/// 把中立 snapshot 规范化为稳定签名；字段顺序固定，证据正文仅来自脱敏 fixture。
String canonicalAgentFileChangeSnapshot(AgentFileChangeSnapshot snapshot) {
  return jsonEncode(_canonicalSnapshot(snapshot));
}

Map<String, Object?> _canonicalSnapshot(AgentFileChangeSnapshot snapshot) {
  return <String, Object?>{
    'revision': snapshot.revision,
    'replayability': snapshot.replayability.name,
    'changes': <Object?>[
      for (final change in snapshot.changes)
        <String, Object?>{
          'id': change.id,
          'path': change.path,
          'destinationPath': change.destinationPath,
          'kind': change.kind.name,
          'evidence': _canonicalEvidence(change.evidence),
        },
    ],
  };
}

Object? _canonicalEvidence(AgentFileChangeEvidence? evidence) {
  return switch (evidence) {
    null => null,
    AgentTextReplacementEvidence(
      :final oldText,
      :final newText,
      :final replaceAll,
    ) =>
      <String, Object?>{
        'type': 'textReplacement',
        'oldText': oldText,
        'newText': newText,
        'replaceAll': replaceAll,
      },
    AgentWrittenContentEvidence(:final content) => <String, Object?>{
      'type': 'writtenContent',
      'content': content,
    },
    AgentUnifiedPatchEvidence(:final patch) => <String, Object?>{
      'type': 'unifiedPatch',
      'patch': patch,
    },
  };
}
