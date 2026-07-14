import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Cursor 扩展通知的中立映射结果。
class CursorAcpExtensionUpdate {
  const CursorAcpExtensionUpdate({
    this.events = const <AgentEvent>[],
    this.unmatchedMethod,
  });

  final List<AgentEvent> events;
  final String? unmatchedMethod;
}

/// 将 Cursor 官方 ACP 扩展映射为中立领域模型。
class CursorAcpExtensionMapper {
  final Map<String, Map<String, AgentPlanEntry>> _todosBySession =
      <String, Map<String, AgentPlanEntry>>{};

  AgentPermissionRequest mapAskQuestion({
    required Object requestId,
    required Map<String, Object?> params,
    required String? sessionId,
    required String? turnId,
  }) {
    final questions = <AgentUserInputQaPair>[];
    final rawQuestions = params['questions'];
    if (rawQuestions is List) {
      for (final item in rawQuestions) {
        final question = _asMap(item);
        final id = _optionalString(question?['id']);
        final prompt = _optionalString(question?['prompt']);
        if (question == null || id == null || prompt == null) {
          continue;
        }
        final options = <AgentUserInputOption>[];
        final rawOptions = question['options'];
        if (rawOptions is List) {
          for (final rawOption in rawOptions) {
            final option = _asMap(rawOption);
            final optionId = _optionalString(option?['id']);
            final label = _optionalString(option?['label']);
            if (optionId != null && label != null) {
              options.add(AgentUserInputOption(id: optionId, label: label));
            }
          }
        }
        questions.add(
          AgentUserInputQaPair(
            questionId: id,
            question: prompt,
            optionItems: List<AgentUserInputOption>.unmodifiable(options),
            allowMultiple: question['allowMultiple'] == true,
          ),
        );
      }
    }
    return AgentPermissionRequest(
      id: requestId.toString(),
      title: _optionalString(params['title']) ?? 'Cursor needs input',
      kind: AgentPermissionKind.userInput,
      sessionId: sessionId,
      turnId: turnId,
      questions: List<AgentUserInputQaPair>.unmodifiable(questions),
      raw: params,
    );
  }

  AgentPlanApprovalRequest mapCreatePlan({
    required Object requestId,
    required Map<String, Object?> params,
    required String? sessionId,
    required String? turnId,
  }) {
    final phases = <AgentPlanApprovalPhase>[];
    final rawPhases = params['phases'];
    if (rawPhases is List) {
      for (final item in rawPhases) {
        final phase = _asMap(item);
        final name = _optionalString(phase?['name']);
        if (phase == null || name == null) {
          continue;
        }
        phases.add(
          AgentPlanApprovalPhase(name: name, todos: _mapTodos(phase['todos'])),
        );
      }
    }
    final title =
        _optionalString(params['name']) ??
        _optionalString(params['title']) ??
        'Review Cursor plan';
    return AgentPlanApprovalRequest(
      id: requestId.toString(),
      title: title,
      overview: _optionalString(params['overview']),
      markdown: _optionalString(params['plan']) ?? '',
      todos: _mapTodos(params['todos']),
      phases: List<AgentPlanApprovalPhase>.unmodifiable(phases),
      isProject: params['isProject'] == true,
      sessionId: sessionId,
      turnId: turnId,
      raw: params,
    );
  }

  CursorAcpExtensionUpdate mapNotification({
    required String method,
    required Map<String, Object?> params,
    required String? sessionId,
    required String? turnId,
  }) {
    return switch (method) {
      'cursor/update_todos' => _mapTodoUpdate(
        params: params,
        sessionId: sessionId,
        turnId: turnId,
      ),
      'cursor/task' => CursorAcpExtensionUpdate(
        events: <AgentEvent>[
          AgentToolCallEvent(
            AgentToolCall(
              id: _toolCallId(params, 'cursor-task'),
              title: _optionalString(params['description']) ?? 'Cursor task',
              kind: AgentToolKind.other,
              status: AgentToolStatus.completed,
              content: _taskContent(params),
              sessionId: sessionId,
              turnId: turnId,
              duration: _duration(params['durationMs']),
              raw: params,
            ),
          ),
        ],
      ),
      'cursor/generate_image' => CursorAcpExtensionUpdate(
        events: <AgentEvent>[
          AgentToolCallEvent(
            AgentToolCall(
              id: _toolCallId(params, 'cursor-image'),
              title: 'Generated image',
              kind: AgentToolKind.other,
              status: AgentToolStatus.completed,
              content: _optionalString(params['description']),
              locations: <String>[?_optionalString(params['filePath'])],
              sessionId: sessionId,
              turnId: turnId,
              raw: params,
            ),
          ),
        ],
      ),
      _ => CursorAcpExtensionUpdate(unmatchedMethod: method),
    };
  }

  void clearSession(String sessionId) {
    _todosBySession.remove(sessionId);
  }

  void clear() {
    _todosBySession.clear();
  }

  CursorAcpExtensionUpdate _mapTodoUpdate({
    required Map<String, Object?> params,
    required String? sessionId,
    required String? turnId,
  }) {
    final key = sessionId ?? 'unscoped';
    final incoming = _mapTodos(params['todos']);
    final current = params['merge'] == true
        ? (_todosBySession[key] ?? <String, AgentPlanEntry>{})
        : <String, AgentPlanEntry>{};
    var anonymousIndex = current.length;
    for (final todo in incoming) {
      final id = todo.id ?? 'anonymous-${anonymousIndex++}';
      current[id] = todo;
    }
    _todosBySession[key] = current;
    return CursorAcpExtensionUpdate(
      events: <AgentEvent>[
        AgentPlanUpdatedEvent(
          entries: List<AgentPlanEntry>.unmodifiable(current.values),
          sessionId: sessionId,
          turnId: turnId,
        ),
      ],
    );
  }

  List<AgentPlanEntry> _mapTodos(Object? value) {
    if (value is! List) {
      return const <AgentPlanEntry>[];
    }
    final todos = <AgentPlanEntry>[];
    for (final item in value) {
      final todo = _asMap(item);
      final content = _optionalString(todo?['content']);
      if (todo == null || content == null) {
        continue;
      }
      todos.add(
        AgentPlanEntry(
          id: _optionalString(todo['id']),
          content: content,
          status: _optionalString(todo['status']),
        ),
      );
    }
    return List<AgentPlanEntry>.unmodifiable(todos);
  }
}

String _toolCallId(Map<String, Object?> params, String fallback) {
  return _optionalString(params['toolCallId']) ?? fallback;
}

String? _taskContent(Map<String, Object?> params) {
  final parts = <String>[
    ?_optionalString(params['prompt']),
    if (_optionalString(params['model']) case final model?) 'Model: $model',
    if (_optionalString(params['agentId']) case final agentId?)
      'Agent: $agentId',
  ];
  return parts.isEmpty ? null : parts.join('\n');
}

Duration? _duration(Object? value) {
  final milliseconds = switch (value) {
    int milliseconds => milliseconds,
    num milliseconds => milliseconds.toInt(),
    String milliseconds => int.tryParse(milliseconds),
    _ => null,
  };
  return milliseconds == null || milliseconds < 0
      ? null
      : Duration(milliseconds: milliseconds);
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}
