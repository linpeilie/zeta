import 'package:zeta/src/features/agent/data/mappers/acp_session_update_mapper.dart';

export 'package:zeta/src/features/agent/data/mappers/acp_session_update_mapper.dart'
    show AcpMappedUpdate, GrokAcpMappedUpdate;

/// Grok ACP 通知适配层。
///
/// 标准 `session/update` 委托给共享 mapper；这里只保留 Grok 元数据归一化和
/// `_x.ai/*` 厂商扩展入口。
class GrokAcpNotificationMapper {
  const GrokAcpNotificationMapper({
    this.sessionUpdateMapper = const AcpSessionUpdateMapper(),
  });

  final AcpSessionUpdateMapper sessionUpdateMapper;

  GrokAcpMappedUpdate mapSessionUpdate({
    required Map<String, Object?> params,
    required String? runningTurnId,
  }) {
    return sessionUpdateMapper.mapSessionUpdate(
      params: _normalizeStreamMessageId(params),
      runningTurnId: runningTurnId,
    );
  }

  /// Grok 不发送 `messageId`，但会用 `eventId` 标识每段独立正文。
  ///
  /// 若直接回退到 prompt/turn id，工具调用前后的文字会被合并回第一条消息，
  /// 导致中间工具卡片最终全部落在完整回复之后。这里与本地历史解析保持一致，
  /// 将 Grok 的事件标识投影为标准 ACP message id。
  Map<String, Object?> _normalizeStreamMessageId(Map<String, Object?> params) {
    final updateRaw = params['update'];
    if (updateRaw is! Map) {
      return params;
    }
    final update = updateRaw.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    final kind = update['sessionUpdate']?.toString();
    // thought chunk 必须继续按 prompt/turn 聚合；eventId 是单次事件标识，
    // 用它切分会把一次连续推理膨胀成几十个「思考」条目。
    if (kind != 'agent_message_chunk') {
      return params;
    }
    final messageId = update['messageId']?.toString().trim();
    if (messageId != null && messageId.isNotEmpty) {
      return params;
    }

    final paramsMeta = _asStringKeyedMap(params['_meta']);
    final updateMeta = _asStringKeyedMap(update['_meta']);
    final eventId =
        paramsMeta?['eventId']?.toString().trim() ??
        updateMeta?['eventId']?.toString().trim();
    if (eventId == null || eventId.isEmpty) {
      return params;
    }
    return <String, Object?>{
      ...params,
      'update': <String, Object?>{...update, 'messageId': eventId},
    };
  }

  /// 映射 `_x.ai/session/update` 中与回合完成相关的扩展。
  GrokAcpMappedUpdate mapXaiSessionUpdate({
    required Map<String, Object?> params,
    required String? runningTurnId,
  }) {
    final updateRaw = params['update'];
    if (updateRaw is! Map) {
      return const AcpMappedUpdate(
        unmatchedKind: '_x.ai/session/update:missing',
      );
    }
    final update = updateRaw.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    final kind = update['sessionUpdate']?.toString() ?? '';
    if (kind != 'turn_completed') {
      return AcpMappedUpdate(unmatchedKind: kind);
    }
    return sessionUpdateMapper.mapTurnCompleted(
      params: params,
      update: update,
      runningTurnId: runningTurnId,
    );
  }
}

Map<String, Object?>? _asStringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}
