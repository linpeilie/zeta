import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_effect.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mutation.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_reducer.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

const _threadId = 'thread-1';
const _turnId = 'turn-1';
final _fixedClockValue = DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7);

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
            final mutation = reducer.reduce(reductionCase.event, _context());

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
        _context(hasTurns: const <String>{}),
      );
      final rejected = reducer.reduce(
        event,
        _context(
          selectedThreadId: 'other-thread',
          hasTurns: const <String>{'foreign-turn'},
          pendingTurnGroupId: 'foreign-turn',
        ),
      );

      expect(accepted.accepted, isTrue);
      _expectRejected(rejected, reason: 'currentThreadMismatch');
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

      expect(reducer.reduce(knownTurnEvent, context).accepted, isTrue);
      expect(reducer.reduce(pendingTurnEvent, context).accepted, isTrue);
      _expectRejected(
        reducer.reduce(unknownTurnEvent, context),
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
            .reduce(event, _context(selectedThreadId: null))
            .accepted,
        isTrue,
      );
      _expectRejected(
        AgentConversationReducer.live().reduce(
          event,
          _context(selectedThreadId: null, requiresResumedSelectedThread: true),
        ),
        reason: 'sessionStartedThreadMismatch',
      );
      expect(
        AgentConversationReducer.live()
            .reduce(event, _context(requiresResumedSelectedThread: true))
            .accepted,
        isTrue,
      );
    });
  });

  group('detached critical event allowlist', () {
    test('contains exactly the eight compatibility-critical event types', () {
      const criticalTypes = <Type>{
        AgentStatusEvent,
        AgentErrorEvent,
        AgentTurnCompletedEvent,
        AgentThreadClosedEvent,
        AgentPermissionRequestedEvent,
        AgentPermissionResolvedEvent,
        AgentPlanApprovalRequestedEvent,
        AgentPlanApprovalResolvedEvent,
      };
      final cases = _allReductionCases();

      for (final reductionCase in cases) {
        expect(
          AgentConversationReducer.isCriticalDetachedEvent(reductionCase.event),
          criticalTypes.contains(reductionCase.event.runtimeType),
          reason: reductionCase.name,
        );
      }
      expect(
        cases
            .where(
              (item) =>
                  AgentConversationReducer.isCriticalDetachedEvent(item.event),
            )
            .length,
        criticalTypes.length,
      );
    });
  });

  group('turn compatibility invariants', () {
    test('interrupted turn settles through ordered synchronous mutations', () {
      final mutation = AgentConversationReducer.live().settleInterruptedTurn(
        fallbackTurnId: 'fallback-turn',
      );

      expect(mutation.accepted, isTrue);
      expect(_runtimeTypes(mutation.stateChangesBeforeTimeline), const <Type>[
        AgentPrepareInterruptedTurnChange,
      ]);
      expect(_runtimeTypes(mutation.timelineMutations), const <Type>[
        AgentSettleInterruptedTimelineMutation,
      ]);
      expect(
        (mutation.timelineMutations.single
                as AgentSettleInterruptedTimelineMutation)
            .fallbackTurnId,
        'fallback-turn',
      );
      expect(_runtimeTypes(mutation.stateChanges), const <Type>[
        AgentFinalizeInterruptedTurnChange,
      ]);
      expect(
        mutation.uiUpdate?.regions,
        unorderedEquals(const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        }),
      );
      expect(mutation.uiUpdate?.urgency, AgentUiUpdateUrgency.immediate);
      expect(
        mutation.uiResolution.includePendingInteractionWhenStateChanges,
        isTrue,
      );
      expect(mutation.threadSnapshot, AgentThreadSnapshotMutation.refresh);
      expect(mutation.effects, isEmpty);
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

      final errorMutation = reducer.reduce(error, context);
      final deduplicatedCompletion = reducer.reduce(completion, context);
      reducer.reduce(
        const AgentTurnStartedEvent(
          AgentTurn(id: _turnId, sessionId: _threadId),
        ),
        context,
      );
      final completionAfterNewTurn = reducer.reduce(completion, context);

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
          _context(),
        );

        expect(
          mutation.stateChangesBeforeTimeline.single,
          isA<AgentPrepareTurnCompletedChange>(),
        );
        expect(
          (mutation.stateChangesBeforeTimeline.single
                  as AgentPrepareTurnCompletedChange)
              .event,
          same(event),
        );
        expect(
          mutation.stateChanges.single,
          isA<AgentFinalizeTurnCompletedChange>(),
        );
        expect(
          (mutation.stateChanges.single as AgentFinalizeTurnCompletedChange)
              .event,
          same(event),
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
          _context(),
        );

        expect(mutation.accepted, isTrue);
        expect(_runtimeTypes(mutation.timelineMutations), const <Type>[
          AgentUpsertToolCallTimelineMutation,
        ]);
        expect(mutation.stateChanges, isEmpty);
        expect(mutation.uiUpdate?.urgency, AgentUiUpdateUrgency.immediate);
        expect(
          _runtimeTypes(mutation.uiUpdate?.effects ?? const []),
          const <Type>[AgentRequestAutoScroll],
        );
        expect(mutation.uiResolution.includeHeaderWhenActivityChanges, isTrue);
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
          _context(historyTurns: const <String>{_turnId}),
        );

        expect(
          mutation.uiUpdate?.regions,
          unorderedEquals(const <AgentUiRegion>{
            AgentUiRegion.header,
            AgentUiRegion.composer,
            AgentUiRegion.history,
          }),
        );
        expect(
          mutation.uiUpdate?.regions.contains(AgentUiRegion.liveTurn),
          isFalse,
        );
      },
    );

    test('error timeline mutation exposes only normalized message fields', () {
      const event = AgentErrorEvent(
        message: 'boom',
        details: 'details',
        sessionId: _threadId,
        turnId: _turnId,
        raw: <String, Object?>{'providerSecret': 'must-not-leak'},
      );

      final mutation = AgentConversationReducer.live(
        clock: () => _fixedClockValue,
      ).reduce(event, _context());
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
        _context(),
      );
      final effect = mutation.effects.single as AgentTurnCompletedEffect;

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
        _context(),
      );
      final resolved = AgentConversationReducer.live().reduce(
        const AgentPermissionResolvedEvent(
          requestId: 'permission-1',
          threadId: _threadId,
        ),
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
        _context(),
      );
      final effect = mutation.effects.single as AgentRecordModelCatalogEffect;

      expect(effect.timing, AgentConversationEffectTiming.afterMutation);
      expect(effect.requireThread, isFalse);
      expect(effect.config, same(AgentProviderConfig.defaultCodex));
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
        _context(modelsRefreshing: true),
      );

      expect(mutation.accepted, isTrue);
      expect(mutation.effects, isEmpty);
    });

    test('error logging is a before-mutation thread-independent effect', () {
      const event = AgentErrorEvent(
        message: 'boom',
        sessionId: _threadId,
        turnId: _turnId,
      );

      final mutation = AgentConversationReducer.live().reduce(
        event,
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
        _context(scope: AgentConversationReductionScope.live),
      );
      final duplicateLiveDeprecation = reducers.live.reduce(
        deprecation,
        _context(scope: AgentConversationReductionScope.live),
      );
      final historyDeprecation = reducers.history.reduce(
        deprecation,
        _context(scope: AgentConversationReductionScope.history),
      );
      final replayDeprecation = reducers.replay.reduce(
        deprecation,
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
        _context(scope: AgentConversationReductionScope.live),
      );
      final liveCompletion = reducers.live.reduce(
        completion,
        _context(scope: AgentConversationReductionScope.live),
      );
      final historyCompletion = reducers.history.reduce(
        completion,
        _context(scope: AgentConversationReductionScope.history),
      );
      final replayCompletion = reducers.replay.reduce(
        completion,
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
        afterStateTypes: <Type>[AgentSetProviderStatusChange],
        uiRegions: <AgentUiRegion>{},
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
        afterStateTypes: <Type>[AgentApplySessionStartedChange],
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        uiUrgency: AgentUiUpdateUrgency.immediate,
        snapshot: AgentThreadSnapshotMutation.refresh,
      ),
      const _ReductionCase(
        name: 'thread status',
        event: AgentThreadStatusChangedEvent(
          threadId: _threadId,
          status: AgentThreadRuntimeStatus.active,
          waitingOnApproval: true,
        ),
        afterStateTypes: <Type>[AgentApplyThreadRuntimeStatusChange],
        uiRegions: <AgentUiRegion>{AgentUiRegion.header},
        uiUrgency: AgentUiUpdateUrgency.immediate,
        snapshot: AgentThreadSnapshotMutation.refresh,
      ),
      const _ReductionCase(
        name: 'thread name',
        event: AgentThreadNameUpdatedEvent(
          threadId: _threadId,
          threadName: 'Renamed',
        ),
        afterStateTypes: <Type>[AgentApplyThreadNameChange],
        uiRegions: <AgentUiRegion>{AgentUiRegion.header},
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
        beforeStateTypes: <Type>[AgentPrepareInterruptedTurnChange],
        timelineTypes: <Type>[AgentSettleInterruptedTimelineMutation],
        afterStateTypes: <Type>[AgentFinalizeInterruptedTurnChange],
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        uiUrgency: AgentUiUpdateUrgency.immediate,
        includePendingInteractionWhenStateChanges: true,
        snapshot: AgentThreadSnapshotMutation.refresh,
      ),
      const _ReductionCase(
        name: 'thread compacted',
        event: AgentThreadCompactedEvent(threadId: _threadId, turnId: _turnId),
        afterStateTypes: <Type>[AgentSetCompactingChange],
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        uiUrgency: AgentUiUpdateUrgency.immediate,
      ),
      const _ReductionCase(
        name: 'thread settings',
        event: AgentThreadSettingsUpdatedEvent(
          threadId: _threadId,
          model: 'gpt-test',
        ),
        afterStateTypes: <Type>[AgentApplyThreadSettingsChange],
        uiRegions: <AgentUiRegion>{AgentUiRegion.composer},
        uiUrgency: AgentUiUpdateUrgency.immediate,
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
        afterStateTypes: <Type>[AgentApplySessionConfigChange],
        uiRegions: <AgentUiRegion>{AgentUiRegion.composer},
        uiUrgency: AgentUiUpdateUrgency.immediate,
      ),
    ],
    'batch B turn': <_ReductionCase>[
      const _ReductionCase(
        name: 'turn started',
        event: AgentTurnStartedEvent(
          AgentTurn(id: _turnId, sessionId: _threadId),
        ),
        timelineTypes: <Type>[AgentBeginLiveTurnTimelineMutation],
        afterStateTypes: <Type>[AgentFinalizeTurnStartedChange],
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        uiUrgency: AgentUiUpdateUrgency.immediate,
        snapshot: AgentThreadSnapshotMutation.refresh,
      ),
      const _ReductionCase(
        name: 'turn completed',
        event: AgentTurnCompletedEvent(sessionId: _threadId, turnId: _turnId),
        beforeStateTypes: <Type>[AgentPrepareTurnCompletedChange],
        timelineTypes: <Type>[AgentCompleteLiveTurnTimelineMutation],
        afterStateTypes: <Type>[AgentFinalizeTurnCompletedChange],
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
        includePendingInteractionWhenStateChanges: true,
        snapshot: AgentThreadSnapshotMutation.refresh,
        applicationEffectTypes: <Type>[AgentTurnCompletedEffect],
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.expansion,
        },
        uiUrgency: AgentUiUpdateUrgency.nextFrame,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
        includeHeaderWhenActivityChanges: true,
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.expansion,
        },
        uiUrgency: AgentUiUpdateUrgency.nextFrame,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
        includeHeaderWhenActivityChanges: true,
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
        uiRegions: <AgentUiRegion>{AgentUiRegion.liveTurn},
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
        uiRegions: <AgentUiRegion>{AgentUiRegion.liveTurn},
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.composer,
          AgentUiRegion.liveTurn,
        },
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.composer,
        },
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
        afterStateTypes: <Type>[AgentApplyToolStatusChange],
        uiRegions: <AgentUiRegion>{AgentUiRegion.liveTurn},
        uiUrgency: AgentUiUpdateUrgency.nextFrame,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
        includeHeaderWhenActivityChanges: true,
      ),
      const _ReductionCase(
        name: 'turn diff',
        event: AgentTurnDiffEvent(
          sessionId: _threadId,
          turnId: _turnId,
          diff: 'diff --git a/a b/a',
        ),
        timelineTypes: <Type>[AgentUpsertTurnDiffTimelineMutation],
        uiRegions: <AgentUiRegion>{AgentUiRegion.liveTurn},
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
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
        afterStateTypes: <Type>[AgentApplyAutoApprovalReviewChange],
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.liveTurn,
          AgentUiRegion.history,
        },
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.pendingInteraction,
        },
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
        afterStateTypes: <Type>[AgentSetModelRerouteNoticeChange],
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
        },
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
        uiRegions: <AgentUiRegion>{AgentUiRegion.liveTurn},
        uiUrgency: AgentUiUpdateUrgency.immediate,
        uiEffectTypes: <Type>[AgentRequestAutoScroll],
      ),
      const _ReductionCase(
        name: 'system item',
        event: AgentSystemItemEvent(
          entry: AgentHistoryEventEntry(
            id: 'system-1',
            kind: AgentHistoryEventKind.system,
            title: '上下文已压缩',
            raw: <String, Object?>{'type': 'contextCompaction'},
          ),
          sessionId: _threadId,
          turnId: _turnId,
        ),
        timelineTypes: <Type>[AgentAddHistoryEventTimelineMutation],
        afterStateTypes: <Type>[AgentSetCompactingChange],
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
          AgentUiRegion.composer,
        },
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
        afterStateTypes: <Type>[AgentHandleModelListChange],
        uiRegions: <AgentUiRegion>{AgentUiRegion.composer},
        uiUrgency: AgentUiUpdateUrgency.immediate,
        applicationEffectTypes: <Type>[AgentRecordModelCatalogEffect],
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
        uiRegions: <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
        },
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
    modelsRefreshing: modelsRefreshing,
    activeProviderName: 'Codex',
    activeProviderConfig: AgentProviderConfig.defaultCodex,
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
  AgentConversationMutation mutation,
  _ReductionCase expected,
) {
  expect(mutation.accepted, isTrue, reason: expected.name);
  expect(mutation.rejectionReason, isNull, reason: expected.name);
  expect(
    _runtimeTypes(mutation.stateChangesBeforeTimeline),
    expected.beforeStateTypes,
    reason: '${expected.name}: before state',
  );
  expect(
    _runtimeTypes(mutation.timelineMutations),
    expected.timelineTypes,
    reason: '${expected.name}: timeline',
  );
  expect(
    _runtimeTypes(mutation.stateChanges),
    expected.afterStateTypes,
    reason: '${expected.name}: after state',
  );
  expect(
    mutation.threadSnapshot,
    expected.snapshot,
    reason: '${expected.name}: thread snapshot',
  );
  expect(
    mutation.uiResolution.includeHeaderWhenActivityChanges,
    expected.includeHeaderWhenActivityChanges,
    reason: '${expected.name}: activity resolution',
  );
  expect(
    mutation.uiResolution.includePendingInteractionWhenStateChanges,
    expected.includePendingInteractionWhenStateChanges,
    reason: '${expected.name}: interaction resolution',
  );
  expect(
    _runtimeTypes(mutation.effects),
    expected.applicationEffectTypes,
    reason: '${expected.name}: application effects',
  );

  final uiUpdate = mutation.uiUpdate;
  final expectedRegions = expected.uiRegions;
  if (expectedRegions == null) {
    expect(uiUpdate, isNull, reason: '${expected.name}: UI request');
    return;
  }
  expect(uiUpdate, isNotNull, reason: '${expected.name}: UI request');
  expect(
    uiUpdate!.regions,
    unorderedEquals(expectedRegions),
    reason: '${expected.name}: UI regions',
  );
  expect(
    uiUpdate.urgency,
    expected.uiUrgency,
    reason: '${expected.name}: UI urgency',
  );
  expect(
    _runtimeTypes(uiUpdate.effects),
    expected.uiEffectTypes,
    reason: '${expected.name}: UI effects',
  );
}

void _expectRejected(
  AgentConversationMutation mutation, {
  required String reason,
  List<Type> effectTypes = const <Type>[],
}) {
  expect(mutation.accepted, isFalse);
  expect(mutation.rejectionReason, reason);
  expect(mutation.stateChangesBeforeTimeline, isEmpty);
  expect(mutation.timelineMutations, isEmpty);
  expect(mutation.stateChanges, isEmpty);
  expect(mutation.uiUpdate, isNull);
  expect(mutation.uiResolution.includeHeaderWhenActivityChanges, isFalse);
  expect(
    mutation.uiResolution.includePendingInteractionWhenStateChanges,
    isFalse,
  );
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

String _historyEventId(AgentConversationMutation mutation) {
  return (mutation.timelineMutations.single
          as AgentAddHistoryEventTimelineMutation)
      .event
      .id;
}

final class _ReductionCase {
  const _ReductionCase({
    required this.name,
    required this.event,
    this.beforeStateTypes = const <Type>[],
    this.timelineTypes = const <Type>[],
    this.afterStateTypes = const <Type>[],
    this.uiRegions,
    this.uiUrgency,
    this.uiEffectTypes = const <Type>[],
    this.includeHeaderWhenActivityChanges = false,
    this.includePendingInteractionWhenStateChanges = false,
    this.snapshot,
    this.applicationEffectTypes = const <Type>[],
  });

  final String name;
  final AgentEvent event;
  final List<Type> beforeStateTypes;
  final List<Type> timelineTypes;
  final List<Type> afterStateTypes;
  final Set<AgentUiRegion>? uiRegions;
  final AgentUiUpdateUrgency? uiUrgency;
  final List<Type> uiEffectTypes;
  final bool includeHeaderWhenActivityChanges;
  final bool includePendingInteractionWhenStateChanges;
  final AgentThreadSnapshotMutation? snapshot;
  final List<Type> applicationEffectTypes;
}
