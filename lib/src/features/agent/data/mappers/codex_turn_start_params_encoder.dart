part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// `turn/start` 参数无法安全编码时抛出的受控异常。
///
/// 异常只描述无效的领域配置，不包含凭据、环境变量或完整协议载荷。
final class CodexTurnStartEncodingException implements Exception {
  /// 创建一条可安全展示和记录的编码错误。
  const CodexTurnStartEncodingException(this.message);

  /// 编码失败原因。
  final String message;

  @override
  String toString() => 'CodexTurnStartEncodingException: $message';
}

/// 将中立的回合输入编码为 Codex `TurnStartParams`。
///
/// 无模式时保持旧版顶层 `model`/`effort` 结构；显式模式则仅写入
/// `collaborationMode.settings`，从结构上避免两套配置同时出现。
final class _CodexTurnStartParamsEncoder {
  const _CodexTurnStartParamsEncoder({required this.defaultModelId});

  final String? defaultModelId;

  Map<String, Object?> encode({
    required AgentSession session,
    required List<AgentUserInput> inputs,
    required AgentContext context,
    required AgentModelSelection modelSelection,
    required AgentPermissionSelectionSnapshot permissionSelection,
    required AgentTurnConfiguration turnConfiguration,
    String? clientUserMessageId,
  }) {
    validate(turnConfiguration);
    final conversationMode = turnConfiguration.conversationMode;
    final permissionProfileId = permissionSelection.protocolPermissionProfileId;

    return <String, Object?>{
      'threadId': session.id,
      'input': _encodeCodexUserInputs(inputs),
      if (context.projectPath != null) 'cwd': context.projectPath,
      if (conversationMode == null) ...<String, Object?>{
        'model': ?(modelSelection.modelId ?? defaultModelId),
        // 协议顶层字段名为 `effort`；推理摘要 `summary` 暂无 UI 来源。
        'effort': ?modelSelection.reasoningEffort,
      } else
        'collaborationMode': _encodeCollaborationMode(conversationMode),
      'serviceTier': ?modelSelection.serviceTierId,
      'approvalPolicy':
          AgentPermissionSelectionSnapshot.normalizeApprovalPolicy(
            permissionSelection.approvalPolicy,
          ),
      'permissions': ?permissionProfileId,
      'sandboxPolicy': ?(permissionProfileId == null
          ? permissionSelection.toTurnSandboxPolicy()
          : null),
      'clientUserMessageId': ?clientUserMessageId,
    };
  }

  /// 校验显式模式是否能映射到当前 Codex 实验协议。
  void validate(AgentTurnConfiguration turnConfiguration) {
    final conversationMode = turnConfiguration.conversationMode;
    if (conversationMode == null) {
      return;
    }
    if (conversationMode.effectiveModelId.trim().isEmpty) {
      throw const CodexTurnStartEncodingException(
        'Collaboration mode requires a non-empty model',
      );
    }
    if (conversationMode.modeId.kind == AgentConversationModeKind.unknown) {
      throw CodexTurnStartEncodingException(
        'Unsupported collaboration mode: ${conversationMode.modeId.rawValue}',
      );
    }
  }

  Map<String, Object?> _encodeCollaborationMode(
    AgentConversationModeSelection selection,
  ) {
    final mode = switch (selection.modeId.kind) {
      AgentConversationModeKind.defaultMode => 'default',
      AgentConversationModeKind.plan => 'plan',
      AgentConversationModeKind.unknown =>
        throw CodexTurnStartEncodingException(
          'Unsupported collaboration mode: ${selection.modeId.rawValue}',
        ),
    };
    return <String, Object?>{
      'mode': mode,
      'settings': <String, Object?>{
        'model': selection.effectiveModelId,
        'reasoning_effort': selection.effectiveReasoningEffort,
        // null 表示使用 app-server 内置的对应模式指令。
        'developer_instructions': null,
      },
    };
  }
}

/// 将领域输入项编码为 Codex 协议 `UserInput[]`。
///
/// `turn/start` 与 `turn/steer` 共用此函数，避免富输入编码规则发生漂移。
List<Object?> _encodeCodexUserInputs(List<AgentUserInput> inputs) {
  return <Object?>[
    for (final input in inputs)
      switch (input) {
        AgentTextUserInput(:final text, :final textElements) =>
          <String, Object?>{
            'type': 'text',
            'text': text,
            if (textElements.isNotEmpty)
              'text_elements': <Object?>[
                for (final element in textElements)
                  <String, Object?>{
                    'byteRange': <int>[element.start, element.end],
                    'placeholder': ?element.placeholder,
                  },
              ],
          },
        AgentLocalImageUserInput(:final path, :final detail) =>
          <String, Object?>{
            'type': 'localImage',
            'path': path,
            'detail': ?detail,
          },
        AgentMentionUserInput(:final name, :final path) => <String, Object?>{
          'type': 'mention',
          'name': name,
          'path': path,
        },
        AgentSkillUserInput(:final name, :final path) => <String, Object?>{
          'type': 'skill',
          'name': name,
          'path': path,
        },
      },
  ];
}
