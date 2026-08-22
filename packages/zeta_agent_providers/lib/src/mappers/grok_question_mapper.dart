import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 映射 Grok ACP 扩展 `_x.ai/ask_user_question` / `x.ai/ask_user_question`。
///
/// 请求形状对齐 shell 的 `AskUserQuestionExtRequest`（sessionId / toolCallId /
/// questions 为主字段）。问题与选项通常没有稳定 id，优先用文案本身作为
/// [AgentUserInputQaPair.questionId] 与 [AgentUserInputOption.id]，保证 UI 选中值
/// 能原样回写。
///
/// 响应形状对齐 `AskUserQuestionExtResponse` 内部标签枚举：
/// - `accepted`：完整作答（`answers` + 可选 `partial_answers`）
/// - `skip_interview`：用户跳过（空 answers）
final class GrokQuestionMapper {
  const GrokQuestionMapper();

  /// 是否为 Grok 结构化用户提问扩展方法（含 `_x.ai/` 与 `x.ai/` 前缀）。
  static bool isAskUserQuestionMethod(String method) {
    return method == '_x.ai/ask_user_question' ||
        method == 'x.ai/ask_user_question';
  }

  /// 将 ext_method 参数映射为中立提问事件。
  ///
  /// [requestId] 为 JSON-RPC id；领域请求 id 优先使用 `toolCallId`，与 plan
  /// 审批一致，便于 cancel/替换时对账。
  GrokMappedQuestionRequest mapRequest({
    required Object requestId,
    required Map<String, Object?> params,
    String? runningTurnId,
  }) {
    final sessionId = _string(params['sessionId']);
    final toolCallId = _string(params['toolCallId']);
    final domainId = (toolCallId != null && toolCallId.isNotEmpty)
        ? toolCallId
        : requestId.toString();
    final questions = _mapQuestions(params['questions']);
    final title = questions.length <= 1
        ? 'Agent requests input'
        : 'Agent requests input (${questions.length})';

    return GrokMappedQuestionRequest(
      pending: GrokPendingQuestion(
        id: domainId,
        requestId: requestId,
        sessionId: sessionId,
        questions: questions,
      ),
      event: AgentQuestionRequestedEvent(
        AgentQuestionRequest(
          id: domainId,
          title: title,
          description: _string(params['reason']) ?? _string(params['title']),
          questions: questions,
          sessionId: sessionId,
          turnId: runningTurnId,
          raw: AgentProviderRawPayload.wrap(
            Map<String, Object?>.unmodifiable(params),
          ),
        ),
      ),
    );
  }

  /// 编码 JSON-RPC result。
  ///
  /// 空 [AgentQuestionResponse.answers] 表示 Skip → `skip_interview`。
  /// 非空时按 questionId（即问题文案）组装 `accepted.answers`；单选压成 string，
  /// 多选保留 string 列表，兼容 shell 的 `StringOrVec`。
  Object response(
    AgentQuestionResponse response, {
    required GrokPendingQuestion pending,
  }) {
    if (response.answers.isEmpty) {
      return const <String, Object?>{'type': 'skip_interview'};
    }

    final allowMultipleById = <String, bool>{
      for (final question in pending.questions)
        question.questionId: question.allowMultiple,
    };
    final answers = <String, Object?>{};
    for (final entry in response.answers.entries) {
      final questionId = entry.key.trim();
      if (questionId.isEmpty) {
        continue;
      }
      final values = <String>[
        for (final value in entry.value)
          if (value.trim().isNotEmpty) value.trim(),
      ];
      if (values.isEmpty) {
        continue;
      }
      final multi = allowMultipleById[questionId] == true;
      answers[questionId] = multi
          ? List<String>.unmodifiable(values)
          : values.first;
    }

    if (answers.isEmpty) {
      return const <String, Object?>{'type': 'skip_interview'};
    }

    return <String, Object?>{
      'type': 'accepted',
      'answers': answers,
      'partial_answers': const <String, Object?>{},
    };
  }

  List<AgentUserInputQaPair> _mapQuestions(Object? raw) {
    if (raw is! List) {
      return const <AgentUserInputQaPair>[];
    }
    final pairs = <AgentUserInputQaPair>[];
    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];
      if (item is! Map) {
        continue;
      }
      final map = item.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
      final questionText =
          _string(map['question']) ??
          _string(map['header']) ??
          _string(map['id']);
      if (questionText == null || questionText.isEmpty) {
        continue;
      }
      final explicitId = _string(map['id']);
      final questionId = (explicitId != null && explicitId.isNotEmpty)
          ? explicitId
          : questionText;
      final header = _string(map['header']);
      final allowMultiple =
          map['multiSelect'] == true ||
          map['multi_select'] == true ||
          map['allowMultiple'] == true;

      final optionItems = <AgentUserInputOption>[];
      final optionLabels = <String>[];
      final optionsRaw = map['options'];
      if (optionsRaw is List) {
        for (final optionValue in optionsRaw) {
          if (optionValue is! Map) {
            final label = optionValue?.toString().trim();
            if (label == null || label.isEmpty) {
              continue;
            }
            optionLabels.add(label);
            optionItems.add(AgentUserInputOption(id: label, label: label));
            continue;
          }
          final optionMap = optionValue.map(
            (key, value) => MapEntry(key.toString(), value as Object?),
          );
          final label = _string(optionMap['label']);
          if (label == null || label.isEmpty) {
            continue;
          }
          final optionId =
              _string(optionMap['id']) ?? _string(optionMap['value']) ?? label;
          optionLabels.add(label);
          optionItems.add(
            AgentUserInputOption(
              id: optionId,
              label: label,
              description: _string(optionMap['description']),
            ),
          );
        }
      }

      pairs.add(
        AgentUserInputQaPair(
          questionId: questionId,
          question: questionText,
          header: header,
          options: List<String>.unmodifiable(optionLabels),
          optionItems: List<AgentUserInputOption>.unmodifiable(optionItems),
          // Grok 问卷选项默认支持 Other 自由文本（TUI 行为）；无协议字段时保持 true。
          allowMultiple: allowMultiple,
          isOther: map['isOther'] != false,
        ),
      );
    }
    return List<AgentUserInputQaPair>.unmodifiable(pairs);
  }

  String? _string(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

/// 映射结果：pending 状态 + 领域事件。
final class GrokMappedQuestionRequest {
  const GrokMappedQuestionRequest({required this.pending, required this.event});

  final GrokPendingQuestion pending;
  final AgentQuestionRequestedEvent event;
}

/// 尚未回写的 Grok 用户提问请求。
final class GrokPendingQuestion {
  const GrokPendingQuestion({
    required this.id,
    required this.requestId,
    required this.questions,
    this.sessionId,
    this.runtimeScope,
  });

  /// 领域请求 id（通常为 toolCallId）。
  final String id;

  /// JSON-RPC request id。
  final Object requestId;

  final String? sessionId;
  final AgentRuntimeScope? runtimeScope;
  final List<AgentUserInputQaPair> questions;

  GrokPendingQuestion copyWith({AgentRuntimeScope? runtimeScope}) {
    return GrokPendingQuestion(
      id: id,
      requestId: requestId,
      sessionId: sessionId,
      questions: questions,
      runtimeScope: runtimeScope ?? this.runtimeScope,
    );
  }
}
