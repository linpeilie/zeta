import 'package:agent_provider_contracts/src/models/agent_turn_history_models.dart';
import 'package:agent_provider_contracts/src/models/immutable_collections.dart';

/// App-owned question request title variants.
enum AgentQuestionTitleCode { agentRequestsInput }

/// Agent 向用户发出的独立提问请求。
///
/// 该模型不表达 approve/deny 语义；用户可以提交结构化答案，或用空答案跳过。
final class AgentQuestionRequest {
  AgentQuestionRequest({
    required this.id,
    required List<AgentUserInputQaPair> questions,
    this.title,
    this.titleCode,
    this.description,
    this.sessionId,
    this.turnId,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : assert(
         title != null || titleCode != null,
         'A provider title or app-owned title code is required.',
       ),
       questions = immutableList(questions),
       raw = immutableJsonMap(raw);

  /// UI 和响应端口使用的稳定请求 id。
  final String id;

  /// 提问卡片标题。
  final String? title;

  /// App-owned title variant mapped by Presentation.
  final AgentQuestionTitleCode? titleCode;

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
  AgentQuestionResponse({
    required this.requestId,
    Map<String, List<String>> answers = const <String, List<String>>{},
  }) : answers = immutableListMap(answers);

  /// 对应 [AgentQuestionRequest.id]。
  final String requestId;

  /// questionId → 稳定选项 id 或自由文本；空 map 表示跳过。
  final Map<String, List<String>> answers;
}
