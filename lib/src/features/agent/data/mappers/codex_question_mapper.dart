part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// 映射 Codex 独立用户提问，并编码严格的 answers 响应。
class _CodexQuestionMapper {
  _MappedQuestionRequest mapRequest(JsonRpcRequest request) {
    final id = '${request.id}';
    return _MappedQuestionRequest(
      pendingQuestion: _PendingQuestion(
        id: id,
        requestId: request.id,
        runtimeScope: request.runtimeScope,
        params: request.params,
      ),
      event: AgentQuestionRequestedEvent(
        AgentQuestionRequest(
          id: id,
          title: 'Agent requests input',
          description: _string(request.params['reason']),
          questions: _userInputQaPairs(request.params),
          sessionId: _string(request.params['threadId']),
          turnId: _string(request.params['turnId']),
          raw: request.params,
        ),
      ),
    );
  }

  /// 编码 `ToolRequestUserInputResponse`；协议没有 approve/deny 变体。
  Object response(AgentQuestionResponse response) {
    return <String, Object?>{'answers': _encodeAnswers(response.answers)};
  }

  Map<String, Object?> _encodeAnswers(Map<String, List<String>> answers) {
    final encoded = <String, Object?>{};
    for (final entry in answers.entries) {
      if (entry.key.isEmpty || entry.value.isEmpty) {
        continue;
      }
      encoded[entry.key] = <String, Object?>{
        'answers': List<String>.unmodifiable(entry.value),
      };
    }
    return encoded;
  }
}

class _MappedQuestionRequest {
  const _MappedQuestionRequest({
    required this.pendingQuestion,
    required this.event,
  });

  final _PendingQuestion pendingQuestion;
  final AgentQuestionRequestedEvent event;
}

/// 一个尚未回复的 app-server 用户提问请求。
class _PendingQuestion {
  const _PendingQuestion({
    required this.id,
    required this.requestId,
    required this.runtimeScope,
    required this.params,
  });

  final String id;
  final Object requestId;
  final AgentRuntimeScope? runtimeScope;
  final Map<String, Object?> params;
}
