import 'package:zeta/src/features/agent/data/mappers/acp_session_update_mapper.dart';

export 'package:zeta/src/features/agent/data/mappers/acp_session_update_mapper.dart'
    show AcpMappedUpdate, GrokAcpMappedUpdate;

/// Grok ACP 通知适配层。
///
/// 标准 `session/update` 委托给共享 mapper；这里只保留 `_x.ai/*` 厂商扩展入口。
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
      params: params,
      runningTurnId: runningTurnId,
    );
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
