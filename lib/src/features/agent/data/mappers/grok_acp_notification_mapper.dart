import 'package:zeta/src/features/agent/data/mappers/grok_session_update_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_stream_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/fallback_agent_ui_text_catalog.dart';

export 'package:zeta/src/features/agent/data/mappers/grok_session_update_mapper.dart'
    show GrokAcpMappedUpdate, GrokSessionUpdateMapper;
export 'package:zeta/src/features/agent/data/mappers/grok_stream_identity.dart'
    show
        GrokIdentityInvalidationReason,
        GrokNarrativeBoundaryKind,
        GrokStreamIdentityDiagnostics,
        GrokTerminalSource,
        GrokTurnIdentitySnapshot;

/// Grok ACP 通知适配门面。
///
/// 标准 `session/update` 与 `_x.ai/session/update` 共用同一个有状态 Grok adapter，
/// 叙事 identity 完全由 Grok 专属 mapper/reducer 决定。
final class GrokAcpNotificationMapper {
  GrokAcpNotificationMapper({
    GrokSessionUpdateMapper? sessionUpdateMapper,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
  }) : sessionUpdateMapper =
           sessionUpdateMapper ??
           GrokSessionUpdateMapper(textCatalog: textCatalog);

  final GrokSessionUpdateMapper sessionUpdateMapper;

  GrokStreamIdentityDiagnostics get diagnostics =>
      sessionUpdateMapper.diagnostics;

  int beginTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) => sessionUpdateMapper.beginTurn(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    turnId: turnId,
  );

  GrokAcpMappedUpdate mapSessionUpdate({
    required Map<String, Object?> params,
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
  }) => sessionUpdateMapper.mapSessionUpdate(
    params: params,
    runningTurnId: runningTurnId,
    runtimeScope: runtimeScope,
  );

  /// 将 `_x.ai/session/update` 送入与标准通知相同的 session/turn reducer。
  GrokAcpMappedUpdate mapXaiSessionUpdate({
    required Map<String, Object?> params,
    required String? runningTurnId,
    required AgentRuntimeScope runtimeScope,
  }) => sessionUpdateMapper.mapSessionUpdate(
    params: params,
    runningTurnId: runningTurnId,
    runtimeScope: runtimeScope,
    terminalSource: GrokTerminalSource.xaiNotification,
  );

  GrokAcpMappedUpdate mapPromptTerminal({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
    required String stopReason,
    required GrokTerminalSource source,
    String? errorMessage,
    Map<String, Object?> raw = const <String, Object?>{},
  }) => sessionUpdateMapper.mapPromptTerminal(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    turnId: turnId,
    stopReason: stopReason,
    source: source,
    errorMessage: errorMessage,
    raw: raw,
  );

  bool noteBoundary({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required GrokNarrativeBoundaryKind kind,
  }) => sessionUpdateMapper.noteBoundary(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    runningTurnId: runningTurnId,
    kind: kind,
  );

  void invalidateTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required GrokIdentityInvalidationReason reason,
  }) => sessionUpdateMapper.invalidateTurn(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    runningTurnId: runningTurnId,
    promptId: promptId,
    reason: reason,
  );

  void invalidateRuntime({
    required AgentRuntimeScope runtimeScope,
    required GrokIdentityInvalidationReason reason,
  }) => sessionUpdateMapper.invalidateRuntime(
    runtimeScope: runtimeScope,
    reason: reason,
  );

  void invalidateSession({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required GrokIdentityInvalidationReason reason,
  }) => sessionUpdateMapper.invalidateSession(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    reason: reason,
  );

  GrokTurnIdentitySnapshot? snapshot({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) => sessionUpdateMapper.snapshot(
    runtimeScope: runtimeScope,
    sessionId: sessionId,
    turnId: turnId,
  );

  void dispose() => sessionUpdateMapper.dispose();
}
