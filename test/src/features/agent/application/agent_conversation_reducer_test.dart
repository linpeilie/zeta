import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

const _threadId = 'thread-1';
const _turnId = 'turn-1';
final _fixedClockValue = DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7);
const _initialState = AgentConversationSessionState.initial(
  defaultTitle: agentDefaultThreadTitle,
);

void main() {
  group('AgentConversationReducer 33-event migration table', () {
    for (final batch in _reductionCasesByBatch().entries) {
      group(batch.key, () {
        for (final reductionCase in batch.value) {
          test(reductionCase.name, () {
            // Arrange
            final reducer = AgentConversationReducer.live(
              clock: () => _fixedClockValue,
            );

            // Act
            final mutation = reducer.reduce(
              reductionCase.event,
              _initialState,
              _context(),
            );

            // Assert
            _expectReduction(mutation, reductionCase);
          });
        }
      });
    }
  });

  group('current-thread acceptance and rejection', () {
    test('all 33 cases preserve their wrong-thread routing contract', () {
      final globallyAcceptedTypes = <Type>{
        AgentStatusEvent,
        AgentThreadArchivedEvent,
        AgentThreadUnarchivedEvent,
        AgentThreadDeletedEvent,
        AgentDeprecationNoticeEvent,
        AgentModelListEvent,
      };

      for (final reductionCase in _allReductionCases()) {
        // Arrange
        final reducer = AgentConversationReducer.live(
          clock: () => _fixedClockValue,
        );

        // Act
        final mutation = reducer.reduce(
          reductionCase.event,
          _initialState,
          _context(selectedThreadId: 'other-thread'),
        );

        // Assert
        if (globallyAcceptedTypes.contains(reductionCase.event.runtimeType)) {
          _expectReduction(mutation, reductionCase);
          continue;
        }
        final expectedReason = reductionCase.event is AgentSessionStartedEvent
            ? 'sessionStartedThreadMismatch'
            : 'currentThreadMismatch';
        _expectRejected(
          mutation,
          reason: expectedReason,
          effectTypes: reductionCase.event is AgentErrorEvent
              ? const <Type>[AgentLogProviderErrorEffect]
              : const <Type>[],
        );
      }
    });

    test('session identity takes precedence over turn fallback', () {
      const event = AgentMessageDeltaEvent(
        messageId: 'message-session-precedence',
        delta: 'hello',
        role: AgentMessageRole.agent,
        sessionId: _threadId,
        turnId: 'foreign-turn',
      );
      final reducer = AgentConversationReducer.live();

      final accepted = reducer.reduce(
        event,
        _initialState,
        _context(hasTurns: const <String>{}),
      );
      final rejected = reducer.reduce(
        event,
        _initialState,
        _context(
          selectedThreadId: 'other-thread',
          hasTurns: const <String>{'foreign-turn'},
          pendingTurnGroupId: 'foreign-turn',
        ),
      );

      expect(accepted.accepted, isTrue);
      _expectRejected(rejected, reason: 'currentThreadMismatch');
    });

    test('other-thread settings routes only its neutral permission state', () {
      final event = AgentThreadSettingsUpdatedEvent(
        threadId: _threadId,
        model: 'must-not-touch-current-canvas',
        collaborationMode: AgentConversationModeSelection(
          modeId: AgentConversationModeId.plan,
          effectiveModelId: 'gpt-test',
        ),
        permissionSelection: AgentPermissionSelection(optionId: ':read-only'),
      );

      final mutation = AgentConversationReducer.live().reduce(
        event,
        _initialState,
        _context(selectedThreadId: 'other-thread'),
      );

      expect(mutation.accepted, isTrue);
      expect(mutation.uiUpdate, isNull);
      expect(_runtimeTypes(mutation.effects), <Type>[
        AgentApplyThreadPermissionEffect,
      ]);
      final change =
          mutation.effects.single as AgentApplyThreadPermissionEffect;
      expect(change.threadId, _threadId);
      expect(change.permissionSelection.optionId, ':read-only');
    });

    test('turn identity falls back to timeline and pending turn group', () {
      const knownTurnEvent = AgentMessageDeltaEvent(
        messageId: 'known-turn-message',
        delta: 'known',
        role: AgentMessageRole.agent,
        turnId: 'known-turn',
      );
      const pendingTurnEvent = AgentMessageDeltaEvent(
        messageId: 'pending-turn-message',
        delta: 'pending',
        role: AgentMessageRole.agent,
        turnId: 'pending-turn',
      );
      const unknownTurnEvent = AgentMessageDeltaEvent(
        messageId: 'unknown-turn-message',
        delta: 'unknown',
        role: AgentMessageRole.agent,
        turnId: 'unknown-turn',
      );
      final reducer = AgentConversationReducer.live();
      final context = _context(
        hasTurns: const <String>{'known-turn'},
        pendingTurnGroupId: 'pending-turn',
      );

      expect(
        reducer.reduce(knownTurnEvent, _initialState, context).accepted,
        isTrue,
      );
      expect(
        reducer.reduce(pendingTurnEvent, _initialState, context).accepted,
        isTrue,
      );
      _expectRejected(
        reducer.reduce(unknownTurnEvent, _initialState, context),
        reason: 'currentThreadMismatch',
      );
    });

    test(
      'events without session or turn identity remain globally routable',
      () {
        const event = AgentMessageUpdatedEvent(
          messageId: 'identity-free-message',
          text: 'done',
        );

        final mutation = AgentConversationReducer.live().reduce(
          event,
          _initialState,
          _context(
            selectedThreadId: 'other-thread',
            hasTurns: const <String>{},
          ),
        );

        expect(mutation.accepted, isTrue);
        expect(_runtimeTypes(mutation.timelineMutations), const <Type>[
          AgentUpdateMessageTimelineMutation,
        ]);
      },
    );

    test('session-start resume guard preserves selected-thread semantics', () {
      const event = AgentSessionStartedEvent(
        AgentSession(id: _threadId, providerId: defaultAgentProviderId),
      );

      expect(
        AgentConversationReducer.live()
            .reduce(event, _initialState, _context(selectedThreadId: null))
            .accepted,
        isTrue,
      );
      _expectRejected(
        AgentConversationReducer.live().reduce(
          event,
          _initialState,
          _context(selectedThreadId: null, requiresResumedSelectedThread: true),
        ),
        reason: 'sessionStartedThreadMismatch',
      );
      expect(
        AgentConversationReducer.live()
            .reduce(
              event,
              _initialState,
              _context(requiresResumedSelectedThread: true),
            )
            .accepted,
        isTrue,
      );
    });
  });

  group('detached critical event allowlist', () {
    test('contains exactly the ten compatibility-critical event types', () {
      const criticalTypes = <Type>{
        AgentStatusEvent,
        AgentErrorEvent,
        AgentTurnCompletedEvent,
        AgentThreadClosedEvent,
        AgentThreadNameUpdatedEvent,
        AgentThreadPreviewUpdatedEvent,
        AgentPermissionRequestedEvent,
        AgentPermissionResolvedEvent,
        AgentPlanApprovalRequestedEvent,
        AgentPlanApprovalResolvedEvent,
      };
      final cases = _allReductionCases();

      for (final reductionCase in cases) {
        expect(
          AgentDetachedEventPolicy.isCritical(reductionCase.event),
          criticalTypes.contains(reductionCase.event.runtimeType),
          reason: reductionCase.name,
        );
      }
      expect(
        cases
            .where((item) => AgentDetachedEventPolicy.isCritical(item.event))
            .length,
        criticalTypes.length,
      );
    });
  });

  group('turn compatibility invariants', () {
    test('interrupted turn settles through ordered synchronous mutations', () {
      final mutation = AgentConversationReducer.live().settleInterruptedTurn(
        fallbackTurnId: 'fallback-turn',
        state: _initialState,
        context: _context(),
      );

      expect(mutation.accepted, isTrue);
      expect(_runtimeTypes(mutation.timelineMutations), const <Type>[
        AgentSettleInterruptedTimelineMutation,
      ]);
      expect(
        (mutation.timelineMutations.single
                as AgentSettleInterruptedTimelineMutation)
            .fallbackTurnId,
        'fallback-turn',
      );
      expect(_runtimeTypes(mutation.effects), const <Type>[
        AgentClearPlanHandoffEffect,
        AgentSyncTurnRunningEffect,
      ]);
      expect(mutation.uiUpdate?.urgency, AgentUiUpdateUrgency.immediate);
      expect(mutation.threadSnapshot, AgentThreadSnapshotMutation.refresh);
    });

    test('Codex error and matching failed turn.error render only once', () {
      final reducer = AgentConversationReducer.live(
        clock: () => _fixedClockValue,
      );
      final context = _context();
      const error = AgentErrorEvent(
        message: 'same failure',
        sessionId: _threadId,
        turnId: _turnId,
      );
      const completion = AgentTurnCompletedEvent(
        sessionId: _threadId,
        turnId: _turnId,
        status: AgentHistoryTurnStatus.failed,
        errorMessage: 'same failure',
      );

      final errorMutation = reducer.reduce(error, _initialState, context);
      final deduplicatedCompletion = reducer.reduce(
        completion,
        _initialState,
        context,
      );
      reducer.reduce(
        const AgentTurnStartedEvent(
          AgentTurn(id: _turnId, sessionId: _threadId),
        ),
        _initialState,
        context,
      );
      final completionAfterNewTurn = reducer.reduce(
        completion,
        _initialState,
        context,
      );

      expect(_runtimeTypes(errorMutation.timelineMutations), const <Type>[
        AgentAddConversationMessageTimelineMutation,
      ]);
      expect(
        _runtimeTypes(deduplicatedCompletion.timelineMutations),
        const <Type>[AgentCompleteLiveTurnTimelineMutation],
      );
      expect(
        _runtimeTypes(completionAfterNewTurn.timelineMutations),
        const <Type>[
          AgentAddConversationMessageTimelineMutation,
          AgentCompleteLiveTurnTimelineMutation,
        ],
      );
    });

    test('serverOverloaded live error includes capacity guidance', () {
      final mutation =
          AgentConversationReducer.live(clock: () => _fixedClockValue).reduce(
            const AgentErrorEvent(
              message:
                  'Selected model is at capacity. Please try a different model.',
              code: 'serverOverloaded',
              willRetry: false,
              sessionId: _threadId,
              turnId: _turnId,
            ),
            _initialState,
            _context(),
          );

      final text =
          (mutation.timelineMutations.single
                  as AgentAddConversationMessageTimelineMutation)
              .message
              .text;
      expect(text, contains('Selected model is at capacity'));
      expect(text, contains('当前模型容量已满'));
      expect(text, contains('切换其他模型'));
    });

    test('failed turn completion formats serverOverloaded guidance', () {
      final mutation =
          AgentConversationReducer.live(clock: () => _fixedClockValue).reduce(
            const AgentTurnCompletedEvent(
              sessionId: _threadId,
              turnId: _turnId,
              status: AgentHistoryTurnStatus.failed,
              errorMessage:
                  'Selected model is at capacity. Please try a different model.',
              errorCode: 'serverOverloaded',
            ),
            _initialState,
            _context(),
          );

      final text =
          (mutation.timelineMutations.first
                  as AgentAddConversationMessageTimelineMutation)
              .message
              .text;
      expect(text.startsWith('Turn failed: '), isTrue);
      expect(text, contains('当前模型容量已满'));
    });

    test(
      'completed always emits prepare/finalize convergence and handoff boundary',
      () {
        const event = AgentTurnCompletedEvent(
          sessionId: _threadId,
          turnId: _turnId,
        );

        final mutation = AgentConversationReducer.live().reduce(
          event,
          _initialState,
          _context(),
        );

        expect(
          mutation.effects
              .whereType<AgentPreparePlanHandoffEffect>()
              .single
              .event,
          same(event),
        );
        expect(
          mutation.effects.whereType<AgentSyncTurnRunningEffect>(),
          isNotEmpty,
        );
        expect(
          mutation.effects.whereType<AgentAutoStartPlanExecutionEffect>(),
          isNotEmpty,
        );
      },
    );
  });

  group('event family variants', () {
    test(
      'terminal tool call keeps immediate cadence without active status state',
      () {
        const event = AgentToolCallEvent(
          AgentToolCall(
            id: 'tool-terminal',
            title: 'Run tests',
            kind: AgentToolKind.execute,
            status: AgentToolStatus.completed,
            sessionId: _threadId,
            turnId: _turnId,
          ),
        );

        final mutation = AgentConversationReducer.live().reduce(
          event,
          _initialState,
          _context(),
        );

        expect(mutation.accepted, isTrue);
        expect(_runtimeTypes(mutation.timelineMutations), const <Type>[
          AgentUpsertToolCallTimelineMutation,
        ]);
        expect(mutation.uiUpdate?.urgency, AgentUiUpdateUrgency.immediate);
        expect(
          _runtimeTypes(mutation.uiUpdate?.effects ?? const []),
          const <Type>[AgentRequestAutoScroll],
        );
      },
    );
  });

  group('usage and Provider-neutral payload compatibility', () {
    test(
      'history turn usage targets history footer instead of live footer',
      () {
        const event = AgentTokenUsageEvent(
          tokenUsage: AgentTokenUsage(inputTokens: 10, totalTokens: 12),
          sessionId: _threadId,
          turnId: _turnId,
          isSessionCumulative: false,
        );

        final mutation = AgentConversationReducer.live().reduce(
          event,
          _initialState,
          _context(historyTurns: const <String>{_turnId}),
        );

        expect(mutation.uiUpdate?.urgency, AgentUiUpdateUrgency.immediate);
        expect(
          mutation.timelineMutations.single,
          isA<AgentUpdateTurnTokenUsageTimelineMutation>(),
        );
      },
    );

    test('error timeline mutation exposes only normalized message fields', () {
      const event = AgentErrorEvent(
        message: 'boom',
        details: 'details',
        sessionId: _threadId,
        turnId: _turnId,
      );

      final mutation = AgentConversationReducer.live(
        clock: () => _fixedClockValue,
      ).reduce(event, _initialState, _context());
      final message =
          (mutation.timelineMutations.single
                  as AgentAddConversationMessageTimelineMutation)
              .message;

      expect(message.role, AgentMessageRole.system);
      expect(message.text, 'boom: details');
      expect(message.raw, isEmpty);
      expect(message.text, isNot(contains('must-not-leak')));
    });
  });

  group('application effect descriptors', () {
    test('turn completion effect carries exact live turn scope', () {
      const event = AgentTurnCompletedEvent(
        sessionId: _threadId,
        turnId: _turnId,
      );

      final mutation = AgentConversationReducer.live().reduce(
        event,
        _initialState,
        _context(),
      );
      final effect = mutation.effects
          .whereType<AgentTurnCompletedEffect>()
          .single;

      expect(effect.turnId, _turnId);
      expect(effect.attention.kind, AgentAttentionKind.turnCompleted);
      expect(effect.attention.phase, AgentAttentionPhase.raised);
      expect(effect.attention.sourceId, _turnId);
      expect(effect.attention.threadId, _threadId);
      expect(effect.timing, AgentConversationEffectTiming.afterMutation);
      expect(effect.requireThread, isTrue);
      _expectDefaultScope(effect.scope, turnId: _turnId);
    });

    test('pending interaction effects carry raised and resolved identity', () {
      final requested = AgentConversationReducer.live().reduce(
        const AgentPermissionRequestedEvent(
          AgentPermissionRequest(
            id: 'permission-1',
            title: 'Run',
            kind: AgentPermissionKind.commandExecution,
            sessionId: _threadId,
            turnId: _turnId,
          ),
        ),
        _initialState,
        _context(),
      );
      final resolved = AgentConversationReducer.live().reduce(
        const AgentPermissionResolvedEvent(
          requestId: 'permission-1',
          threadId: _threadId,
        ),
        _initialState,
        _context(),
      );

      final raisedSignal =
          (requested.effects.single as AgentAttentionEffect).signal;
      final resolvedSignal =
          (resolved.effects.single as AgentAttentionEffect).signal;
      expect(raisedSignal.kind, AgentAttentionKind.permissionRequired);
      expect(raisedSignal.phase, AgentAttentionPhase.raised);
      expect(resolvedSignal.kind, raisedSignal.kind);
      expect(resolvedSignal.phase, AgentAttentionPhase.resolved);
      expect(resolvedSignal.sourceId, raisedSignal.sourceId);
    });

    test('model catalog effect is thread-independent and preserves source', () {
      final event =
          _allReductionCases()
                  .singleWhere((item) => item.event is AgentModelListEvent)
                  .event
              as AgentModelListEvent;

      final mutation = AgentConversationReducer.live().reduce(
        event,
        _initialState,
        _context(),
      );
      final effect = mutation.effects
          .whereType<AgentRecordModelCatalogEffect>()
          .single;

      expect(effect.timing, AgentConversationEffectTiming.afterMutation);
      expect(effect.requireThread, isFalse);
      expect(effect.config, same(defaultCodexAgentProviderConfig));
      expect(effect.models, same(event.models));
      expect(effect.source, 'Codex runtime');
      _expectDefaultScope(effect.scope);
    });

    test('refresh-origin model list suppresses catalog persistence effect', () {
      const event = AgentModelListEvent(
        AgentModelList(models: <AgentModelInfo>[]),
      );

      final mutation = AgentConversationReducer.live().reduce(
        event,
        _initialState,
        _context(modelsRefreshing: true),
      );

      expect(mutation.accepted, isTrue);
      expect(
        mutation.effects.whereType<AgentRecordModelCatalogEffect>(),
        isEmpty,
      );
    });

    test('error logging is a before-mutation thread-independent effect', () {
      const event = AgentErrorEvent(
        message: 'boom',
        sessionId: _threadId,
        turnId: _turnId,
      );

      final mutation = AgentConversationReducer.live().reduce(
        event,
        _initialState,
        _context(),
      );
      final effect = mutation.effects.single as AgentLogProviderErrorEffect;

      expect(effect.event, same(event));
      expect(effect.timing, AgentConversationEffectTiming.beforeMutation);
      expect(effect.requireThread, isFalse);
      _expectDefaultScope(effect.scope, turnId: _turnId);
    });
  });

  group('live/history/replay reducer identity isolation', () {
    test('live facade and reducer share one monotonic local id namespace', () {
      final timelineIds = AgentConversationLocalTimelineIdGenerator(
        clock: () => _fixedClockValue,
      );
      final firstId = timelineIds.next('error');
      final reducer = AgentConversationReducer.live(timelineIds: timelineIds);

      final mutation = reducer.reduce(
        const AgentErrorEvent(
          message: 'provider failure',
          sessionId: _threadId,
          turnId: _turnId,
        ),
        _initialState,
        _context(),
      );
      final secondId =
          (mutation.timelineMutations.single
                  as AgentAddConversationMessageTimelineMutation)
              .message
              .id;

      expect(firstId, 'error-${_fixedClockValue.microsecondsSinceEpoch}-1');
      expect(secondId, 'error-${_fixedClockValue.microsecondsSinceEpoch}-2');
    });

    test('dedup sets, local ids, and error identity are not shared', () {
      final reducers = AgentConversationReducerContexts(
        clock: () => _fixedClockValue,
      );
      const deprecation = AgentDeprecationNoticeEvent(
        summary: 'same deprecation',
      );

      final liveDeprecation = reducers.live.reduce(
        deprecation,
        _initialState,
        _context(scope: AgentConversationReductionScope.live),
      );
      final duplicateLiveDeprecation = reducers.live.reduce(
        deprecation,
        _initialState,
        _context(scope: AgentConversationReductionScope.live),
      );
      final historyDeprecation = reducers.history.reduce(
        deprecation,
        _initialState,
        _context(scope: AgentConversationReductionScope.history),
      );
      final replayDeprecation = reducers.replay.reduce(
        deprecation,
        _initialState,
        _context(scope: AgentConversationReductionScope.replay),
      );

      expect(liveDeprecation.accepted, isTrue);
      _expectRejected(duplicateLiveDeprecation, reason: 'duplicateDeprecation');
      expect(historyDeprecation.accepted, isTrue);
      expect(replayDeprecation.accepted, isTrue);
      expect(
        <String>[
          _historyEventId(liveDeprecation),
          _historyEventId(historyDeprecation),
          _historyEventId(replayDeprecation),
        ],
        everyElement(
          'deprecation-${_fixedClockValue.microsecondsSinceEpoch}-1',
        ),
      );

      const error = AgentErrorEvent(
        message: 'scope-local failure',
        sessionId: _threadId,
        turnId: _turnId,
      );
      const completion = AgentTurnCompletedEvent(
        sessionId: _threadId,
        turnId: _turnId,
        status: AgentHistoryTurnStatus.failed,
        errorMessage: 'scope-local failure',
      );
      reducers.live.reduce(
        error,
        _initialState,
        _context(scope: AgentConversationReductionScope.live),
      );
      final liveCompletion = reducers.live.reduce(
        completion,
        _initialState,
        _context(scope: AgentConversationReductionScope.live),
      );
      final historyCompletion = reducers.history.reduce(
        completion,
        _initialState,
        _context(scope: AgentConversationReductionScope.history),
      );
      final replayCompletion = reducers.replay.reduce(
        completion,
        _initialState,
        _context(scope: AgentConversationReductionScope.replay),
      );

      expect(_runtimeTypes(liveCompletion.timelineMutations), const <Type>[
        AgentCompleteLiveTurnTimelineMutation,
      ]);
      expect(_runtimeTypes(historyCompletion.timelineMutations), const <Type>[
        AgentAddConversationMessageTimelineMutation,
        AgentCompleteLiveTurnTimelineMutation,
      ]);
      expect(_runtimeTypes(replayCompletion.timelineMutations), const <Type>[
        AgentAddConversationMessageTimelineMutation,
        AgentCompleteLiveTurnTimelineMutation,
      ]);
    });

    test('reducer rejects a context from a different reduction scope', () {
      final reducer = AgentConversationReducer.live();

      expect(
        () => reducer.reduce(
          const AgentStatusEvent(AgentProviderStatus.idle()),
          _initialState,
          _context(scope: AgentConversationReductionScope.history),
        ),
        throwsAssertionError,
      );
    });
  });
}

Map<String, List<_ReductionCase>> _reductionCasesByBatch() {
  return <String, List<_ReductionCase>>{
    'batch A lifecycle/thread': <_ReductionCase>[
      const _ReductionCase(
        name: 'status',
        event: AgentStatusEvent(AgentProviderStatus.idle()),
        uiUrgency: AgentUiUpdateUrgency.immediate,
      ),
      const _ReductionCase(
        name: 'session started',
        event: AgentSessionStartedEvent(
          AgentSession(
            id: _threadId,
            providerId: defaultAgentProviderId,
            title: 'Thread 1',
          ),
        ),
        uiUrgency: AgentUiUpdateUrgency.immediate,
        snapshot: AgentThreadSnapshotMutation.refresh,
        applicationEffectTypes: <Type>[AgentBindConversationModeThreadEffect],
      ),
      const _ReductionCase(
        name: 'thread status',
        event: AgentThreadStatusChangedEvent(
          threadId: _threadId,
          status: AgentThreadRuntimeStatus.active,
          waitingOnApproval: true,
        ),
        uiUrgency: AgentUiUpdateUrgency.immediate,
        snapshot: AgentThreadSnapshotMutation.refresh,
      ),
      const _ReductionCase(
        name: 'thread name',
        event: AgentThreadNameUpdatedEvent(
          threadId: _threadId,
          threadName: 'Renamed',
        ),
        uiUrgency: AgentUiUpdateUrgency.immediate,
        snapshot: AgentThreadSnapshotMutation.refresh,
      ),
      const _ReductionCase(
        name: 'thread preview',
        event: AgentThreadPreviewUpdatedEvent(
          threadId: _threadId,
          preview: 'Last turn summary',
        ),
        uiUrgency: AgentUiUpdateUrgency.immediate,
        snapshot: AgentThreadSnapshotMutation.refresh,
      ),
      const _ReductionCase(
        name: 'thread archived',
        event: AgentThreadArchivedEvent(threadId: _threadId),
      ),
      const _ReductionCase(
        name: 'thread unarchived',
        event: AgentThreadUnarchivedEvent(threadId: _threadId),
      ),
      const _ReductionCase(
        name: 'thread deleted',
        event: AgentThreadDeletedEvent(threadId: _threadId),
      ),
      const _ReductionCase(
        name: 'thread closed',
        event: AgentThreadClosedEvent(threadId: _threadId),
        timelineTypes: <Type>[AgentSettleInterruptedTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        snapshot: AgentThreadSnapshotMutation.refresh,
        applicationEffectTypes: <Type>[
          AgentClearPlanHandoffEffect,
          AgentSyncTurnRunningEffect,
        ],
      ),
      const _ReductionCase(
        name: 'thread compacted',
        event: AgentThreadCompactedEvent(threadId: _threadId, turnId: _turnId),
      ),
      const _ReductionCase(
        name: 'thread settings',
        event: AgentThreadSettingsUpdatedEvent(
          threadId: _threadId,
          model: 'gpt-test',
        ),
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[AgentApplyThreadSettingsEffect],
      ),
      const _ReductionCase(
        name: 'session config',
        event: AgentSessionConfigUpdatedEvent(
          sessionId: _threadId,
          options: <AgentSessionConfigOption>[
            AgentSessionConfigOption(
              id: 'model',
              name: 'Model',
              kind: AgentSessionConfigOptionKind.select,
              currentValue: 'gpt-test',
            ),
          ],
        ),
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[AgentSyncThreadSelectionEffect],
      ),
    ],
    'batch B turn': <_ReductionCase>[
      const _ReductionCase(
        name: 'turn started',
        event: AgentTurnStartedEvent(
          AgentTurn(id: _turnId, sessionId: _threadId),
        ),
        timelineTypes: <Type>[AgentBeginLiveTurnTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        snapshot: AgentThreadSnapshotMutation.refresh,
        applicationEffectTypes: <Type>[AgentSyncTurnRunningEffect],
      ),
      const _ReductionCase(
        name: 'turn completed',
        event: AgentTurnCompletedEvent(sessionId: _threadId, turnId: _turnId),
        timelineTypes: <Type>[AgentCompleteLiveTurnTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
        snapshot: AgentThreadSnapshotMutation.refresh,
        applicationEffectTypes: <Type>[
          AgentPreparePlanHandoffEffect,
          AgentTurnCompletedEffect,
          AgentSyncTurnRunningEffect,
          AgentAutoStartPlanExecutionEffect,
        ],
      ),
    ],
    'batch C message/reasoning': <_ReductionCase>[
      const _ReductionCase(
        name: 'message delta',
        event: AgentMessageDeltaEvent(
          messageId: 'message-1',
          delta: 'hello',
          role: AgentMessageRole.agent,
          kind: AgentMessageKind.plan,
          sessionId: _threadId,
          turnId: _turnId,
        ),
        timelineTypes: <Type>[AgentAppendMessageDeltaTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.nextFrame,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
      ),
      const _ReductionCase(
        name: 'reasoning delta',
        event: AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'thinking',
          sessionId: _threadId,
          turnId: _turnId,
        ),
        timelineTypes: <Type>[AgentAppendReasoningDeltaTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.nextFrame,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
      ),
      const _ReductionCase(
        name: 'message updated',
        event: AgentMessageUpdatedEvent(
          messageId: 'message-1',
          text: 'done',
          sessionId: _threadId,
          turnId: _turnId,
        ),
        timelineTypes: <Type>[AgentUpdateMessageTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
      ),
      const _ReductionCase(
        name: 'plan updated',
        event: AgentPlanUpdatedEvent(
          entries: <AgentPlanEntry>[AgentPlanEntry(content: 'Step 1')],
          sessionId: _threadId,
          turnId: _turnId,
        ),
        timelineTypes: <Type>[AgentReplaceActivePlanTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
      ),
    ],
    'batch D usage/context': <_ReductionCase>[
      const _ReductionCase(
        name: 'token usage',
        event: AgentTokenUsageEvent(
          tokenUsage: AgentTokenUsage(inputTokens: 10, totalTokens: 12),
          sessionId: _threadId,
          turnId: _turnId,
        ),
        timelineTypes: <Type>[AgentUpdateTurnTokenUsageTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
      ),
      const _ReductionCase(
        name: 'context window usage',
        event: AgentContextWindowUsageEvent(
          usedTokens: 10,
          modelContextWindow: 100,
          sessionId: _threadId,
          turnId: _turnId,
        ),
        timelineTypes: <Type>[AgentUpdateContextWindowUsageTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.nextFrame,
      ),
    ],
    'batch E tool/diff/plan': <_ReductionCase>[
      const _ReductionCase(
        name: 'tool call progress',
        event: AgentToolCallEvent(
          AgentToolCall(
            id: 'tool-1',
            title: 'Run tests',
            kind: AgentToolKind.execute,
            status: AgentToolStatus.inProgress,
            sessionId: _threadId,
            turnId: _turnId,
          ),
        ),
        timelineTypes: <Type>[AgentUpsertToolCallTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.nextFrame,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
      ),
      _ReductionCase(
        name: 'turn file changes',
        event: AgentTurnFileChangesEvent(
          sessionId: _threadId,
          turnId: _turnId,
          snapshot: AgentFileChangeSnapshot(
            revision: 1,
            replayability: AgentFileChangeReplayability.liveOnly,
            changes: const <AgentFileChange>[
              AgentFileChange(
                id: 'change-1',
                path: 'lib/a.dart',
                kind: AgentFileChangeKind.modified,
                evidence: AgentUnifiedPatchEvidence(
                  patch: 'diff --git a/a b/a',
                ),
              ),
            ],
          ),
        ),
        timelineTypes: const <Type>[AgentUpsertTurnFileChangesTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: const <Type>[AgentRequestAutoScroll],
      ),
    ],
    'batch F pending interaction': <_ReductionCase>[
      const _ReductionCase(
        name: 'auto approval review',
        event: AgentAutoApprovalReviewEvent(
          threadId: _threadId,
          turnId: _turnId,
          reviewId: 'review-1',
          status: 'denied',
        ),
        uiUrgency: AgentUiUpdateUrgency.immediate,
      ),
      const _ReductionCase(
        name: 'permission requested',
        event: AgentPermissionRequestedEvent(
          AgentPermissionRequest(
            id: 'permission-1',
            title: 'Run',
            kind: AgentPermissionKind.commandExecution,
            sessionId: _threadId,
            turnId: _turnId,
          ),
        ),
        timelineTypes: <Type>[AgentAddPermissionRequestTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[AgentAttentionEffect],
      ),
      const _ReductionCase(
        name: 'permission resolved',
        event: AgentPermissionResolvedEvent(
          requestId: 'permission-1',
          threadId: _threadId,
        ),
        timelineTypes: <Type>[AgentRemovePermissionRequestTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[AgentAttentionEffect],
      ),
      const _ReductionCase(
        name: 'question requested',
        event: AgentQuestionRequestedEvent(
          AgentQuestionRequest(
            id: 'question-request-1',
            title: 'Question',
            questions: <AgentUserInputQaPair>[
              AgentUserInputQaPair(questionId: 'q1', question: 'Continue?'),
            ],
            sessionId: _threadId,
            turnId: _turnId,
          ),
        ),
        timelineTypes: <Type>[AgentAddQuestionRequestTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[AgentAttentionEffect],
      ),
      const _ReductionCase(
        name: 'question resolved',
        event: AgentQuestionResolvedEvent(
          requestId: 'question-request-1',
          threadId: _threadId,
        ),
        timelineTypes: <Type>[AgentRemoveQuestionRequestTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[AgentAttentionEffect],
      ),
      const _ReductionCase(
        name: 'plan approval requested',
        event: AgentPlanApprovalRequestedEvent(
          AgentPlanApprovalRequest(
            id: 'plan-approval-1',
            title: 'Plan',
            markdown: 'Do it',
            sessionId: _threadId,
            turnId: _turnId,
          ),
        ),
        timelineTypes: <Type>[AgentAddPlanApprovalRequestTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[AgentAttentionEffect],
      ),
      const _ReductionCase(
        name: 'plan approval resolved',
        event: AgentPlanApprovalResolvedEvent(
          requestId: 'plan-approval-1',
          sessionId: _threadId,
        ),
        timelineTypes: <Type>[AgentRemovePlanApprovalRequestTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[AgentAttentionEffect],
      ),
    ],
    'batch G error/system/model': <_ReductionCase>[
      const _ReductionCase(
        name: 'model reroute',
        event: AgentModelReroutedEvent(
          threadId: _threadId,
          turnId: _turnId,
          fromModel: 'model-a',
          toModel: 'model-b',
          reason: 'highRiskCyberActivity',
        ),
        timelineTypes: <Type>[AgentAddHistoryEventTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
      ),
      const _ReductionCase(
        name: 'deprecation',
        event: AgentDeprecationNoticeEvent(
          summary: 'Deprecated',
          details: 'Upgrade',
        ),
        timelineTypes: <Type>[AgentAddHistoryEventTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
      ),
      _ReductionCase(
        name: 'system item',
        event: AgentSystemItemEvent(
          entry: AgentHistoryEventEntry(
            id: 'system-1',
            kind: AgentHistoryEventKind.system,
            title: '上下文已压缩',
            raw: AgentProviderRawPayload.wrap(<String, Object?>{
              'type': 'contextCompaction',
            }),
          ),
          sessionId: _threadId,
          turnId: _turnId,
        ),
        timelineTypes: <Type>[AgentAddHistoryEventTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
      ),
      const _ReductionCase(
        name: 'model list',
        event: AgentModelListEvent(
          AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'gpt-test',
                model: 'gpt-test',
                displayName: 'GPT Test',
              ),
            ],
          ),
        ),
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[
          AgentApplyModelListEffect,
          AgentRecordModelCatalogEffect,
        ],
      ),
      const _ReductionCase(
        name: 'error',
        event: AgentErrorEvent(
          message: 'boom',
          details: 'details',
          sessionId: _threadId,
          turnId: _turnId,
        ),
        timelineTypes: <Type>[AgentAddConversationMessageTimelineMutation],
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
        applicationEffectTypes: <Type>[AgentLogProviderErrorEffect],
      ),
    ],
  };
}

List<_ReductionCase> _allReductionCases() {
  return _reductionCasesByBatch().values
      .expand((batch) => batch)
      .toList(growable: false);
}

AgentConversationReducerContext _context({
  AgentConversationReductionScope scope = AgentConversationReductionScope.live,
  String? selectedThreadId = _threadId,
  bool requiresResumedSelectedThread = false,
  String? pendingTurnGroupId,
  Set<String> hasTurns = const <String>{_turnId},
  Set<String> historyTurns = const <String>{},
  bool modelsRefreshing = false,
}) {
  return AgentConversationReducerContext(
    scope: scope,
    selectedThreadId: selectedThreadId,
    requiresResumedSelectedThread: requiresResumedSelectedThread,
    pendingTurnGroupId: pendingTurnGroupId,
    hasTurn: hasTurns.contains,
    isHistoryTurnId: historyTurns.contains,
    hasRunningTurnExcluding: (_) => false,
    modelsRefreshing: modelsRefreshing,
    activeProviderName: 'Codex',
    activeProviderConfig: defaultCodexAgentProviderConfig,
    effectScope: AgentConversationEffectScope(
      reductionScope: scope,
      providerId: defaultAgentProviderId,
      listenerGeneration: 7,
      runtimeId: 'runtime-1',
      connectionEpoch: 3,
      providerLifecycleState: 'ready',
      threadId: selectedThreadId,
    ),
  );
}

void _expectReduction(
  AgentConversationReduction mutation,
  _ReductionCase expected,
) {
  expect(mutation.accepted, isTrue, reason: expected.name);
  expect(mutation.rejectionReason, isNull, reason: expected.name);
  expect(
    _runtimeTypes(mutation.timelineMutations),
    expected.timelineTypes,
    reason: '${expected.name}: timeline',
  );
  expect(
    mutation.threadSnapshot,
    expected.snapshot,
    reason: '${expected.name}: thread snapshot',
  );
  expect(
    _runtimeTypes(mutation.effects),
    expected.applicationEffectTypes,
    reason: '${expected.name}: application effects',
  );

  final uiUpdate = mutation.uiUpdate;
  final expectedUrgency = expected.uiUrgency;
  if (expectedUrgency == null) {
    expect(uiUpdate, isNull, reason: '${expected.name}: UI request');
    return;
  }
  expect(uiUpdate, isNotNull, reason: '${expected.name}: UI request');
  expect(
    uiUpdate!.urgency,
    expectedUrgency,
    reason: '${expected.name}: UI urgency',
  );
  expect(
    _runtimeTypes(uiUpdate.effects),
    expected.uiEffectTypes,
    reason: '${expected.name}: UI effects',
  );
}

void _expectRejected(
  AgentConversationReduction mutation, {
  required String reason,
  List<Type> effectTypes = const <Type>[],
}) {
  expect(mutation.accepted, isFalse);
  expect(mutation.rejectionReason, reason);
  expect(mutation.timelineMutations, isEmpty);
  expect(mutation.uiUpdate, isNull);
  expect(mutation.threadSnapshot, isNull);
  expect(_runtimeTypes(mutation.effects), effectTypes);
}

void _expectDefaultScope(AgentConversationEffectScope scope, {String? turnId}) {
  expect(scope.reductionScope, AgentConversationReductionScope.live);
  expect(scope.providerId, defaultAgentProviderId);
  expect(scope.listenerGeneration, 7);
  expect(scope.runtimeId, 'runtime-1');
  expect(scope.connectionEpoch, 3);
  expect(scope.providerLifecycleState, 'ready');
  expect(scope.threadId, _threadId);
  expect(scope.turnId, turnId);
}

List<Type> _runtimeTypes(Iterable<Object> values) {
  return values.map((value) => value.runtimeType).toList(growable: false);
}

String _historyEventId(AgentConversationReduction mutation) {
  return (mutation.timelineMutations.single
          as AgentAddHistoryEventTimelineMutation)
      .event
      .id;
}

final class _ReductionCase {
  const _ReductionCase({
    required this.name,
    required this.event,
    this.timelineTypes = const <Type>[],
    this.uiUrgency,
    this.uiEffectTypes = const <Type>[],
    this.snapshot,
    this.applicationEffectTypes = const <Type>[],
  });

  final String name;
  final AgentEvent event;
  final List<Type> timelineTypes;
  final AgentUiUpdateUrgency? uiUrgency;
  final List<Type> uiEffectTypes;
  final AgentThreadSnapshotMutation? snapshot;
  final List<Type> applicationEffectTypes;
}
