import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('ClaudeCodeAgentProvider', () {
    test('hello turn maps init/text/result and usage', () async {
      final process = _FakeClaudeProcess();
      var idSeq = 0;
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode,
        processStarter: _starter(process),
        locator: const _FakeClaudeCodeCliLocator(),
        idFactory: () {
          idSeq += 1;
          return idSeq == 1
              ? '00000000-0000-4000-8000-000000000001'
              : 'turn-hello-1';
        },
      );
      addTearDown(provider.dispose);

      final events = <AgentEvent>[];
      provider.events.listen(events.add);

      await provider.initialize();
      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
      );
      expect(session.id, '00000000-0000-4000-8000-000000000001');

      // Process start should have been observed.
      await pumpEventQueue();
      process.emitInit(sessionId: session.id);
      await pumpEventQueue();

      final turn = await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        message: 'ping',
      );
      expect(turn.id, 'turn-hello-1');

      await pumpEventQueue();
      expect(process.receivedUserTexts, <String>['ping']);
      final userFrame = process.receivedUserFrames.single;
      expect(userFrame['session_id'], session.id);
      expect(userFrame.containsKey('parent_tool_use_id'), isTrue);
      expect(userFrame['parent_tool_use_id'], isNull);

      process.emitAssistantText(
        sessionId: session.id,
        messageId: 'msg_1',
        text: 'pong',
      );
      process.emitResultSuccess(sessionId: session.id);
      await pumpEventQueue(times: 5);

      expect(events.whereType<AgentSessionStartedEvent>(), isNotEmpty);
      expect(events.whereType<AgentTurnStartedEvent>(), hasLength(1));
      expect(events.whereType<AgentMessageUpdatedEvent>(), hasLength(1));
      final usage = events.whereType<AgentTokenUsageEvent>().single;
      expect(usage.isSessionCumulative, isFalse);
      expect(usage.turnId, 'turn-hello-1');
      final completed = events.whereType<AgentTurnCompletedEvent>().single;
      expect(completed.status, AgentHistoryTurnStatus.completed);
      expect(completed.turnId, 'turn-hello-1');
      expect(completed.completedAt, isNotNull);
    });

    test(
      'emits turn started context from the current model selection',
      () async {
        final process = _FakeClaudeProcess();
        var idSeq = 0;
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode.copyWith(
            selectedModel: 'opus',
            selectedReasoningEffort: 'xhigh',
          ),
          processStarter: _starter(process),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: () {
            idSeq += 1;
            return idSeq == 1
                ? '00000000-0000-4000-8000-000000000101'
                : 'turn-context-1';
          },
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        provider.events.listen(events.add);

        await provider.initialize();
        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        await pumpEventQueue();
        process.emitInit(sessionId: session.id);
        await pumpEventQueue();
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'ping',
        );

        final started = events.whereType<AgentTurnStartedEvent>().single;
        expect(started.modelId, 'opus');
        expect(started.reasoningEffort, 'xhigh');
        expect(started.startedAt, isNotNull);
      },
    );

    test(
      'compactThread sends /compact and allows the following turn',
      () async {
        final process = _FakeClaudeProcess();
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _starter(process),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: _sequenceIds(<String>[
            '00000000-0000-4000-8000-000000000031',
            'turn-compact-1',
            'turn-after-compact-1',
          ]),
        );
        addTearDown(provider.dispose);

        final events = <AgentEvent>[];
        provider.events.listen(events.add);
        final session = await provider.startSession(
          context: const AgentContext(projectPath: '/tmp/zeta-cc-compact'),
        );

        await expectLater(
          provider.compactThread('another-session'),
          throwsStateError,
        );
        expect(process.receivedUserFrames, isEmpty);

        final compactOperation = provider.compactThread(session.id);
        await pumpEventQueue(times: 3);

        expect(process.receivedUserTexts, <String>['/compact']);
        final userFrame = process.receivedUserFrames.single;
        expect(userFrame['session_id'], session.id);
        expect(userFrame['message'], <String, Object?>{
          'role': 'user',
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': '/compact'},
          ],
        });
        expect(events.whereType<AgentTurnStartedEvent>(), hasLength(1));

        process.emitResultSuccess(sessionId: session.id);
        await compactOperation;

        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: '/tmp/zeta-cc-compact'),
          message: 'after compact',
        );
        await pumpEventQueue();
        expect(process.receivedUserTexts, <String>[
          '/compact',
          'after compact',
        ]);
        process.emitResultSuccess(sessionId: session.id);
        await pumpEventQueue();
      },
    );

    test(
      'can_use_tool emits permission event then control_response on decide',
      () async {
        final process = _FakeClaudeProcess();
        var idSeq = 0;
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _starter(process),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: () {
            idSeq += 1;
            return idSeq == 1 ? 'session-perm-1' : 'turn-perm-1';
          },
        );
        addTearDown(provider.dispose);

        final events = <AgentEvent>[];
        provider.events.listen(events.add);

        await provider.initialize();
        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        await pumpEventQueue();
        process.emitInit(sessionId: session.id);
        await pumpEventQueue();

        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'run tool',
        );
        await pumpEventQueue();

        process.emitControlRequest(requestId: 'req_1', toolName: 'Bash');
        await pumpEventQueue(times: 3);

        // 不立即 deny；等待用户决策。
        expect(provider.controlDeniedCount, 0);
        expect(provider.controlPendingCount, 1);
        expect(process.receivedControlResponses, isEmpty);
        final permission = events
            .whereType<AgentPermissionRequestedEvent>()
            .single;
        expect(permission.request.id, 'req_1');
        expect(permission.request.sessionId, 'session-perm-1');
        expect(permission.request.turnId, 'turn-perm-1');

        // Plan decision 端口不得看见或消费普通权限 pending。
        await provider.respondToPlanApproval(
          const AgentPlanApprovalDecision(
            requestId: 'req_1',
            kind: AgentPlanApprovalDecisionKind.accepted,
          ),
        );
        await pumpEventQueue();
        expect(provider.controlPendingCount, 1);
        expect(provider.planApprovalPendingCount, 0);
        expect(process.receivedControlResponses, isEmpty);

        await provider.respondToPermission(
          const AgentPermissionDecision(
            requestId: 'req_1',
            approved: true,
            commandDecision: AgentCommandApprovalDecisionKind.accept,
          ),
        );
        await pumpEventQueue(times: 3);

        expect(provider.controlPendingCount, 0);
        expect(process.receivedControlResponses, hasLength(1));
        final response = process.receivedControlResponses.single;
        expect(response['type'], 'control_response');
        final envelope = response['response'] as Map<String, Object?>;
        expect(envelope['subtype'], 'success');
        expect(envelope['request_id'], 'req_1');
        final body = envelope['response'] as Map<String, Object?>;
        expect(body['behavior'], 'allow');
        expect(body['updatedInput'], isA<Map>());
      },
    );

    test(
      'AskUserQuestion emits question options and accepts structured answers',
      () async {
        final process = _FakeClaudeProcess();
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _starter(process),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: _sequenceIds(<String>[
            'session-question-1',
            'turn-question-1',
          ]),
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        provider.events.listen(events.add);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        process.emitInit(sessionId: session.id);
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'ask a question',
        );
        process.emitControlRequest(
          requestId: 'req-question-1',
          toolName: 'AskUserQuestion',
          input: <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'question': 'Choose a repair direction',
                'header': 'Repair',
                'multiSelect': false,
                'options': <Object?>[
                  <String, Object?>{
                    'label': 'Static fallback',
                    'description': 'Use a versioned table',
                  },
                  <String, Object?>{
                    'label': 'Keep hidden',
                    'description': 'Explain the missing value',
                  },
                  <String, Object?>{
                    'label': 'No change',
                    'description': 'Only report the cause',
                  },
                ],
              },
            ],
          },
        );
        await pumpEventQueue(times: 5);

        expect(events.whereType<AgentPermissionRequestedEvent>(), isEmpty);
        final questionEvent = events
            .whereType<AgentQuestionRequestedEvent>()
            .single;
        expect(questionEvent.request.sessionId, 'session-question-1');
        expect(questionEvent.request.turnId, 'turn-question-1');
        expect(
          questionEvent.request.questions.single.optionItems.map(
            (option) => option.label,
          ),
          <String>['Static fallback', 'Keep hidden', 'No change'],
        );
        expect(provider.controlPendingCount, 0);
        expect(provider.questionPendingCount, 1);
        expect(process.receivedControlResponses, isEmpty);

        await provider.respondToQuestion(
          const AgentQuestionResponse(
            requestId: 'req-question-1',
            answers: <String, List<String>>{
              'Choose a repair direction': <String>['Static fallback'],
            },
          ),
        );
        await pumpEventQueue(times: 3);

        expect(provider.questionPendingCount, 0);
        final response = process.receivedControlResponses.single;
        final envelope = response['response'] as Map<String, Object?>;
        expect(envelope['request_id'], 'req-question-1');
        final body = envelope['response'] as Map<String, Object?>;
        expect(body['behavior'], 'allow');
        final updatedInput = body['updatedInput'] as Map<String, Object?>;
        expect(updatedInput['answers'], <String, String>{
          'Choose a repair direction': 'Static fallback',
        });
        expect(
          events.whereType<AgentQuestionResolvedEvent>().single.requestId,
          'req-question-1',
        );
      },
    );

    test(
      'ExitPlanMode uses the isolated plan approval route and response id',
      () async {
        final process = _FakeClaudeProcess();
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _starter(process),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: _sequenceIds(<String>['session-plan-1', 'turn-plan-1']),
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        provider.events.listen(events.add);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'create a plan',
        );
        process.emitAssistantText(
          sessionId: session.id,
          messageId: 'msg-plan-1',
          text: 'Fallback plan',
        );
        process.emitExitPlanToolUse(
          sessionId: session.id,
          toolUseId: 'toolu-plan-1',
          input: <String, Object?>{'plan': 'Verified plan'},
        );
        process.emitControlRequest(
          requestId: 'req-plan-1',
          toolUseId: 'toolu-plan-1',
          toolName: 'ExitPlanMode',
          input: <String, Object?>{'plan': 'Verified plan'},
        );
        await pumpEventQueue(times: 5);

        expect(events.whereType<AgentToolCallEvent>(), isEmpty);
        expect(events.whereType<AgentPermissionRequestedEvent>(), isEmpty);
        final approval = events
            .whereType<AgentPlanApprovalRequestedEvent>()
            .single
            .request;
        expect(approval.id, 'toolu-plan-1');
        expect(approval.markdown, 'Verified plan');
        expect(approval.sessionId, 'session-plan-1');
        expect(approval.turnId, 'turn-plan-1');
        expect(provider.controlPendingCount, 0);
        expect(provider.planApprovalPendingCount, 1);

        // Permission decision 端口不得看见或消费 Plan pending。
        await provider.respondToPermission(
          const AgentPermissionDecision(
            requestId: 'toolu-plan-1',
            approved: true,
          ),
        );
        await pumpEventQueue();
        expect(provider.controlPendingCount, 0);
        expect(provider.planApprovalPendingCount, 1);
        expect(process.receivedControlResponses, isEmpty);

        await provider.respondToPlanApproval(
          const AgentPlanApprovalDecision(
            requestId: 'toolu-plan-1',
            kind: AgentPlanApprovalDecisionKind.accepted,
          ),
        );
        await pumpEventQueue(times: 3);

        expect(provider.planApprovalPendingCount, 0);
        final response = process.receivedControlResponses.single;
        final envelope = response['response'] as Map<String, Object?>;
        expect(envelope['request_id'], 'req-plan-1');
        final body = envelope['response'] as Map<String, Object?>;
        expect(body['behavior'], 'allow');
        expect(body['updatedInput'], <String, Object?>{
          'plan': 'Verified plan',
        });
      },
    );

    test('unknown control_request type is still fail-closed denied', () async {
      final process = _FakeClaudeProcess();
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode,
        processStarter: _starter(process),
        locator: const _FakeClaudeCodeCliLocator(),
        idFactory: () => 'id-unknown-ctrl',
      );
      addTearDown(provider.dispose);

      final events = <AgentEvent>[];
      provider.events.listen(events.add);

      await provider.initialize();
      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
      );
      await pumpEventQueue();
      process.emitInit(sessionId: session.id);
      await pumpEventQueue();

      process.emitJson(<String, Object?>{
        'type': 'control_request',
        'request_id': 'req_x',
        'request': <String, Object?>{'type': 'not_a_tool'},
      });
      await pumpEventQueue(times: 3);

      expect(provider.controlDeniedCount, 1);
      expect(events.whereType<AgentPermissionRequestedEvent>(), isEmpty);
      expect(process.receivedControlResponses, hasLength(1));
      final envelope =
          process.receivedControlResponses.single['response']
              as Map<String, Object?>;
      expect(envelope['subtype'], 'error');
      expect(envelope['request_id'], 'req_x');
    });

    test(
      'idle permission switch restarts peer by resuming same session',
      () async {
        final firstProcess = _FakeClaudeProcess();
        final secondProcess = _FakeClaudeProcess();
        final starts = <_RecordedProcessStart>[];
        final processes = <_FakeClaudeProcess>[firstProcess, secondProcess];
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _queueStarter(processes, starts),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: () => 'session-switch-1',
        );
        addTearDown(provider.dispose);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        final result = await provider.permissionPolicy.applyPermissionSelection(
          const AgentPermissionSelection(optionId: ':plan'),
        );

        expect(result.scope, AgentPermissionApplyScope.currentSession);
        expect(starts, hasLength(2));
        expect(
          starts.first.arguments,
          containsAllInOrder(<String>[
            '--session-id',
            session.id,
            '--permission-mode',
            'default',
          ]),
        );
        expect(
          starts.last.arguments,
          containsAllInOrder(<String>[
            '--resume',
            session.id,
            '--permission-mode',
            'plan',
          ]),
        );
      },
    );

    test(
      'resume starts with requested session and rejects mismatched init',
      () async {
        final process = _FakeClaudeProcess();
        final starts = <_RecordedProcessStart>[];
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _queueStarter(<_FakeClaudeProcess>[process], starts),
          locator: const _FakeClaudeCodeCliLocator(),
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        provider.events.listen(events.add);

        final session = await provider.resumeSession(
          'resume-session-1',
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          permissionSnapshot: const AgentPermissionRequestSnapshot.resolved(
            selection: AgentPermissionSelection(optionId: ':plan'),
            source: AgentPermissionRequestSource.threadEffective,
          ),
        );

        expect(session.id, 'resume-session-1');
        expect(starts, hasLength(1));
        expect(
          starts.single.arguments,
          containsAllInOrder(<String>[
            '--resume',
            'resume-session-1',
            '--permission-mode',
            'plan',
          ]),
        );

        process.emitInit(sessionId: 'different-session');
        await pumpEventQueue(times: 3);

        expect(events.whereType<AgentSessionStartedEvent>(), isEmpty);
        final error = events.whereType<AgentErrorEvent>().single;
        expect(error.code, 'claudeCodeSessionMismatch');
        expect(error.sessionId, 'resume-session-1');
      },
    );

    test('thread catalog delegates to the Claude history reader', () async {
      final reader = _RecordingClaudeCodeSessionHistoryReader();
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode,
        sessionHistoryReader: reader,
      );
      addTearDown(provider.dispose);
      const query = AgentThreadListQuery(
        projectPath: '/workspace/project',
        limit: 7,
      );

      final page = await provider.listThreads(query: query);
      final history = await provider.readThreadHistory(
        threadId: 'history-thread-1',
        sessionPath: '/claude/history-thread-1.jsonl',
        projectPath: '/workspace/project',
      );

      expect(reader.listQuery, same(query));
      expect(page.threads.single.id, 'history-thread-1');
      expect(reader.readThreadId, 'history-thread-1');
      expect(reader.readProjectPath, '/workspace/project');
      expect(reader.readSessionPath, '/claude/history-thread-1.jsonl');
      expect(history.threadId, 'history-thread-1');
    });

    test(
      'listModels uses CLI metadata even when enrichment is disabled',
      () async {
        var metadataCalls = 0;
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode.copyWith(
            extra: const <String, Object?>{
              claudeCodeAccountDataEnrichmentKey: false,
            },
          ),
          metadataLoader: () async {
            metadataCalls += 1;
            return _metadataSnapshot('cli-default-$metadataCalls');
          },
        );
        addTearDown(provider.dispose);

        final first = await provider.listModels(limit: 1);
        final cached = await provider.listModels(limit: 1);

        expect(first.models.single.id, 'cli-default-1');
        expect(cached, same(first));
        expect(metadataCalls, 1);
      },
    );

    test(
      'implements refreshable catalog and forwards forced refresh',
      () async {
        var metadataCalls = 0;
        final catalog = ClaudeCodeModelCatalog(
          metadataLoader: () async {
            metadataCalls += 1;
            return _metadataSnapshot('cli-refresh-$metadataCalls');
          },
        );
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          modelCatalog: catalog,
        );
        addTearDown(provider.dispose);

        final first = await provider.listModels();
        final refreshed = await provider.listModels(forceRefresh: true);

        expect(first.models.single.id, 'cli-refresh-1');
        expect(refreshed.models.single.id, 'cli-refresh-2');
        expect(metadataCalls, 2);
      },
    );

    test('model and quota reads share one metadata probe', () async {
      final gate = Completer<ClaudeCodeCliMetadataSnapshot>();
      var metadataCalls = 0;
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode.copyWith(
          extra: const <String, Object?>{
            claudeCodeAccountDataEnrichmentKey: false,
          },
        ),
        metadataLoader: () {
          metadataCalls += 1;
          return gate.future;
        },
      );
      addTearDown(provider.dispose);

      final modelsFuture = provider.listModels();
      final quotaFuture = provider.readUsageQuota();
      await Future<void>.delayed(Duration.zero);
      expect(metadataCalls, 1);

      gate.complete(_metadataSnapshot('shared-model', subscriptionType: 'pro'));
      final models = await modelsFuture;
      final quota = await quotaFuture;

      expect(models.models.single.id, 'shared-model');
      expect(quota?.planType, 'Claude Pro');
      expect(quota?.windows, isEmpty);
      expect(metadataCalls, 1);
    });

    test('exposes usage quota through the neutral bundle port', () async {
      final adapter = ClaudeCodeUsageQuotaAdapter(
        providerId: defaultClaudeCodeProviderId,
        providerName: 'Claude Code',
        metadataLoader: () async =>
            _metadataSnapshot('quota-model', subscriptionType: 'max'),
        credentialsLoader: () async => ClaudeCodeOAuthCredentials(
          accessToken: 'sensitive-test-token',
          expiresAt: DateTime.utc(2099),
          subscriptionType: 'max',
          scopes: const <String>['user:inference', 'user:profile'],
        ),
        remoteUsageLoader:
            ({
              required String accessToken,
              required String? claudeCodeVersion,
            }) async => <String, Object?>{
              'five_hour': <String, Object?>{'utilization': 20},
            },
      );
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode,
        usageQuotaAdapter: adapter,
      );
      addTearDown(provider.dispose);

      final quotaPort = nativeBundleFromClaudeCode(provider).usageQuota;
      final quota = await quotaPort?.readUsageQuota();

      expect(quotaPort, same(provider));
      expect(quota?.providerId, defaultClaudeCodeProviderId);
      expect(quota?.planType, 'Claude Max');
      expect(quota?.windows.single.usedPercent, 20);
    });

    test('persisted model configuration is used for the first peer', () async {
      final process = _FakeClaudeProcess();
      final starts = <_RecordedProcessStart>[];
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode.copyWith(
          selectedModel: 'haiku',
          selectedReasoningEffort: 'high',
        ),
        processStarter: _queueStarter(<_FakeClaudeProcess>[process], starts),
        locator: const _FakeClaudeCodeCliLocator(),
        idFactory: () => 'session-initial-model-1',
      );
      addTearDown(provider.dispose);

      await provider.startSession(
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
      );

      expect(starts, hasLength(1));
      expect(
        starts.single.arguments,
        containsAllInOrder(<String>['--model', 'haiku', '--effort', 'high']),
      );
    });

    test(
      'idle reasoning effort switch resumes the same session before next turn',
      () async {
        final firstProcess = _FakeClaudeProcess();
        final secondProcess = _FakeClaudeProcess();
        final starts = <_RecordedProcessStart>[];
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _queueStarter(<_FakeClaudeProcess>[
            firstProcess,
            secondProcess,
          ], starts),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: _sequenceIds(<String>[
            'session-effort-switch-1',
            'turn-effort-switch-1',
          ]),
        );
        addTearDown(provider.dispose);
        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );

        provider.updateModelSelection(
          const AgentModelSelection(reasoningEffort: 'xhigh'),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'use selected effort',
        );

        expect(starts, hasLength(2));
        expect(starts.first.arguments, isNot(contains('--effort')));
        expect(
          starts.last.arguments,
          containsAllInOrder(<String>[
            '--resume',
            session.id,
            '--effort',
            'xhigh',
          ]),
        );
        expect(firstProcess.receivedUserTexts, isEmpty);
        expect(secondProcess.receivedUserTexts, <String>[
          'use selected effort',
        ]);
      },
    );

    test('clearing persisted reasoning effort restores CLI default', () async {
      final firstProcess = _FakeClaudeProcess();
      final secondProcess = _FakeClaudeProcess();
      final starts = <_RecordedProcessStart>[];
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode.copyWith(
          selectedReasoningEffort: 'high',
        ),
        processStarter: _queueStarter(<_FakeClaudeProcess>[
          firstProcess,
          secondProcess,
        ], starts),
        locator: const _FakeClaudeCodeCliLocator(),
        idFactory: _sequenceIds(<String>[
          'session-effort-clear-1',
          'turn-effort-clear-1',
        ]),
      );
      addTearDown(provider.dispose);
      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
      );

      provider.updateModelSelection(const AgentModelSelection());
      await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        message: 'use CLI default effort',
      );

      expect(starts, hasLength(2));
      expect(
        starts.first.arguments,
        containsAllInOrder(<String>['--effort', 'high']),
      );
      expect(starts.last.arguments, isNot(contains('--effort')));
      expect(secondProcess.receivedUserTexts, <String>[
        'use CLI default effort',
      ]);
    });

    test(
      'idle model switch resumes the same session before next turn',
      () async {
        final firstProcess = _FakeClaudeProcess();
        final secondProcess = _FakeClaudeProcess();
        final starts = <_RecordedProcessStart>[];
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _queueStarter(<_FakeClaudeProcess>[
            firstProcess,
            secondProcess,
          ], starts),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: _sequenceIds(<String>[
            'session-model-switch-1',
            'turn-model-switch-1',
          ]),
        );
        addTearDown(provider.dispose);
        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );

        provider.updateModelSelection(
          const AgentModelSelection(modelId: 'sonnet'),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'use selected model',
        );

        expect(starts, hasLength(2));
        expect(starts.first.arguments, isNot(contains('--model')));
        expect(
          starts.last.arguments,
          containsAllInOrder(<String>[
            '--resume',
            session.id,
            '--model',
            'sonnet',
          ]),
        );
        expect(firstProcess.receivedUserTexts, isEmpty);
        expect(secondProcess.receivedUserTexts, <String>['use selected model']);
      },
    );

    test(
      'model update during a turn only affects the following turn',
      () async {
        final firstProcess = _FakeClaudeProcess();
        final secondProcess = _FakeClaudeProcess();
        final starts = <_RecordedProcessStart>[];
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _queueStarter(<_FakeClaudeProcess>[
            firstProcess,
            secondProcess,
          ], starts),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: _sequenceIds(<String>[
            'session-running-model-1',
            'turn-running-model-1',
            'turn-running-model-2',
          ]),
        );
        addTearDown(provider.dispose);
        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        firstProcess.emitInit(sessionId: session.id);
        await pumpEventQueue(times: 3);
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'first turn',
        );

        provider.updateModelSelection(
          const AgentModelSelection(modelId: 'haiku'),
        );
        expect(starts, hasLength(1));
        expect(firstProcess.receivedUserTexts, <String>['first turn']);

        firstProcess.emitResultSuccess(sessionId: session.id);
        await pumpEventQueue(times: 5);
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'second turn',
        );

        expect(starts, hasLength(2));
        expect(
          starts.last.arguments,
          containsAllInOrder(<String>[
            '--resume',
            session.id,
            '--model',
            'haiku',
          ]),
        );
        expect(secondProcess.receivedUserTexts, <String>['second turn']);
      },
    );

    test(
      'turn permission snapshot resumes same session before sending user frame',
      () async {
        final planProcess = _FakeClaudeProcess();
        final executionProcess = _FakeClaudeProcess();
        final starts = <_RecordedProcessStart>[];
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _queueStarter(<_FakeClaudeProcess>[
            planProcess,
            executionProcess,
          ], starts),
          locator: const _FakeClaudeCodeCliLocator(),
          idFactory: _sequenceIds(<String>[
            'session-turn-permission-1',
            'turn-execution-1',
          ]),
        );
        addTearDown(provider.dispose);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          permissionSnapshot: const AgentPermissionRequestSnapshot.resolved(
            selection: AgentPermissionSelection(optionId: ':plan'),
            source: AgentPermissionRequestSource.threadEffective,
          ),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'execute approved plan',
          configuration: const AgentTurnConfiguration(
            permissionSnapshot: AgentPermissionRequestSnapshot.resolved(
              selection: AgentPermissionSelection(optionId: ':ask'),
              source: AgentPermissionRequestSource.localWorkflowOverride,
            ),
          ),
        );

        expect(starts, hasLength(2));
        expect(
          starts.first.arguments,
          containsAllInOrder(<String>[
            '--session-id',
            session.id,
            '--permission-mode',
            'plan',
          ]),
        );
        expect(
          starts.last.arguments,
          containsAllInOrder(<String>[
            '--resume',
            session.id,
            '--permission-mode',
            'default',
          ]),
        );
        expect(planProcess.receivedUserTexts, isEmpty);
        expect(executionProcess.receivedUserTexts, <String>[
          'execute approved plan',
        ]);
      },
    );

    test('turn permission switch rejects running and stale sessions', () async {
      final process = _FakeClaudeProcess();
      final starts = <_RecordedProcessStart>[];
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode,
        processStarter: _queueStarter(<_FakeClaudeProcess>[process], starts),
        locator: const _FakeClaudeCodeCliLocator(),
        idFactory: _sequenceIds(<String>[
          'session-turn-guard-1',
          'turn-running-1',
        ]),
      );
      addTearDown(provider.dispose);
      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        permissionSnapshot: const AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: ':plan'),
          source: AgentPermissionRequestSource.threadEffective,
        ),
      );
      await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        message: 'plan is still running',
      );
      const executionConfiguration = AgentTurnConfiguration(
        permissionSnapshot: AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: ':ask'),
          source: AgentPermissionRequestSource.localWorkflowOverride,
        ),
      );

      await expectLater(
        provider.sendMessage(
          session: const AgentSession(
            id: 'stale-session',
            providerId: defaultClaudeCodeProviderId,
          ),
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'must not switch stale session',
          configuration: executionConfiguration,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'must not switch running turn',
          configuration: executionConfiguration,
        ),
        throwsA(isA<StateError>()),
      );

      expect(starts, hasLength(1));
      expect(process.receivedUserTexts, <String>['plan is still running']);
    });

    test('permission switch is rejected while a turn is running', () async {
      final process = _FakeClaudeProcess();
      final starts = <_RecordedProcessStart>[];
      final provider = ClaudeCodeAgentProvider(
        config: AgentProviderConfig.defaultClaudeCode,
        processStarter: _queueStarter(<_FakeClaudeProcess>[process], starts),
        locator: const _FakeClaudeCodeCliLocator(),
        idFactory: _sequenceIds(<String>[
          'session-running-1',
          'turn-running-1',
        ]),
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
      );
      await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        message: 'still running',
      );

      await expectLater(
        provider.permissionPolicy.applyPermissionSelection(
          const AgentPermissionSelection(optionId: ':plan'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(starts, hasLength(1));
    });

    test(
      'allow always is persisted and auto-applied without another event',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'zeta-claude-provider-permission-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final cacheFile = File(
          '${directory.path}${Platform.pathSeparator}session.json',
        );
        final process = _FakeClaudeProcess();
        final provider = ClaudeCodeAgentProvider(
          config: AgentProviderConfig.defaultClaudeCode,
          processStarter: _starter(process),
          locator: const _FakeClaudeCodeCliLocator(),
          sessionDecisionStoreFactory: (_) =>
              FileClaudeCodeSessionDecisionStore(
                storage: AtomicTextFile(cacheFile),
              ),
          idFactory: _sequenceIds(<String>['session-cache-1', 'turn-cache-1']),
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        provider.events.listen(events.add);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'C:\tmp\zeta-cc-test'),
          message: 'run tools',
        );
        process.emitControlRequest(requestId: 'req_first', toolName: 'Bash');
        await pumpEventQueue(times: 3);
        await provider.respondToPermission(
          const AgentPermissionDecision(
            requestId: 'req_first',
            approved: true,
            commandDecision: AgentCommandApprovalDecisionKind.acceptForSession,
          ),
        );
        process.emitControlRequest(requestId: 'req_second', toolName: 'Bash');
        await pumpEventQueue(times: 5);

        expect(events.whereType<AgentPermissionRequestedEvent>(), hasLength(1));
        expect(provider.controlPendingCount, 0);
        expect(process.receivedControlResponses, hasLength(2));
        final lastEnvelope =
            process.receivedControlResponses.last['response']
                as Map<String, Object?>;
        expect(lastEnvelope['request_id'], 'req_second');
        final source = await cacheFile.readAsString();
        expect(source, contains('"toolName":"Bash"'));
        expect(source, contains('"decision":"allow"'));
        expect(source, isNot(contains('echo hi')));
        expect(source, isNot(contains('input')));
      },
    );

    test('source has no 尚未接入 failure branch', () {
      final source = File(
        'packages/zeta_agent_providers/lib/src/datasources/claude_code/'
        'claude_code_agent_provider.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('尚未接入')));
    });
  });
}

class _FakeClaudeCodeCliLocator extends ClaudeCodeCliLocator {
  const _FakeClaudeCodeCliLocator();

  @override
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) async {
    return const ResolvedCliCommand(
      displayPath: 'claude',
      executable: 'claude',
    );
  }

  @override
  Future<ResolvedCliCommand?> resolvePath(String path) =>
      locate(AgentProviderConfig.defaultClaudeCode);
}

final class _RecordingClaudeCodeSessionHistoryReader
    extends ClaudeCodeSessionHistoryReader {
  AgentThreadListQuery? listQuery;
  String? readThreadId;
  String? readProjectPath;
  String? readSessionPath;

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
    required String providerId,
    Map<String, String>? environment,
  }) async {
    listQuery = query;
    return AgentThreadPage(
      threads: <AgentThreadSummary>[
        AgentThreadSummary(
          id: 'history-thread-1',
          providerId: providerId,
          projectPath: query.projectPath!,
          preview: 'History thread',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
          status: AgentThreadRuntimeStatus.idle,
        ),
      ],
      nextCursor: null,
    );
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    required String providerId,
    required String projectPath,
    String? sessionPath,
    Map<String, String>? environment,
  }) async {
    readThreadId = threadId;
    readProjectPath = projectPath;
    readSessionPath = sessionPath;
    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: const <AgentHistoryTurn>[],
    );
  }
}

ProcessStarter _starter(_FakeClaudeProcess process) {
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    process.start();
    return process;
  };
}

ProcessStarter _queueStarter(
  List<_FakeClaudeProcess> processes,
  List<_RecordedProcessStart> starts,
) {
  var index = 0;
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (index >= processes.length) {
      throw StateError('No fake Claude process left');
    }
    starts.add(
      _RecordedProcessStart(
        executable: executable,
        arguments: List<String>.of(arguments),
        workingDirectory: workingDirectory,
      ),
    );
    final process = processes[index++];
    process.start();
    return process;
  };
}

String Function() _sequenceIds(List<String> ids) {
  var index = 0;
  return () {
    if (index >= ids.length) {
      throw StateError('No fake id left');
    }
    return ids[index++];
  };
}

ClaudeCodeCliMetadataSnapshot _metadataSnapshot(
  String id, {
  String? subscriptionType = 'Claude Pro',
}) {
  return ClaudeCodeCliMetadataSnapshot(
    models: AgentModelList(
      models: <AgentModelInfo>[
        AgentModelInfo(id: id, model: id, displayName: id, isDefault: true),
      ],
    ),
    subscriptionType: subscriptionType,
  );
}

final class _RecordedProcessStart {
  const _RecordedProcessStart({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class _FakeClaudeProcess implements Process {
  final StreamController<List<int>> _stdinBytes = StreamController<List<int>>();
  final StreamController<List<int>> _stdoutBytes =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrBytes =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();

  final List<String> receivedUserTexts = <String>[];
  final List<Map<String, Object?>> receivedUserFrames =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> receivedControlResponses =
      <Map<String, Object?>>[];

  late final IOSink _stdin = IOSink(_FakeStdinConsumer(_stdinBytes));

  void start() {
    _stdinBytes.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleInputLine, onDone: () => _completeExit(0));
  }

  @override
  int get pid => 99;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdoutBytes.stream;

  @override
  Stream<List<int>> get stderr => _stderrBytes.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _completeExit(0);
    return true;
  }

  void emitInit({required String sessionId}) {
    _writeStdout(<String, Object?>{
      'type': 'system',
      'subtype': 'init',
      'session_id': sessionId,
      'cwd': r'C:\tmp\zeta-cc-test',
      'model': 'claude-haiku-4-5-20251001',
      'permissionMode': 'default',
      'claude_code_version': '2.1.220',
      'uuid': 'uuid-init',
    });
  }

  void emitAssistantText({
    required String sessionId,
    required String messageId,
    required String text,
  }) {
    _writeStdout(<String, Object?>{
      'type': 'assistant',
      'session_id': sessionId,
      'uuid': 'uuid-asst-1',
      'message': <String, Object?>{
        'id': messageId,
        'role': 'assistant',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
      },
    });
  }

  void emitExitPlanToolUse({
    required String sessionId,
    required String toolUseId,
    Map<String, Object?> input = const <String, Object?>{},
  }) {
    _writeStdout(<String, Object?>{
      'type': 'assistant',
      'session_id': sessionId,
      'uuid': 'uuid-exit-plan',
      'message': <String, Object?>{
        'id': 'msg-exit-plan',
        'role': 'assistant',
        'content': <Object?>[
          <String, Object?>{
            'type': 'tool_use',
            'id': toolUseId,
            'name': 'ExitPlanMode',
            'input': input,
          },
        ],
      },
    });
  }

  void emitResultSuccess({required String sessionId}) {
    _writeStdout(<String, Object?>{
      'type': 'result',
      'subtype': 'success',
      'session_id': sessionId,
      'uuid': 'uuid-result-1',
      'is_error': false,
      'num_turns': 1,
      'stop_reason': 'end_turn',
      'duration_ms': 100,
      'result': 'pong',
      'usage': <String, Object?>{
        'input_tokens': 10,
        'output_tokens': 4,
        'cache_creation_input_tokens': 0,
        'cache_read_input_tokens': 0,
      },
    });
  }

  void emitControlRequest({
    required String requestId,
    required String toolName,
    String? toolUseId,
    Map<String, Object?>? input,
  }) {
    emitJson(<String, Object?>{
      'type': 'control_request',
      'request_id': requestId,
      'request': <String, Object?>{
        'subtype': 'can_use_tool',
        'tool_use_id': toolUseId ?? 'toolu_$requestId',
        'tool_name': toolName,
        'input': input ?? <String, Object?>{'command': 'echo hi'},
      },
    });
  }

  void emitJson(Map<String, Object?> message) {
    _writeStdout(message);
  }

  void _writeStdout(Map<String, Object?> message) {
    if (!_stdoutBytes.isClosed) {
      _stdoutBytes.add(utf8.encode('${jsonEncode(message)}\n'));
    }
  }

  void _handleInputLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      return;
    }
    final map = <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    if (map['type'] == 'user') {
      receivedUserFrames.add(map);
      final message = map['message'];
      if (message is Map) {
        final content = message['content'];
        if (content is List && content.isNotEmpty) {
          final first = content.first;
          if (first is Map && first['text'] is String) {
            receivedUserTexts.add(first['text'] as String);
          }
        }
      }
    }
    if (map['type'] == 'control_response') {
      receivedControlResponses.add(map);
    }
  }

  void _completeExit(int code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
    unawaited(_closeController(_stdoutBytes));
    unawaited(_closeController(_stderrBytes));
    unawaited(_closeController(_stdinBytes));
  }
}

class _FakeStdinConsumer implements StreamConsumer<List<int>> {
  const _FakeStdinConsumer(this._controller);

  final StreamController<List<int>> _controller;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return stream.listen(_controller.add).asFuture<void>();
  }

  @override
  Future<void> close() async {}
}

Future<void> _closeController(StreamController<List<int>> controller) async {
  if (!controller.isClosed) {
    await controller.close();
  }
}
