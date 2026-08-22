import 'package:zeta_agent_core/src/domain/agent_turn_history_models.dart';

/// Agent 向用户发出的独立提问请求。
///
/// 该模型不表达 approve/deny 语义；用户可以提交结构化答案，或用空答案跳过。
final class AgentQuestionRequest {
  const AgentQuestionRequest({
    required this.id,
    required this.title,
    required this.questions,
    this.description,
    this.sessionId,
    this.turnId,
    this.raw = const <String, Object?>{},
  });

  /// UI 和响应端口使用的稳定请求 id。
  final String id;

  /// 提问卡片标题。
  final String title;

  /// 可选的请求说明。
  final String? description;

  /// 待回答的问题列表。
  final List<AgentUserInputQaPair> questions;

  /// 可选会话 id，用于把实时事件路由到当前 thread。
  final String? sessionId;

  /// 可选回合 id，用于把实时事件路由到当前 turn。
  final String? turnId;

  /// Provider 原始请求，仅用于 data/application 诊断。
  final Map<String, Object?> raw;
}

/// 用户对独立提问请求的结构化回答。
final class AgentQuestionResponse {
  const AgentQuestionResponse({
    required this.requestId,
    this.answers = const <String, List<String>>{},
  });

  /// 对应 [AgentQuestionRequest.id]。
  final String requestId;

  /// questionId → 稳定选项 id 或自由文本；空 map 表示跳过。
  final Map<String, List<String>> answers;
}
