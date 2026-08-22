import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/src/mappers/agent_provider_payload.dart';

/// Claude Code 交互提问工具的协议名称。
const claudeCodeAskUserQuestionToolName = 'AskUserQuestion';

/// Claude Code 用户提问 control_request 的处理结果。
final class ClaudeCodeQuestionControlRequestResult {
  const ClaudeCodeQuestionControlRequestResult({
    required this.handled,
    this.responseFrame,
    this.events = const <AgentEvent>[],
  });

  const ClaudeCodeQuestionControlRequestResult.notHandled()
    : handled = false,
      responseFrame = null,
      events = const <AgentEvent>[];

  final bool handled;
  final Map<String, Object?>? responseFrame;
  final List<AgentEvent> events;
}

/// 已完成回答的 Claude Code 用户提问。
final class ClaudeCodeQuestionResponseResult {
  const ClaudeCodeQuestionResponseResult({
    required this.responseFrame,
    required this.requestId,
    required this.sessionId,
  });

  final Map<String, Object?> responseFrame;
  final String requestId;
  final String? sessionId;
}

/// 等待用户回答的 Claude Code 提问。
final class ClaudeCodePendingQuestion {
  const ClaudeCodePendingQuestion({
    required this.requestId,
    required this.toolUseId,
    required this.toolInput,
    required this.questions,
    this.sessionId,
    this.turnId,
  });

  final String requestId;
  final String toolUseId;
  final Map<String, Object?> toolInput;
  final List<AgentUserInputQaPair> questions;
  final String? sessionId;
  final String? turnId;
}

/// Claude Code `AskUserQuestion` 的独立请求、pending 与响应适配器。
///
/// CLI 在 stdio host 模式下把交互提问包在 `can_use_tool` control_request 中，
/// 但它不是权限审批。这里必须在普通权限 handler 之前接管，并通过
/// [AgentQuestionResponse] 把结构化 answers 写回 `updatedInput`。
final class ClaudeCodeQuestionAdapter {
  final Map<String, ClaudeCodePendingQuestion> _pending =
      <String, ClaudeCodePendingQuestion>{};

  int get pendingCount => _pending.length;

  Map<String, ClaudeCodePendingQuestion> get pending =>
      Map<String, ClaudeCodePendingQuestion>.unmodifiable(_pending);

  ClaudeCodeQuestionControlRequestResult handleControlRequest(
    Map<String, Object?> raw, {
    String? sessionId,
    String? turnId,
  }) {
    final request = _map(raw['request']);
    if (request?['subtype'] != 'can_use_tool' ||
        _string(request?['tool_name']) != claudeCodeAskUserQuestionToolName) {
      return const ClaudeCodeQuestionControlRequestResult.notHandled();
    }

    final requestId = _string(raw['request_id']);
    final toolUseId = _string(request?['tool_use_id']);
    final toolInput = _map(request?['input']);
    if (requestId == null || toolUseId == null || toolInput == null) {
      return ClaudeCodeQuestionControlRequestResult(
        handled: true,
        responseFrame: _errorFrame(
          requestId: requestId ?? 'missing-request-id',
          error: 'Zeta denied malformed AskUserQuestion request',
        ),
      );
    }

    final questions = _mapQuestions(toolInput['questions']);
    if (questions.isEmpty) {
      return ClaudeCodeQuestionControlRequestResult(
        handled: true,
        responseFrame: _errorFrame(
          requestId: requestId,
          error: 'Zeta denied AskUserQuestion without valid questions',
        ),
      );
    }

    final pending = ClaudeCodePendingQuestion(
      requestId: requestId,
      toolUseId: toolUseId,
      toolInput: Map<String, Object?>.unmodifiable(toolInput),
      questions: questions,
      sessionId: sessionId,
      turnId: turnId,
    );
    _pending[requestId] = pending;

    final title = questions.length == 1
        ? 'Agent requests input'
        : 'Agent requests input (${questions.length})';
    return ClaudeCodeQuestionControlRequestResult(
      handled: true,
      events: <AgentEvent>[
        AgentQuestionRequestedEvent(
          AgentQuestionRequest(
            id: requestId,
            title: title,
            questions: questions,
            sessionId: sessionId,
            turnId: turnId,
            raw: wrapAgentProviderPayload(<String, Object?>{
              'tool_name': claudeCodeAskUserQuestionToolName,
              'tool_use_id': toolUseId,
              'source': 'claude_code.can_use_tool',
            }),
          ),
        ),
      ],
    );
  }

  ClaudeCodeQuestionResponseResult? resolveResponse(
    AgentQuestionResponse response,
  ) {
    final pending = _pending.remove(response.requestId);
    if (pending == null) {
      return null;
    }

    final answers = <String, String>{};
    for (final question in pending.questions) {
      final values = <String>[
        for (final value in response.answers[question.questionId] ?? const [])
          if (value.trim().isNotEmpty) value.trim(),
      ];
      if (values.isEmpty) {
        continue;
      }
      answers[question.question] = question.allowMultiple
          ? values.join(', ')
          : values.first;
    }

    final updatedInput = <String, Object?>{
      ...pending.toolInput,
      'answers': Map<String, String>.unmodifiable(answers),
    };
    return ClaudeCodeQuestionResponseResult(
      responseFrame: _successFrame(
        requestId: pending.requestId,
        response: <String, Object?>{
          'behavior': 'allow',
          'updatedInput': updatedInput,
        },
      ),
      requestId: pending.requestId,
      sessionId: pending.sessionId,
    );
  }

  /// turn 已结束时释放尚未回答的提问，避免中断后的 pending 泄漏到下一回合。
  List<ClaudeCodePendingQuestion> completeTurn({
    required String sessionId,
    required String turnId,
  }) {
    final completed = _pending.values
        .where((item) => item.sessionId == sessionId && item.turnId == turnId)
        .toList(growable: false);
    for (final item in completed) {
      _pending.remove(item.requestId);
    }
    return completed;
  }

  void clear() => _pending.clear();

  static List<AgentUserInputQaPair> _mapQuestions(Object? raw) {
    if (raw is! List) {
      return const <AgentUserInputQaPair>[];
    }
    final questions = <AgentUserInputQaPair>[];
    for (final value in raw) {
      final question = _map(value);
      if (question == null) {
        continue;
      }
      final questionText = _string(question['question']);
      if (questionText == null) {
        continue;
      }
      final optionItems = <AgentUserInputOption>[];
      final options = question['options'];
      if (options is List) {
        for (final value in options) {
          final option = _map(value);
          final label = _string(option?['label']);
          if (label == null) {
            continue;
          }
          optionItems.add(
            AgentUserInputOption(
              id: label,
              label: label,
              description: _string(option?['description']),
            ),
          );
        }
      }
      questions.add(
        AgentUserInputQaPair(
          questionId: questionText,
          question: questionText,
          header: _string(question['header']),
          optionItems: List<AgentUserInputOption>.unmodifiable(optionItems),
          allowMultiple: question['multiSelect'] == true,
          // Claude Code 的问题面板始终支持 Other 自由文本。
          isOther: true,
        ),
      );
    }
    return List<AgentUserInputQaPair>.unmodifiable(questions);
  }

  static Map<String, Object?> _successFrame({
    required String requestId,
    required Map<String, Object?> response,
  }) {
    return <String, Object?>{
      'type': 'control_response',
      'response': <String, Object?>{
        'subtype': 'success',
        'request_id': requestId,
        'response': response,
      },
    };
  }

  static Map<String, Object?> _errorFrame({
    required String requestId,
    required String error,
  }) {
    return <String, Object?>{
      'type': 'control_response',
      'response': <String, Object?>{
        'subtype': 'error',
        'request_id': requestId,
        'error': error,
      },
    };
  }

  static String? _string(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Map<String, Object?>? _map(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    return null;
  }
}
