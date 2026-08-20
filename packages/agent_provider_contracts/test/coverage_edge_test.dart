import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

final class _EmptyText {
  @override
  String toString() => '';
}

AgentPermissionSelection _selection(String id) =>
    AgentPermissionSelection(optionId: id);

AgentProviderRuntimeSessionScope _runtimeSession(String id) =>
    AgentProviderRuntimeSessionScope(id);

void main() {
  test(
    'conversation mode value equality covers ordered collection branches',
    () {
      const preset = AgentConversationModePreset(
        id: AgentConversationModeId.defaultMode,
        displayName: 'Default',
        suggestedModelId: 'model',
        suggestedReasoningEffort: 'high',
      );
      expect(preset.hashCode, isNot(0));
      final catalog = AgentConversationModeCatalog(
        presets: const <AgentConversationModePreset>[preset],
      );
      expect(
        catalog,
        AgentConversationModeCatalog(
          presets: const <AgentConversationModePreset>[preset],
        ),
      );
      expect(catalog.hashCode, isNot(0));
      expect(
        catalog,
        isNot(
          AgentConversationModeCatalog(
            presets: const <AgentConversationModePreset>[],
          ),
        ),
      );
      expect(
        catalog,
        isNot(
          AgentConversationModeCatalog(
            presets: const <AgentConversationModePreset>[
              AgentConversationModePreset(
                id: AgentConversationModeId.plan,
                displayName: 'Plan',
              ),
            ],
          ),
        ),
      );
      final selection = AgentConversationModeSelection(
        modeId: AgentConversationModeId.defaultMode,
        effectiveModelId: 'model',
        effectiveReasoningEffort: 'high',
      );
      final equalSelection = AgentConversationModeSelection(
        modeId: AgentConversationModeId.defaultMode,
        effectiveModelId: 'model',
        effectiveReasoningEffort: 'high',
      );
      expect(selection, equalSelection);
      expect(selection.hashCode, isNot(0));
      final configuration = AgentTurnConfiguration(conversationMode: selection);
      final equalConfiguration = AgentTurnConfiguration(
        conversationMode: equalSelection,
      );
      expect(configuration, equalConfiguration);
      expect(configuration.hashCode, isNot(0));
    },
  );

  test(
    'remaining equality and nullable branches execute without identity',
    () {
      final selectionA = _selection('ask');
      final selectionB = _selection('ask');
      final snapshotA = AgentPermissionRequestSnapshot.resolved(
        selection: selectionA,
        source: AgentPermissionRequestSource.catalogDefault,
      );
      final snapshotB = AgentPermissionRequestSnapshot.resolved(
        selection: selectionB,
        source: AgentPermissionRequestSource.catalogDefault,
      );
      expect(snapshotA, snapshotB);
      final resultA = AgentPermissionApplyResult(
        normalizedSelection: selectionA,
        scope: AgentPermissionApplyScope.currentSession,
      );
      final resultB = AgentPermissionApplyResult(
        normalizedSelection: selectionB,
        scope: AgentPermissionApplyScope.currentSession,
      );
      expect(resultA, resultB);

      const capabilities = AgentProviderCapabilities(
        supportsModeSelection: true,
      );
      expect(capabilities.copyWith().supportsModeSelection, isTrue);
      expect(
        AgentProviderSettings().copyWith().activeProviderId,
        defaultAgentProviderId,
      );
      expect(
        AgentTurnStartedEvent.fromModelSelection(
          turn: AgentTurn(id: 'turn', sessionId: 'thread'),
          selection: const AgentModelSelection(),
        ).startedAt,
        isNotNull,
      );
      final runtimeSessionA = _runtimeSession('binding');
      final runtimeSessionB = _runtimeSession('binding');
      expect(runtimeSessionA, runtimeSessionB);
    },
  );

  test(
    'remaining collection and display branches are immutable and formatted',
    () {
      final response = AgentQuestionResponse(
        requestId: 'request',
        answers: <String, List<String>>{
          'question': <String>['answer'],
        },
      );
      expect(
        () => response.answers['question']!.clear(),
        throwsUnsupportedError,
      );
      expect(
        AgentSkillsCatalog(
          entries: <AgentSkillsCatalogEntry>[
            AgentSkillsCatalogEntry(
              cwd: '/repo',
              skills: const <AgentSkillMetadata>[],
            ),
          ],
        ).query(''),
        isEmpty,
      );
      expect(const AgentSkillRef(name: 'name', path: '/skill').label, 'name');

      String label(AgentToolKind kind) => kind.name;
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call',
          kindLabel: label,
          rawInput: <String, Object?>{'command': 42},
        ),
        '42',
      );
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call',
          kindLabel: label,
          rawInput: <String, Object?>{'command': _EmptyText()},
        ),
        'other',
      );
      expect(
        buildAgentToolCallDisplayTitle(
          toolCallId: 'call',
          kindLabel: label,
          locations: const <String>['///'],
        ),
        '///',
      );
    },
  );

  test('remaining history getters and entry constructors are covered', () {
    expect(
      const AgentTurnModelConfig(reasoningEffort: 'high').hasDisplayable,
      isTrue,
    );
    expect(
      const AgentTurnModelConfig(fastEnabled: true).hasDisplayable,
      isTrue,
    );
    const usage = AgentTokenUsage(
      inputTokens: 1,
      lastCachedInputTokens: 2,
      lastReasoningOutputTokens: 3,
      modelContextWindow: 4,
    );
    expect(usage.hasCumulativeBreakdown, isTrue);
    expect(
      const AgentTokenUsage(cachedInputTokens: 1).hasCumulativeBreakdown,
      isTrue,
    );
    expect(
      const AgentTokenUsage(outputTokens: 1).hasCumulativeBreakdown,
      isTrue,
    );
    expect(
      const AgentTokenUsage(reasoningOutputTokens: 1).hasCumulativeBreakdown,
      isTrue,
    );
    expect(
      const AgentTokenUsage(totalTokens: 1).hasCumulativeBreakdown,
      isTrue,
    );
    expect(usage.displayReasoningOutputTokens, isNull);
    expect(usage.displayLastCachedInputTokens, '2');
    expect(usage.displayLastReasoningOutputTokens, '3');
    expect(usage.displayModelContextWindow, '4');
    final tool = AgentToolCall(id: 'tool', title: 'Tool');
    expect(AgentHistoryToolEntry(toolCall: tool).toolCall, tool);
    final qa = AgentUserInputQaPair(
      questionId: 'question',
      question: 'Question',
    );
    final event = AgentHistoryEventEntry(
      id: 'event',
      kind: AgentHistoryEventKind.permission,
      title: 'Permission',
      qaPairs: <AgentUserInputQaPair>[qa],
    );
    expect(event.qaPairs, <AgentUserInputQaPair>[qa]);
    expect(() => event.qaPairs!.clear(), throwsUnsupportedError);
    final coded = AgentHistoryEventEntry(
      id: 'coded',
      kind: AgentHistoryEventKind.system,
      titleCode: AgentHistoryEventTitleCode.waiting,
      descriptionCode: AgentHistoryEventDescriptionCode.subAgentStarted,
      duration: const Duration(seconds: 2),
    );
    expect(coded.title, isNull);
    expect(coded.titleCode, AgentHistoryEventTitleCode.waiting);
    expect(
      coded.descriptionCode,
      AgentHistoryEventDescriptionCode.subAgentStarted,
    );
    expect(coded.duration, const Duration(seconds: 2));
    expect(
      () => AgentHistoryEventEntry(
        id: 'invalid',
        kind: AgentHistoryEventKind.system,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
