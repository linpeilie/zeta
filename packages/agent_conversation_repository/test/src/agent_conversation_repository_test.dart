import 'dart:async';

import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_history_client/agent_history_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

import 'test_fakes.dart';

void main() {
  const draftKey = ConversationKey.draft(
    providerId: 'provider',
    entryId: 'entry',
  );

  test(
    'draft lifecycle exposes snapshots and releases borrowed leases',
    () async {
      final runtime = TestRuntime('provider');
      final conversation = TestConversationPort();
      final ports = TestResponsePorts();
      final store = TestTurnContextStore();
      final repository = AgentConversationRepository(
        turnContextStore: store,
        logger: loggerFor('conversation-test'),
        clock: Clock.fixed(DateTime.utc(2026)),
      );
      final bundle = testBundle(
        runtime: runtime,
        conversation: conversation,
        ports: ports,
      );
      final first = await repository.openConversation(
        bundle: bundle,
        key: draftKey,
        context: const AgentContext(projectPath: 'project'),
      );
      final second = await repository.openConversation(
        bundle: bundle,
        key: draftKey,
        context: const AgentContext(projectPath: 'updated'),
      );
      final otherRuntime = TestRuntime('provider');
      await expectLater(
        repository.openConversation(
          bundle: testBundle(
            runtime: otherRuntime,
            conversation: TestConversationPort(),
          ),
          key: draftKey,
          context: const AgentContext(),
        ),
        _failure(AgentConversationFailureCode.invalidIdentity),
      );
      final snapshots = <ConversationSnapshot>[];
      final subscription = repository.snapshots(draftKey).listen(snapshots.add);

      expect(first.generation, second.generation);
      expect(first.isReleased, isFalse);
      expect(repository.snapshotOf(draftKey)?.phase, ConversationPhase.ready);
      expect(repository.diagnosticsOf(draftKey).runtimeLeaseCount, 1);
      expect(repository.diagnosticsOf(draftKey).reducerInstanceCount, 3);

      final turn = await repository.submit(
        key: draftKey,
        request: const TurnRequest(
          message: 'hello',
          clientUserMessageId: 'user-message',
        ),
      );
      expect(turn.id, 'turn-1');
      expect(conversation.startCalls, 1);
      expect(conversation.sendCalls, 1);
      expect(conversation.lastContext?.projectPath, 'updated');
      expect(repository.snapshotOf(draftKey)?.activeTurn?.id, 'turn-1');

      await repository.steer(
        key: draftKey,
        request: const SteerRequest(message: 'steer'),
      );
      await repository.cancel(draftKey);
      expect(ports.steerCalls, 1);
      expect(conversation.cancelCalls, 1);

      final permission = AgentPermissionRequest(
        id: 'permission',
        title: 'Permission',
        kind: AgentPermissionKind.other,
        sessionId: 'thread-1',
        turnId: 'turn-1',
      );
      final question = AgentQuestionRequest(
        id: 'question',
        title: 'Question',
        questions: const <AgentUserInputQaPair>[],
        sessionId: 'thread-1',
        turnId: 'turn-1',
      );
      final plan = AgentPlanApprovalRequest(
        id: 'plan',
        title: 'Plan',
        markdown: 'plan',
        sessionId: 'thread-1',
        turnId: 'turn-1',
      );
      runtime.eventController
        ..add(AgentPermissionRequestedEvent(permission))
        ..add(AgentQuestionRequestedEvent(question))
        ..add(AgentPlanApprovalRequestedEvent(plan));
      await _pump();
      expect(repository.snapshotOf(draftKey)?.pendingPermissions, hasLength(1));
      expect(repository.snapshotOf(draftKey)?.pendingQuestions, hasLength(1));
      expect(
        repository.snapshotOf(draftKey)?.pendingPlanApprovals,
        hasLength(1),
      );

      await repository.respondToPermission(
        draftKey,
        AgentPermissionDecision(requestId: 'permission', approved: true),
      );
      await repository.respondToQuestion(
        draftKey,
        AgentQuestionResponse(requestId: 'question'),
      );
      await repository.respondToPlanApproval(
        draftKey,
        const AgentPlanApprovalDecision(
          requestId: 'plan',
          kind: AgentPlanApprovalDecisionKind.accepted,
        ),
      );
      expect(ports.permissionCalls, 1);
      expect(ports.questionCalls, 1);
      expect(ports.planCalls, 1);
      expect(repository.snapshotOf(draftKey)?.pendingPermissions, isEmpty);
      expect(snapshots, isNotEmpty);

      runtime.eventController
        ..add(
          AgentTurnStartedEvent(
            AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
          ),
        )
        ..add(
          AgentModelReroutedEvent(
            threadId: 'thread-1',
            turnId: 'turn-1',
            fromModel: 'a',
            toModel: 'b',
            reason: 'test',
          ),
        )
        ..add(
          AgentSystemItemEvent(
            entry: AgentHistoryEventEntry(
              id: 'system',
              kind: AgentHistoryEventKind.system,
              title: 'System',
            ),
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        )
        ..add(
          AgentErrorEvent(
            message: 'error',
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        )
        ..add(
          AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
      await _pump();

      await first.release();
      await first.release();
      expect(first.isReleased, isTrue);
      expect(repository.snapshotOf(draftKey), isNotNull);
      ports.error = Exception('unsubscribe');
      await second.release();
      expect(repository.snapshotOf(draftKey), isNull);
      expect(ports.unsubscribeCalls, 1);
      expect(runtime.disposeCalls, 0);
      await subscription.cancel();
      await repository.close();
      await repository.close();
      await runtime.eventController.close();
      await otherRuntime.eventController.close();
    },
  );

  test(
    'thread open merges provider history, replay, and turn context',
    () async {
      final runtime = TestRuntime('provider');
      final conversation = TestConversationPort();
      final history = TestThreadCatalog();
      final store = TestTurnContextStore();
      final startedAt = DateTime.utc(2026);
      history.snapshot = AgentThreadHistorySnapshot(
        threadId: 'thread-1',
        turns: <AgentHistoryTurn>[
          AgentHistoryTurn(
            id: 'history-turn',
            entries: <AgentHistoryEntry>[
              AgentHistoryMessageEntry(
                id: 'history-message',
                role: AgentMessageRole.agent,
                text: 'history',
              ),
            ],
            startedAt: startedAt,
          ),
          AgentHistoryTurn(
            id: 'fallback-turn',
            status: AgentHistoryTurnStatus.completed,
          ),
        ],
      );
      store.values['provider\u0000thread-1'] = AgentThreadTurnContext(
        providerId: 'provider',
        threadId: 'thread-1',
        turns: <AgentTurnContextRecord>[
          const AgentTurnContextRecord(
            turnId: 'history-turn',
            modelId: 'local-model',
          ),
        ],
      );
      final repository = AgentConversationRepository(
        turnContextStore: store,
        logger: loggerFor('history-test'),
        historyInputs: ({required key, required bundle}) async =>
            <HistoryReplayInput>[
              HistoryReplayInput(
                sourceId: 'replay',
                read: () async =>
                    '{"id":"history-turn"}\n'
                    '{"id":"fallback-turn"}\n'
                    '{"id":"replay-turn"}\nnot-json',
                decode: (record) => AgentHistoryTurn(
                  id: record['id']! as String,
                  status: record['id'] == 'history-turn'
                      ? AgentHistoryTurnStatus.completed
                      : AgentHistoryTurnStatus.unknown,
                ),
              ),
            ],
      );
      const key = ConversationKey.thread(
        providerId: 'provider',
        threadId: 'thread-1',
      );
      final handle = await repository.openConversation(
        bundle: testBundle(
          runtime: runtime,
          conversation: conversation,
          history: history,
        ),
        key: key,
        context: const AgentContext(projectPath: 'project'),
      );

      final snapshot = repository.snapshotOf(key)!;
      expect(conversation.resumeCalls, 1);
      expect(history.calls, 1);
      expect(snapshot.turns.map((turn) => turn.id), <String>[
        'history-turn',
        'fallback-turn',
        'replay-turn',
      ]);
      expect(snapshot.session?.id, 'thread-1');
      await handle.release();
      await repository.close();
      await runtime.eventController.close();
    },
  );

  test('rejects mismatched, out-of-order, and old-generation events', () async {
    final runtime = TestRuntime('provider');
    final conversation = TestConversationPort();
    final repository = AgentConversationRepository(
      turnContextStore: TestTurnContextStore(),
      logger: loggerFor('generation-test'),
    );
    final bundle = testBundle(runtime: runtime, conversation: conversation);
    final first = await repository.openConversation(
      bundle: bundle,
      key: draftKey,
      context: const AgentContext(),
    );
    runtime.eventController
      ..add(
        AgentSessionStartedEvent(
          AgentSession(id: 'foreign-thread', providerId: 'other-provider'),
        ),
      )
      ..add(
        AgentThreadStatusChangedEvent(
          threadId: 'other-thread',
          status: AgentThreadRuntimeStatus.active,
        ),
      )
      ..add(
        AgentMessageDeltaEvent(
          messageId: 'ghost',
          delta: 'ghost',
          role: AgentMessageRole.agent,
          turnId: 'unknown-turn',
        ),
      )
      ..add(
        AgentMessageUpdatedEvent(
          messageId: 'foreign-session',
          sessionId: 'foreign-thread',
        ),
      );
    await _pump();
    expect(repository.diagnosticsOf(draftKey).rejectedOutOfOrderEvents, 4);

    runtime.eventController.add(
      AgentMessageDeltaEvent(
        messageId: 'old',
        delta: 'old',
        role: AgentMessageRole.agent,
      ),
    );
    await first.release();
    final second = await repository.openConversation(
      bundle: bundle,
      key: draftKey,
      context: const AgentContext(),
    );
    await _pump();
    expect(second.generation, greaterThan(first.generation));
    expect(repository.snapshotOf(draftKey)?.turns, isEmpty);
    await second.release();
    await repository.close();
    await runtime.eventController.close();
  });

  test(
    'source errors become typed snapshot failures without payload logging',
    () async {
      final runtime = TestRuntime('provider');
      final repository = AgentConversationRepository(
        turnContextStore: TestTurnContextStore(),
        logger: loggerFor('source-error-test'),
      );
      await repository.openConversation(
        bundle: testBundle(
          runtime: runtime,
          conversation: TestConversationPort(),
        ),
        key: draftKey,
        context: const AgentContext(),
      );
      runtime.eventController.addError(StateError('private payload'));
      await _pump();
      expect(
        repository.snapshotOf(draftKey)?.failure?.code,
        AgentConversationFailureCode.providerOperationFailed,
      );
      await repository.close();
      await runtime.eventController.close();
    },
  );

  test(
    'natural source completion marks only the current conversation failed',
    () async {
      final runtime = TestRuntime('provider');
      final repository = AgentConversationRepository(
        turnContextStore: TestTurnContextStore(),
        logger: loggerFor('source-done-test'),
      );
      await repository.openConversation(
        bundle: testBundle(
          runtime: runtime,
          conversation: TestConversationPort(),
        ),
        key: draftKey,
        context: const AgentContext(),
      );
      await runtime.eventController.close();
      await _pump();
      expect(
        repository.snapshotOf(draftKey)?.failure?.code,
        AgentConversationFailureCode.providerOperationFailed,
      );
      await repository.close();
    },
  );

  group('typed failure boundaries', () {
    test(
      'identity, concurrent open, initialize, and history failures',
      () async {
        final runtime = TestRuntime('provider');
        final repository = AgentConversationRepository(
          turnContextStore: TestTurnContextStore(),
          logger: loggerFor('open-failure-test'),
        );
        final bundle = testBundle(
          runtime: runtime,
          conversation: TestConversationPort(),
        );
        await expectLater(
          repository.openConversation(
            bundle: bundle,
            key: const ConversationKey.draft(
              providerId: 'other',
              entryId: 'entry',
            ),
            context: const AgentContext(),
          ),
          _failure(AgentConversationFailureCode.invalidIdentity),
        );

        runtime.initializeBarrier = Completer<void>();
        final opening = repository.openConversation(
          bundle: bundle,
          key: draftKey,
          context: const AgentContext(),
        );
        await expectLater(
          repository.openConversation(
            bundle: bundle,
            key: draftKey,
            context: const AgentContext(),
          ),
          _failure(AgentConversationFailureCode.conversationAlreadyOpening),
        );
        runtime.initializeBarrier!.complete();
        final handle = await opening;
        await handle.release();

        final failedRuntime = TestRuntime('provider')
          ..initializeError = Exception('initialize');
        await expectLater(
          repository.openConversation(
            bundle: testBundle(
              runtime: failedRuntime,
              conversation: TestConversationPort(),
            ),
            key: draftKey,
            context: const AgentContext(),
          ),
          _failure(AgentConversationFailureCode.providerOperationFailed),
        );

        final sourceRuntime = TestRuntime('provider')
          ..eventsError = Exception('events');
        await expectLater(
          repository.openConversation(
            bundle: testBundle(
              runtime: sourceRuntime,
              conversation: TestConversationPort(),
            ),
            key: draftKey,
            context: const AgentContext(),
          ),
          _failure(AgentConversationFailureCode.providerOperationFailed),
        );

        final historyRuntime = TestRuntime('provider');
        final history = TestThreadCatalog()..error = Exception('history');
        await expectLater(
          repository.openConversation(
            bundle: testBundle(
              runtime: historyRuntime,
              conversation: TestConversationPort(),
              history: history,
            ),
            key: const ConversationKey.thread(
              providerId: 'provider',
              threadId: 'thread-1',
            ),
            context: const AgentContext(),
          ),
          _failure(AgentConversationFailureCode.historyReadFailed),
        );
        await repository.close();
        await runtime.eventController.close();
        await failedRuntime.eventController.close();
        await sourceRuntime.eventController.close();
        await historyRuntime.eventController.close();
      },
    );

    test(
      'operation preconditions and provider exceptions stay isolated',
      () async {
        final runtime = TestRuntime('provider');
        final conversation = TestConversationPort();
        final repository = AgentConversationRepository(
          turnContextStore: TestTurnContextStore(),
          logger: loggerFor('operation-failure-test'),
        );
        await repository.openConversation(
          bundle: testBundle(runtime: runtime, conversation: conversation),
          key: draftKey,
          context: const AgentContext(),
        );
        await expectLater(
          repository.cancel(draftKey),
          _failure(AgentConversationFailureCode.noActiveTurn),
        );
        await expectLater(
          repository.steer(key: draftKey, request: const SteerRequest()),
          _failure(AgentConversationFailureCode.operationUnsupported),
        );
        await expectLater(
          repository.respondToPermission(
            draftKey,
            AgentPermissionDecision(requestId: 'missing', approved: true),
          ),
          _failure(AgentConversationFailureCode.pendingRequestNotFound),
        );
        await repository.submit(
          key: draftKey,
          request: const TurnRequest(message: 'active'),
        );
        runtime.eventController.add(
          AgentPermissionRequestedEvent(
            AgentPermissionRequest(
              id: 'unsupported',
              title: 'Permission',
              kind: AgentPermissionKind.other,
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          ),
        );
        await _pump();
        await expectLater(
          repository.respondToPermission(
            draftKey,
            AgentPermissionDecision(requestId: 'unsupported', approved: true),
          ),
          _failure(AgentConversationFailureCode.operationUnsupported),
        );
        conversation.sendError = Exception('send');
        await expectLater(
          repository.submit(
            key: draftKey,
            request: const TurnRequest(message: 'fail'),
          ),
          _failure(AgentConversationFailureCode.providerOperationFailed),
        );
        await repository.closeConversation(draftKey);
        await repository.closeConversation(draftKey);
        expect(
          () => repository.snapshots(draftKey),
          throwsA(
            isA<AgentConversationRepositoryException>().having(
              (error) => error.failure.code,
              'code',
              AgentConversationFailureCode.conversationNotOpen,
            ),
          ),
        );
        expect(
          () => repository.snapshotOf(draftKey),
          returnsNormally,
        );
        await repository.close();
        await expectLater(
          repository.openConversation(
            bundle: testBundle(runtime: runtime, conversation: conversation),
            key: draftKey,
            context: const AgentContext(),
          ),
          _failure(AgentConversationFailureCode.repositoryClosed),
        );
        expect(
          () => repository.snapshots(draftKey),
          throwsA(
            isA<AgentConversationRepositoryException>().having(
              (error) => error.failure.code,
              'code',
              AgentConversationFailureCode.repositoryClosed,
            ),
          ),
        );
        await runtime.eventController.close();
      },
    );

    test('supported steering still requires an active turn', () async {
      final runtime = TestRuntime('provider');
      final repository = AgentConversationRepository(
        turnContextStore: TestTurnContextStore(),
        logger: loggerFor('steer-precondition-test'),
      );
      await repository.openConversation(
        bundle: testBundle(
          runtime: runtime,
          conversation: TestConversationPort(),
          ports: TestResponsePorts(),
        ),
        key: draftKey,
        context: const AgentContext(),
      );
      await expectLater(
        repository.steer(key: draftKey, request: const SteerRequest()),
        _failure(AgentConversationFailureCode.noActiveTurn),
      );
      await repository.close();
      await runtime.eventController.close();
    });

    test('close wins an in-flight open and queued operation', () async {
      final runtime = TestRuntime('provider')
        ..initializeBarrier = Completer<void>();
      final repository = AgentConversationRepository(
        turnContextStore: TestTurnContextStore(),
        logger: loggerFor('close-race-test'),
      );
      final opening = repository.openConversation(
        bundle: testBundle(
          runtime: runtime,
          conversation: TestConversationPort(),
        ),
        key: draftKey,
        context: const AgentContext(),
      );
      final closing = repository.close();
      runtime.initializeBarrier!.complete();
      await expectLater(
        opening,
        _failure(AgentConversationFailureCode.repositoryClosed),
      );
      await closing;
      await runtime.eventController.close();

      final queuedRuntime = TestRuntime('provider');
      final queuedRepository = AgentConversationRepository(
        turnContextStore: TestTurnContextStore(),
        logger: loggerFor('queued-operation-test'),
      );
      await queuedRepository.openConversation(
        bundle: testBundle(
          runtime: queuedRuntime,
          conversation: TestConversationPort(),
        ),
        key: draftKey,
        context: const AgentContext(),
      );
      final cancellation = queuedRepository.cancel(draftKey);
      final cancellationExpectation = expectLater(
        cancellation,
        _failure(AgentConversationFailureCode.conversationNotOpen),
      );
      await queuedRepository.closeConversation(draftKey);
      await cancellationExpectation;
      await queuedRepository.close();
      await queuedRuntime.eventController.close();
    });

    test('thread open uses the empty default replay input source', () async {
      final runtime = TestRuntime('provider');
      final repository = AgentConversationRepository(
        turnContextStore: TestTurnContextStore(),
        logger: loggerFor('default-history-test'),
      );
      const key = ConversationKey.thread(
        providerId: 'provider',
        threadId: 'thread-1',
      );
      final handle = await repository.openConversation(
        bundle: testBundle(
          runtime: runtime,
          conversation: TestConversationPort(),
        ),
        key: key,
        context: const AgentContext(),
      );
      expect(repository.snapshotOf(key)?.turns, isEmpty);
      await handle.release();
      await repository.close();
      await runtime.eventController.close();
    });

    test(
      'provider-returned session and turn identities are revalidated',
      () async {
        final startRuntime = TestRuntime('provider');
        final startConversation = TestConversationPort()
          ..session = AgentSession(id: 'thread-1', providerId: 'other');
        final startRepository = AgentConversationRepository(
          turnContextStore: TestTurnContextStore(),
          logger: loggerFor('start-identity-test'),
        );
        await startRepository.openConversation(
          bundle: testBundle(
            runtime: startRuntime,
            conversation: startConversation,
          ),
          key: draftKey,
          context: const AgentContext(),
        );
        await expectLater(
          startRepository.submit(
            key: draftKey,
            request: const TurnRequest(message: 'message'),
          ),
          _failure(AgentConversationFailureCode.invalidIdentity),
        );
        await startRepository.close();
        await startRuntime.eventController.close();

        final turnRuntime = TestRuntime('provider');
        final turnConversation = TestConversationPort()
          ..turn = AgentTurn(id: 'turn', sessionId: 'other-thread');
        final turnRepository = AgentConversationRepository(
          turnContextStore: TestTurnContextStore(),
          logger: loggerFor('turn-identity-test'),
        );
        await turnRepository.openConversation(
          bundle: testBundle(
            runtime: turnRuntime,
            conversation: turnConversation,
          ),
          key: draftKey,
          context: const AgentContext(),
        );
        await expectLater(
          turnRepository.submit(
            key: draftKey,
            request: const TurnRequest(message: 'message'),
          ),
          _failure(AgentConversationFailureCode.invalidIdentity),
        );
        await turnRepository.close();
        await turnRuntime.eventController.close();

        final resumeRuntime = TestRuntime('provider');
        final resumeConversation = TestConversationPort()
          ..session = AgentSession(id: 'wrong-thread', providerId: 'provider');
        final resumeRepository = AgentConversationRepository(
          turnContextStore: TestTurnContextStore(),
          logger: loggerFor('resume-identity-test'),
        );
        await expectLater(
          resumeRepository.openConversation(
            bundle: testBundle(
              runtime: resumeRuntime,
              conversation: resumeConversation,
            ),
            key: const ConversationKey.thread(
              providerId: 'provider',
              threadId: 'thread-1',
            ),
            context: const AgentContext(),
          ),
          _failure(AgentConversationFailureCode.invalidIdentity),
        );
        await resumeRepository.close();
        await resumeRuntime.eventController.close();
      },
    );
  });
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Matcher _failure(AgentConversationFailureCode code) => throwsA(
  isA<AgentConversationRepositoryException>().having(
    (error) => error.failure.code,
    'code',
    code,
  ),
);
