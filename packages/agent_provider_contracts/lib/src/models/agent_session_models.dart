import 'package:agent_provider_contracts/src/models/immutable_collections.dart';

/// 一条 Agent 会话，对应 Codex app-server 的 thread。
final class AgentSession {
  AgentSession({
    required this.id,
    required this.providerId,
    this.title,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : raw = immutableJsonMap(raw);

  /// provider 会话 id；Codex 中对应 thread id。
  final String id;

  /// 创建该会话的 provider id。
  final String providerId;

  /// provider 返回的可选标题。
  final String? title;

  /// 原始协议 payload，便于调试和未来补充字段。
  final Map<String, Object?> raw;
}

/// 一次用户请求或 steer，对应 Codex app-server 的 turn。
final class AgentTurn {
  AgentTurn({
    required this.id,
    required this.sessionId,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : raw = immutableJsonMap(raw);

  /// provider 回合 id；Codex 中对应 turn id。
  final String id;

  /// 回合所属会话 id。
  final String sessionId;

  /// 原始协议 payload。
  final Map<String, Object?> raw;
}
