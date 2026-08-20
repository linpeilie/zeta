import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('small contract values retain typed data and value semantics', () {
    const failure = AgentProviderFailure(
      code: AgentProviderFailureCode.protocol,
      diagnosticCode: 'bad-frame',
      diagnosticDetails: 'diagnostic only',
    );
    expect(failure.props, hasLength(3));
    expect(
      failure,
      equals(
        const AgentProviderFailure(
          code: AgentProviderFailureCode.protocol,
          diagnosticCode: 'bad-frame',
          diagnosticDetails: 'diagnostic only',
        ),
      ),
    );

    final command = ResolvedCliProcessCommand(
      executable: 'agent',
      arguments: const <String>['serve'],
      displayPath: '/bin/agent',
    );
    final started = command.processCommandFor(<String>['--stdio']);
    expect(started.arguments, <String>['serve', '--stdio']);
    expect(() => started.arguments.add('x'), throwsUnsupportedError);
    expect(started.props, <Object?>[
      'agent',
      <String>['serve', '--stdio'],
      '/bin/agent',
    ]);

    expect(
      ContextWindowCodec.positiveWindow(<String, Object?>{
        'context_window': '4096',
      }),
      4096,
    );
    expect(
      ContextWindowCodec.positiveWindow(const <String, Object?>{}),
      isNull,
    );
    expect(ContextWindowCodec.positiveInt(2.8), 2);
    expect(ContextWindowCodec.positiveInt(0), isNull);
    expect(ContextWindowCodec.positiveInt('bad'), isNull);

    const scope = AgentRuntimeScope(runtimeId: 'runtime', connectionEpoch: 2);
    expect(
      scope,
      const AgentRuntimeScope(runtimeId: 'runtime', connectionEpoch: 2),
    );
    expect(scope.hashCode, isNot(0));
    expect(scope.toString(), 'runtime@2');
    const sessionScope = AgentProviderRuntimeScopeKey.session('binding');
    expect(sessionScope, const AgentProviderRuntimeScopeKey.session('binding'));
    expect(sessionScope.hashCode, isNot(0));
    expect(sessionScope.toString(), 'session(binding)');
    expect(AgentProviderRuntimeScopeKey.global.toString(), 'global');
    expect(
      AgentProviderRuntimeScopeKey.global,
      AgentProviderRuntimeScopeKey.global,
    );
    expect(AgentProviderRuntimeScopeKey.global.hashCode, isNot(0));
    const info = AgentRuntimeInfo(
      runtimeId: 'runtime',
      connectionEpoch: 2,
      protocolName: 'neutral',
      protocolVersion: '1',
      compatibilityStatus: AgentRuntimeCompatibilityStatus.supported,
    );
    expect(info.protocolName, 'neutral');

    const signal = AgentAttentionSignal(
      kind: AgentAttentionKind.turnCompleted,
      phase: AgentAttentionPhase.raised,
      sourceId: 'turn-1',
    );
    expect(
      signal.identityFor('provider', 'thread'),
      'turnCompleted:provider:thread:turn-1',
    );
    final withThread = signal.withThreadId('thread');
    expect(withThread.threadId, 'thread');
    expect(withThread.withThreadId('thread'), same(withThread));
    const workspace = AgentWorkspaceAttention(
      signal: signal,
      providerId: 'provider',
      threadId: 'thread',
      projectPath: '/repo',
    );
    expect(workspace.identity, 'turnCompleted:provider:thread:turn-1');
    const terminal = AgentTurnTerminalSignal(
      providerId: 'provider',
      threadId: 'thread',
      turnId: 'turn',
    );
    expect(terminal.turnId, 'turn');
  });

  test('codec helpers tolerate mixed persisted values', () {
    expect(decodeOptionalString('x'), 'x');
    expect(decodeOptionalString(''), isNull);
    expect(decodeStringList(<Object?>['a', '', 1]), <String>['a']);
    expect(decodeStringList('bad'), isEmpty);
    expect(
      decodeStringMap(<Object?, Object?>{'a': 1, 2: 'b'}),
      <String, String>{'a': '1'},
    );
    expect(decodeStringMap(null), isEmpty);
    expect(decodeObjectMap(<Object?, Object?>{'a': 1, 2: 3}), <String, Object?>{
      'a': 1,
    });
    expect(decodeObjectMap(null), isEmpty);
    expect(
      decodeDateTimeFromMilliseconds(1),
      DateTime.fromMillisecondsSinceEpoch(1),
    );
    expect(decodeDateTimeFromMilliseconds('1'), isNull);
  });

  test('event family constructs every public variant', () {
    final raw = <String, Object?>{
      'nested': <Object?>[1, 2],
    };
    const status = AgentProviderStatus(
      state: AgentProviderConnectionState.ready,
      code: AgentProviderStatusCode.ready,
    );
    final session = AgentSession(id: 'thread', providerId: 'provider');
    final turn = AgentTurn(id: 'turn', sessionId: 'thread');
    const usage = AgentTokenUsage(inputTokens: 1, outputTokens: 2);
    final tool = AgentToolCall(id: 'tool', title: 'Read');
    final questions = AgentQuestionRequest(
      id: 'question',
      title: 'Question',
      questions: <AgentUserInputQaPair>[],
    );
    final planRequest = AgentPlanApprovalRequest(
      id: 'plan',
      title: 'Plan',
      markdown: 'Do it',
    );
    final events = <AgentEvent>[
      const AgentStatusEvent(status),
      AgentSessionStartedEvent(session),
      AgentThreadStatusChangedEvent(
        threadId: 'thread',
        status: AgentThreadRuntimeStatus.active,
        raw: raw,
      ),
      AgentThreadNameUpdatedEvent(
        threadId: 'thread',
        threadName: 'Name',
        raw: raw,
      ),
      AgentThreadPreviewUpdatedEvent(
        threadId: 'thread',
        preview: 'Preview',
        raw: raw,
      ),
      AgentThreadArchivedEvent(threadId: 'thread', raw: raw),
      AgentThreadUnarchivedEvent(threadId: 'thread', raw: raw),
      AgentThreadDeletedEvent(threadId: 'thread', raw: raw),
      AgentThreadClosedEvent(threadId: 'thread', raw: raw),
      AgentThreadCompactedEvent(threadId: 'thread', turnId: 'turn', raw: raw),
      const AgentThreadSettingsUpdatedEvent(threadId: 'thread'),
      AgentAutoApprovalReviewEvent(
        threadId: 'thread',
        turnId: 'turn',
        reviewId: 'review',
        status: 'approved',
        raw: raw,
      ),
      AgentTurnStartedEvent.fromModelSelection(
        turn: turn,
        selection: const AgentModelSelection(
          modelId: ' model ',
          reasoningEffort: ' high ',
        ),
        startedAt: DateTime(2026),
      ),
      AgentTurnCompletedEvent(sessionId: 'thread', turnId: 'turn', raw: raw),
      AgentTokenUsageEvent(tokenUsage: usage, raw: raw),
      AgentContextWindowUsageEvent(usedTokens: 10, raw: raw),
      AgentMessageDeltaEvent(
        messageId: 'message',
        delta: 'a',
        role: AgentMessageRole.agent,
        raw: raw,
      ),
      AgentReasoningDeltaEvent(
        itemId: 'reasoning',
        kind: AgentReasoningDeltaKind.text,
        raw: raw,
      ),
      AgentMessageUpdatedEvent(messageId: 'message', raw: raw),
      AgentPlanUpdatedEvent(entries: const <AgentPlanEntry>[]),
      AgentSessionConfigUpdatedEvent(
        sessionId: 'thread',
        options: <AgentSessionConfigOption>[],
      ),
      AgentConversationModeUpdatedEvent(
        sessionId: 'thread',
        modeId: AgentConversationModeId.defaultMode,
        raw: raw,
      ),
      AgentPlanApprovalRequestedEvent(planRequest),
      const AgentPlanApprovalResolvedEvent(requestId: 'plan'),
      AgentTurnFileChangesEvent(
        sessionId: 'thread',
        turnId: 'turn',
        snapshot: AgentFileChangeSnapshot(
          revision: 1,
          replayability: AgentFileChangeReplayability.replayable,
          changes: const <AgentFileChange>[],
        ),
      ),
      AgentToolCallEvent(tool),
      AgentPermissionRequestedEvent(
        AgentPermissionRequest(
          id: 'permission',
          title: 'Permission',
          kind: AgentPermissionKind.other,
        ),
      ),
      AgentPermissionResolvedEvent(
        requestId: 'permission',
        threadId: 'thread',
        raw: raw,
      ),
      AgentQuestionRequestedEvent(questions),
      AgentQuestionResolvedEvent(
        requestId: 'question',
        threadId: 'thread',
        raw: raw,
      ),
      AgentModelReroutedEvent(
        threadId: 'thread',
        turnId: 'turn',
        fromModel: 'a',
        toModel: 'b',
        reason: 'capacity',
        raw: raw,
      ),
      AgentDeprecationNoticeEvent(summary: 'deprecated', raw: raw),
      AgentSystemItemEvent(
        entry: AgentHistoryEventEntry(
          id: 'event',
          kind: AgentHistoryEventKind.system,
          titleCode: AgentHistoryEventTitleCode.contextCompacted,
        ),
      ),
      AgentErrorEvent(message: 'error', raw: raw),
      AgentModelListEvent(AgentModelList(models: <AgentModelInfo>[])),
    ];
    expect(events, hasLength(35));
    expect(
      () => (events[2] as AgentThreadStatusChangedEvent).raw.clear(),
      throwsUnsupportedError,
    );
  });
}
