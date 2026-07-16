import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_acp_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_models_cli.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_session_history_reader.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_acp_notification_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

import '../../../../../testing/fixture_reader.dart';

void main() {
  group('GrokAcpAgentProvider', () {
    test('initializes, authenticates, and starts ACP sessions', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );

      expect(session.id, 'sess-1');
      expect(
        peer.requestMethods,
        containsAll(<String>['initialize', 'authenticate', 'session/new']),
      );
      final initParams = peer.requestParams.first! as Map<String, Object?>;
      expect(initParams['protocolVersion'], 1);
      final caps = initParams['clientCapabilities']! as Map<String, Object?>;
      expect(caps['terminal'], isFalse);

      final models = await provider.listModels();
      expect(models.models, hasLength(2));
      expect(models.models.first.contextWindowTokens, 500000);
      expect(models.models.last.contextWindowTokens, 200000);
      expect(provider.lifecycleState, AgentProviderLifecycleState.ready);

      await provider.dispose();
      expect(provider.lifecycleState, AgentProviderLifecycleState.closed);
    });

    test(
      'fails explicitly for unsupported thread lifecycle operations',
      () async {
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: _FakeJsonRpcPeer(),
        );
        addTearDown(provider.dispose);

        await expectLater(
          provider.renameThread(threadId: 'session-1', name: 'New name'),
          throwsA(isA<UnsupportedError>()),
        );
        await expectLater(
          provider.archiveThread('session-1'),
          throwsA(isA<UnsupportedError>()),
        );
        await expectLater(
          provider.forkThread(
            threadId: 'session-1',
            context: const AgentContext(projectPath: '/repo'),
          ),
          throwsA(isA<UnsupportedError>()),
        );
        expect(provider.capabilities.canRenameThread, isFalse);
        expect(provider.capabilities.canForkThread, isFalse);
      },
    );

    test(
      'enriches restored Grok history with initialize model context window',
      () async {
        final sessionDir = await Directory.systemTemp.createTemp(
          'zeta-grok-context-history-',
        );
        addTearDown(() async {
          if (await sessionDir.exists()) {
            await sessionDir.delete(recursive: true);
          }
        });
        await File(
          '${sessionDir.path}${Platform.pathSeparator}updates.jsonl',
        ).writeAsString(r'''
{"method":"session/update","params":{"sessionId":"sess-context","update":{"sessionUpdate":"session_info_update","modelId":"grok-4.5"}}}
{"method":"session/update","params":{"sessionId":"sess-context","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"hello"}},"_meta":{"eventId":"u1"}}}
{"method":"_x.ai/session/update","params":{"sessionId":"sess-context","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"inputTokens":393000,"cachedReadTokens":350000,"outputTokens":10400,"totalTokens":403400}},"_meta":{"eventId":"done"}}}
''');

        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: _FakeJsonRpcPeer(),
        );
        addTearDown(provider.dispose);

        final history = await provider.readThreadHistory(
          threadId: 'sess-context',
          sessionPath: sessionDir.path,
        );

        expect(history.turns.single.model, 'grok-4.5');
        expect(history.turns.single.modelContextWindow, 500000);
        expect(history.turns.single.tokenUsage?.modelContextWindow, 500000);
        expect(history.turns.single.tokenUsage?.totalTokens, 403400);
      },
    );

    test('ignores a late model list after provider disposal', () async {
      final peer = _FakeJsonRpcPeer()..includeModelState = false;
      final modelsCompleter = Completer<AgentModelList>();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
        modelsCli: _DelayedModelsCli(modelsCompleter.future),
      );

      await provider.initialize();
      final listFuture = provider.listModels();
      await Future<void>.delayed(Duration.zero);
      await provider.dispose();
      modelsCompleter.complete(
        const AgentModelList(
          models: <AgentModelInfo>[
            AgentModelInfo(
              id: 'grok-4.5',
              model: 'grok-4.5',
              displayName: 'Grok 4.5',
            ),
          ],
        ),
      );

      final models = await listFuture;
      expect(models.models.single.id, 'grok-4.5');
    });

    test(
      'polls summary.json after turn complete and emits name updated',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'zeta-grok-title-',
        );
        addTearDown(() async {
          if (await tempRoot.exists()) {
            await tempRoot.delete(recursive: true);
          }
        });

        const projectPath = r'D:\repo\zeta';
        final encoded = Uri.encodeComponent(projectPath.replaceAll('/', '\\'));
        const sessionId = 'sess-1';
        final sessionDir = Directory(
          '${tempRoot.path}${Platform.pathSeparator}sessions'
          '${Platform.pathSeparator}$encoded'
          '${Platform.pathSeparator}$sessionId',
        );
        await sessionDir.create(recursive: true);
        final summary = File(
          '${sessionDir.path}${Platform.pathSeparator}summary.json',
        );

        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
          sessionHistoryReader: GrokSessionHistoryReader(
            grokHome: tempRoot.path,
          ),
          generatedTitlePollDelays: const <Duration>[
            Duration.zero,
            Duration(milliseconds: 20),
            Duration(milliseconds: 20),
          ],
        );
        addTearDown(provider.dispose);

        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: projectPath),
        );
        expect(session.id, sessionId);

        // turn 完成后 summary 尚无 generated_title；稍后异步写入（与真实 Grok 一致）。
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 15), () async {
            await summary.writeAsString('''
{
  "info": {"id": "$sessionId", "cwd": ${jsonEncode(projectPath)}},
  "session_summary": "User Asking What AI Model This Is",
  "generated_title": "User Asking What AI Model This Is"
}
''');
          }),
        );

        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: projectPath),
          message: '你是什么模型？',
        );

        await _waitUntil(
          () => events.whereType<AgentThreadNameUpdatedEvent>().isNotEmpty,
        );

        final nameEvents = events.whereType<AgentThreadNameUpdatedEvent>();
        expect(nameEvents, isNotEmpty);
        expect(nameEvents.last.threadName, 'User Asking What AI Model This Is');
      },
    );

    test(
      'resolves generated_title from slash-encoded macOS session paths',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'zeta-grok-title-mac-',
        );
        addTearDown(() async {
          if (await tempRoot.exists()) {
            await tempRoot.delete(recursive: true);
          }
        });

        // 与 ~/.grok/sessions/%2FUsers%2F... 一致：按 / 编码，而非旧逻辑的 \。
        const projectPath = '/Users/linpeilie/Development/Workspace/zeta';
        final encoded = Uri.encodeComponent(projectPath);
        expect(encoded.startsWith('%2F'), isTrue);
        const sessionId = 'sess-1';
        final sessionDir = Directory(
          '${tempRoot.path}${Platform.pathSeparator}sessions'
          '${Platform.pathSeparator}$encoded'
          '${Platform.pathSeparator}$sessionId',
        );
        await sessionDir.create(recursive: true);
        await File(
          '${sessionDir.path}${Platform.pathSeparator}summary.json',
        ).writeAsString('''
{
  "info": {"id": "$sessionId", "cwd": ${jsonEncode(projectPath)}},
  "generated_title": "User Asking What AI Model This Is"
}
''');

        final peer = _FakeJsonRpcPeer();
        // Fake peer 固定返回 sess-1；cwd 用 mac 路径。
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
          sessionHistoryReader: GrokSessionHistoryReader(
            grokHome: tempRoot.path,
          ),
          generatedTitlePollDelays: const <Duration>[Duration.zero],
        );
        addTearDown(provider.dispose);

        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: projectPath),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: projectPath),
          message: '你是什么模型',
        );
        await _waitUntil(
          () => events.whereType<AgentThreadNameUpdatedEvent>().isNotEmpty,
        );

        expect(
          events.whereType<AgentThreadNameUpdatedEvent>().single.threadName,
          'User Asking What AI Model This Is',
        );
      },
    );

    test('maps session/update chunks and tool calls to AgentEvents', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification('session/update', <String, Object?>{
        'sessionId': 'sess-1',
        'update': <String, Object?>{
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'msg-1',
          'content': <String, Object?>{'type': 'text', 'text': 'Hello Grok'},
        },
      });
      peer.emitNotification('session/update', <String, Object?>{
        'sessionId': 'sess-1',
        'update': <String, Object?>{
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-1',
          'title': 'Read file',
          'kind': 'read',
          'status': 'completed',
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        events.whereType<AgentMessageDeltaEvent>().single.delta,
        'Hello Grok',
      );
      expect(
        events.whereType<AgentToolCallEvent>().single.toolCall.id,
        'call-1',
      );
      expect(
        events.whereType<AgentToolCallEvent>().single.toolCall.kind,
        AgentToolKind.read,
      );

      await subscription.cancel();
      await provider.dispose();
    });

    test('sends session/prompt and completes turn', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );
      final turn = await provider.sendMessage(
        session: session,
        message: 'ping',
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );

      expect(turn.sessionId, session.id);
      expect(peer.requestMethods, contains('session/prompt'));
      final promptParams =
          peer.requestParams[peer.requestMethods.indexOf('session/prompt')]!
              as Map<String, Object?>;
      final prompt = promptParams['prompt']! as List<Object?>;
      expect(prompt.first, containsPair('text', 'ping'));

      await provider.dispose();
    });

    test('sends session/cancel and cancels pending permissions', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitServerRequest(
        id: 77,
        method: 'session/request_permission',
        params: <String, Object?>{
          'sessionId': 'sess-1',
          'toolCall': <String, Object?>{
            'toolCallId': 'call-cancel',
            'title': 'Run baseline fixture',
          },
          'options': <Object?>[
            <String, Object?>{
              'optionId': 'allow-once',
              'name': 'Allow once',
              'kind': 'allow_once',
            },
          ],
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<AgentPermissionRequestedEvent>(), isNotEmpty);

      await provider.cancelTurn(
        const AgentTurn(id: 'turn-1', sessionId: 'sess-1'),
      );

      expect(peer.notificationsSent, contains('session/cancel'));
      expect(peer.responses, isNotEmpty);
      final cancelled = peer.responses.last['result']! as Map<String, Object?>;
      final outcome = cancelled['outcome']! as Map<String, Object?>;
      expect(outcome['outcome'], 'cancelled');

      await subscription.cancel();
      await provider.dispose();
    });

    test('suppresses session/load replay updates from live timeline', () async {
      final peer = _FakeJsonRpcPeer()..loadSessionEmitsReplay = true;
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.resumeSession(
        'sess-replay',
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<AgentMessageDeltaEvent>(), isEmpty);
      expect(events.whereType<AgentSessionStartedEvent>(), isNotEmpty);
      expect(peer.requestMethods, contains('session/load'));

      await subscription.cancel();
      await provider.dispose();
    });

    test('rejects resume when session/load is unsupported', () async {
      // Arrange
      final peer = _FakeJsonRpcPeer()..supportsLoadSession = false;
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      await provider.initialize();

      // Act / Assert
      await expectLater(
        provider.resumeSession(
          'sess-existing',
          context: const AgentContext(projectPath: '/repo'),
        ),
        throwsUnsupportedError,
      );
      expect(peer.requestMethods, isNot(contains('session/load')));

      await provider.dispose();
    });

    test('responds to session/request_permission', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitServerRequest(
        id: 42,
        method: 'session/request_permission',
        params: <String, Object?>{
          'sessionId': 'sess-1',
          'toolCall': <String, Object?>{
            'toolCallId': 'call-1',
            'title': 'Run tests',
          },
          'options': <Object?>[
            <String, Object?>{
              'optionId': 'allow-once',
              'name': 'Allow once',
              'kind': 'allow_once',
            },
            <String, Object?>{
              'optionId': 'reject-once',
              'name': 'Reject',
              'kind': 'reject_once',
            },
          ],
        },
      );
      await Future<void>.delayed(Duration.zero);

      final request = events.whereType<AgentPermissionRequestedEvent>().single;
      expect(request.request.title, 'Run tests');

      await provider.respondToPermission(
        AgentPermissionDecision(requestId: request.request.id, approved: true),
      );
      expect(peer.responses, isNotEmpty);
      final response = peer.responses.single;
      expect(response['id'], 42);
      final result = response['result']! as Map<String, Object?>;
      final outcome = result['outcome']! as Map<String, Object?>;
      expect(outcome['optionId'], 'allow-once');

      await subscription.cancel();
      await provider.dispose();
    });
  });

  group('GrokAcpNotificationMapper', () {
    const mapper = GrokAcpNotificationMapper();

    test('maps agent_thought_chunk to reasoning delta', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 's1',
          'update': <String, Object?>{
            'sessionUpdate': 'agent_thought_chunk',
            'content': <String, Object?>{'type': 'text', 'text': 'thinking'},
          },
        },
        runningTurnId: 't1',
      );
      final event = mapped.events.single as AgentReasoningDeltaEvent;
      expect(event.delta, 'thinking');
      expect(event.sessionId, 's1');
      expect(event.turnId, 't1');
    });

    test('ignores live user_message_chunk to avoid duplicate bubbles', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 's1',
          'update': <String, Object?>{
            'sessionUpdate': 'user_message_chunk',
            'content': <String, Object?>{
              'type': 'text',
              'text': 'review 未提交的代码',
            },
          },
        },
        runningTurnId: 't1',
      );
      expect(mapped.events, isEmpty);
      expect(mapped.unmatchedKind, 'user_message_chunk');
    });

    test('maps PascalCase tool status Completed to completed', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 's1',
          'update': <String, Object?>{
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'call-1',
            'title': 'Read file',
            'kind': 'Read',
            'status': 'Completed',
          },
        },
        runningTurnId: 't1',
      );
      final tool = (mapped.events.single as AgentToolCallEvent).toolCall;
      expect(tool.status, AgentToolStatus.completed);
      expect(tool.kind, AgentToolKind.read);
    });

    test('maps session/update turn_completed', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 's1',
          'update': <String, Object?>{
            'sessionUpdate': 'turn_completed',
            'stopReason': 'end_turn',
          },
        },
        runningTurnId: 't1',
      );
      final event = mapped.events.single as AgentTurnCompletedEvent;
      expect(event.sessionId, 's1');
      expect(event.turnId, 't1');
      expect(event.status, AgentHistoryTurnStatus.completed);
    });

    test('maps turn_completed usage as turn-absolute with apiDurationMs', () {
      final mapped = mapper.mapXaiSessionUpdate(
        params: readFixtureJsonMap(
          'grok/acp/xai_turn_completed_notification_redacted.json',
        ),
        runningTurnId: 'local-turn-1',
      );
      expect(mapped.events, hasLength(2));
      final usage = mapped.events[0] as AgentTokenUsageEvent;
      expect(usage.turnId, 'local-turn-1');
      expect(usage.isSessionCumulative, isFalse);
      expect(usage.tokenUsage.totalTokens, 120);
      expect(usage.tokenUsage.inputTokens, 100);
      expect(usage.tokenUsage.cachedInputTokens, 40);
      final completed = mapped.events[1] as AgentTurnCompletedEvent;
      expect(completed.turnId, 'local-turn-1');
      expect(completed.duration, const Duration(milliseconds: 4500));
      expect(completed.status, AgentHistoryTurnStatus.completed);
    });

    test('maps plan entries', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 's1',
          'update': <String, Object?>{
            'sessionUpdate': 'plan',
            'entries': <Object?>[
              <String, Object?>{
                'content': 'Step 1',
                'status': 'pending',
                'priority': 'high',
              },
            ],
          },
        },
        runningTurnId: 't1',
      );
      final event = mapped.events.single as AgentPlanUpdatedEvent;
      expect(event.entries.single.content, 'Step 1');
    });

    test('keeps redacted x.ai updates page fixture parseable', () {
      final page = readFixtureJsonMap(
        'grok/acp/xai_session_updates_response_redacted.json',
      );

      expect(page['totalCount'], 2);
      expect(page['hasMore'], isFalse);
      expect(page['lastEventId'], 'evt-turn-completed');
      expect((page['updates']! as List<Object?>), hasLength(2));
      expect(jsonEncode(page), isNot(contains('super-secret')));
    });
  });

  group('parseAcpModelsPayload / GrokModelsCli.parseModelsOutput', () {
    test('parses ACP session models payload', () {
      final list = parseAcpModelsPayload(<String, Object?>{
        'currentModelId': 'grok-4.5',
        'availableModels': <Object?>[
          <String, Object?>{
            'modelId': 'grok-4.5',
            'name': 'Grok 4.5',
            'description': 'frontier',
            '_meta': <String, Object?>{
              'totalContextTokens': 500000,
              'supportsReasoningEffort': true,
              'reasoningEffort': 'high',
              'reasoningEfforts': <Object?>[
                <String, Object?>{
                  'id': 'high',
                  'value': 'high',
                  'description': 'Highest',
                },
              ],
            },
          },
        ],
      });
      expect(list, isNotNull);
      expect(list!.models.single.id, 'grok-4.5');
      expect(list.models.single.isDefault, isTrue);
      expect(list.models.single.supportedReasoningEfforts, isNotEmpty);
      expect(list.models.single.contextWindowTokens, 500000);
    });

    test('parses context window aliases only when positive', () {
      final list = parseAcpModelsPayload(<String, Object?>{
        'currentModelId': 'grok-4.5',
        'availableModels': <Object?>[
          <String, Object?>{
            'modelId': 'grok-4.5',
            'name': 'Grok 4.5',
            '_meta': <String, Object?>{'total_context_tokens': '500000'},
          },
          <String, Object?>{
            'modelId': 'invalid',
            'name': 'Invalid',
            '_meta': <String, Object?>{'totalContextTokens': 0},
          },
        ],
      });

      expect(list!.models.first.contextWindowTokens, 500000);
      expect(list.models.last.contextWindowTokens, isNull);
    });

    test('parses grok models CLI text', () {
      const stdout = '''
Default model: grok-4.5

Available models:
  * grok-4.5 (default)
  - grok-composer-2.5-fast
''';
      final list = GrokModelsCli.parseModelsOutput(stdout);
      expect(list.models, hasLength(2));
      expect(list.models.first.isDefault, isTrue);
      expect(list.models.last.id, 'grok-composer-2.5-fast');
    });
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FakeJsonRpcPeer implements JsonRpcPeer {
  final _notifications = StreamController<JsonRpcNotification>.broadcast();
  final _serverRequests = StreamController<JsonRpcRequest>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  final _protocolErrors =
      StreamController<JsonRpcProtocolException>.broadcast();

  final requestMethods = <String>[];
  final requestParams = <Object?>[];
  final responses = <Map<String, Object?>>[];
  final notificationsSent = <String>[];

  /// 模拟 session/load 期间推送 isReplay 更新。
  bool loadSessionEmitsReplay = false;

  /// 模拟 initialize 返回的 session/load 能力。
  bool supportsLoadSession = true;

  /// 模拟旧 Grok initialize 不带模型状态，以覆盖 CLI 降级竞态。
  bool includeModelState = true;

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  @override
  Stream<JsonRpcRequest> get serverRequests => _serverRequests.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Stream<JsonRpcProtocolException> get protocolErrors => _protocolErrors.stream;

  @override
  Future<void> start() async {}

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requestMethods.add(method);
    requestParams.add(params);
    return switch (method) {
      'initialize' => <String, Object?>{
        ...readFixtureJsonMap('grok/acp/initialize_0_2_101_redacted.json'),
        'agentCapabilities': <String, Object?>{
          'loadSession': supportsLoadSession,
        },
        if (!includeModelState) '_meta': <String, Object?>{},
      },
      'authenticate' => <String, Object?>{'_meta': <String, Object?>{}},
      'session/new' => readFixtureJsonMap(
        'grok/acp/session_new_0_2_101_redacted.json',
      ),
      'session/load' => () {
        if (loadSessionEmitsReplay) {
          // 在响应返回前同步发出回放通知（真实 Grok 行为）。
          emitNotification('session/update', <String, Object?>{
            'sessionId': 'sess-replay',
            'update': <String, Object?>{
              'sessionUpdate': 'agent_message_chunk',
              'messageId': 'replay-msg',
              'content': <String, Object?>{
                'type': 'text',
                'text': 'should not appear live',
              },
            },
            '_meta': <String, Object?>{'isReplay': true},
          });
        }
        return readFixtureJsonMap(
          'grok/acp/session_load_0_2_101_redacted.json',
        );
      }(),
      'session/prompt' => <String, Object?>{'stopReason': 'end_turn'},
      'session/set_model' => <String, Object?>{},
      _ => <String, Object?>{},
    };
  }

  @override
  void sendNotification(String method, {Object? params}) {
    notificationsSent.add(method);
  }

  @override
  Future<void> sendResponse(
    Object id, {
    Object? result,
    JsonRpcError? error,
  }) async {
    responses.add(<String, Object?>{
      'id': id,
      'result': ?result,
      if (error != null) 'error': error.toJson(),
    });
  }

  @override
  Future<void> close() async {
    await _notifications.close();
    await _serverRequests.close();
    await _stderr.close();
    await _protocolErrors.close();
  }

  void emitNotification(String method, Map<String, Object?> params) {
    _notifications.add(
      JsonRpcNotification(method: method, params: params, raw: params),
    );
  }

  void emitServerRequest({
    required Object id,
    required String method,
    required Map<String, Object?> params,
  }) {
    _serverRequests.add(
      JsonRpcRequest(id: id, method: method, params: params, raw: params),
    );
  }
}

class _DelayedModelsCli extends GrokModelsCli {
  _DelayedModelsCli(this.result);

  final Future<AgentModelList> result;

  @override
  Future<AgentModelList> listModels(AgentProviderConfig config) => result;
}
