import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/data/agent_provider_permission_migration.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/provider_operation_scheduler.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

import '../../../../../testing/agent_file_change_canonical.dart';

void main() {
  group('CodexAppServerAgentProvider', () {
    test('starts Codex app-server threads and turns', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
      );
      final turn = await provider.sendMessage(
        session: session,
        message: 'hello',
        context: const AgentContext(projectPath: '/repo'),
      );

      expect(session.id, 'thread-1');
      expect(turn.id, 'turn-1');
      expect(peer.requestMethods, <String>[
        'initialize',
        'thread/start',
        'turn/start',
      ]);
      expect(peer.notificationsSent, contains('initialized'));
      await provider.dispose();
    });

    test('rejects unknown turn mode before sending a request', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      await expectLater(
        provider.sendMessage(
          session: const AgentSession(
            id: 'thread-1',
            providerId: defaultAgentProviderId,
          ),
          context: const AgentContext(projectPath: '/repo'),
          message: 'hello',
          configuration: AgentTurnConfiguration(
            conversationMode: AgentConversationModeSelection(
              modeId: AgentConversationModeId.fromRaw('future-mode'),
              effectiveModelId: 'model-1',
            ),
          ),
        ),
        throwsA(
          isA<CodexTurnStartEncodingException>().having(
            (error) => error.message,
            'message',
            contains('future-mode'),
          ),
        ),
      );

      expect(peer.requestMethods, isEmpty);
    });

    test('rejects blank collaboration mode model before any RPC', () {
      final peer = _FakeJsonRpcPeer();

      expect(
        () => AgentConversationModeSelection(
          modeId: AgentConversationModeId.plan,
          effectiveModelId: '   ',
        ),
        throwsArgumentError,
      );
      expect(peer.requestMethods, isEmpty);
    });

    test('declares client capabilities during initialize', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      await provider.initialize();

      expect(peer.requestMethods.first, 'initialize');
      final params = peer.requestParams.first! as Map<String, Object?>;
      final clientInfo = params['clientInfo']! as Map<String, Object?>;
      expect(clientInfo['name'], 'zeta');

      final capabilities = params['capabilities']! as Map<String, Object?>;
      expect(capabilities['experimentalApi'], isTrue);
      expect(capabilities['requestAttestation'], isFalse);
      expect(capabilities['mcpServerOpenaiFormElicitation'], isFalse);

      final optOut = capabilities['optOutNotificationMethods']! as List<String>;
      expect(optOut, contains('thread/realtime/outputAudio/delta'));
      // ????????????????????
      expect(optOut, isNot(contains('thread/tokenUsage/updated')));
      expect(optOut, isNot(contains('turn/completed')));
      expect(optOut, isNot(contains('item/reasoning/textDelta')));
      expect(optOut, isNot(contains('item/plan/delta')));
      expect(optOut, isNot(contains('turn/diff/updated')));
      expect(optOut, isNot(contains('thread/status/changed')));
      expect(optOut, isNot(contains('serverRequest/resolved')));
      expect(optOut, isNot(contains('item/mcpToolCall/progress')));
      expect(optOut, isNot(contains('model/rerouted')));
      expect(optOut, isNot(contains('deprecationNotice')));
      expect(optOut, isNot(contains('account/rateLimits/updated')));
      await provider.dispose();
    });

    test(
      'lists collaboration modes with exact params and enables capability',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        expect(provider.capabilities.supportsModeSelection, isFalse);

        final first = await provider.listConversationModes();
        final second = await provider.listConversationModes();

        final requestIndex = peer.requestMethods.indexOf(
          'collaborationMode/list',
        );
        expect(requestIndex, isNonNegative);
        expect(peer.requestParams[requestIndex], const <String, Object?>{});
        expect(
          peer.requestMethods
              .where((method) => method == 'collaborationMode/list')
              .length,
          1,
        );
        expect(second, same(first));
        expect(
          first.presets.map((preset) => preset.id),
          <AgentConversationModeId>[
            AgentConversationModeId.defaultMode,
            AgentConversationModeId.plan,
          ],
        );
        final plan = first.presets.last;
        expect(plan.displayName, 'Plan');
        expect(plan.suggestedModelId, isNull);
        expect(plan.suggestedReasoningEffort, 'medium');
        expect(provider.capabilities.supportsModeSelection, isTrue);
      },
    );

    test(
      'keeps unknown modes while skipping malformed and duplicate entries',
      () async {
        final peer = _FakeJsonRpcPeer(
          collaborationModeListResponseProvider: (_) => <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'name': ' Default first ',
                'mode': ' DEFAULT ',
                'model': null,
                'reasoning_effort': null,
              },
              <String, Object?>{
                'name': 'Default duplicate',
                'mode': 'default',
                'model': 'ignored-model',
              },
              <String, Object?>{
                'name': ' Future mode ',
                'mode': ' FUTURE ',
                'model': ' future-model ',
                'reasoning_effort': ' ultra ',
              },
              <String, Object?>{
                'name': 'Broken mode',
                'mode': ' ',
                'model': null,
              },
              <String, Object?>{
                'name': 'Broken model',
                'mode': 'other',
                'model': 7,
              },
              42,
              <String, Object?>{
                'name': 'Plan',
                'mode': 'plan',
                'model': null,
                'reasoning_effort': ' medium ',
              },
            ],
          },
        );
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final catalog = await provider.listConversationModes();

        expect(catalog.presets.map((preset) => preset.id.rawValue), <String>[
          'default',
          'future',
          'plan',
        ]);
        expect(catalog.presets.first.displayName, 'Default first');
        expect(catalog.presets[1].id.kind, AgentConversationModeKind.unknown);
        expect(catalog.presets[1].suggestedModelId, 'future-model');
        expect(catalog.presets[1].suggestedReasoningEffort, 'ultra');
        expect(catalog.presets.last.suggestedReasoningEffort, 'medium');
        expect(provider.capabilities.supportsModeSelection, isTrue);
      },
    );

    test('retries a malformed collaboration mode response', () async {
      var responseCalls = 0;
      final peer = _FakeJsonRpcPeer(
        collaborationModeListResponseProvider: (_) {
          responseCalls += 1;
          if (responseCalls == 1) {
            return <String, Object?>{'data': <String, Object?>{}};
          }
          return _conversationModeListResponse();
        },
      );
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      await expectLater(
        provider.listConversationModes(),
        throwsA(isA<FormatException>()),
      );
      expect(provider.capabilities.supportsModeSelection, isFalse);

      final catalog = await provider.listConversationModes();

      expect(catalog.presets, hasLength(2));
      expect(responseCalls, 2);
      expect(provider.capabilities.supportsModeSelection, isTrue);
    });

    test(
      'marks method-not-found unsupported without breaking normal turns',
      () async {
        final peer = _FakeJsonRpcPeer(
          collaborationModeListResponseProvider: (_) {
            throw const JsonRpcException(
              JsonRpcError(code: -32601, message: 'Method not found'),
            );
          },
        );
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        await expectLater(
          provider.listConversationModes(),
          throwsA(isA<UnsupportedError>()),
        );
        await expectLater(
          provider.listConversationModes(),
          throwsA(isA<UnsupportedError>()),
        );
        final turn = await provider.sendMessage(
          session: const AgentSession(
            id: 'thread-1',
            providerId: defaultAgentProviderId,
          ),
          context: const AgentContext(projectPath: '/repo'),
          message: 'continue normally',
        );

        expect(turn.id, 'turn-1');
        expect(
          peer.requestMethods
              .where((method) => method == 'collaborationMode/list')
              .length,
          1,
        );
        expect(peer.requestMethods, contains('turn/start'));
        expect(provider.capabilities.supportsModeSelection, isFalse);
      },
    );

    test(
      'keeps an incomplete catalog cached but capability disabled',
      () async {
        var responseCalls = 0;
        final peer = _FakeJsonRpcPeer(
          collaborationModeListResponseProvider: (_) {
            responseCalls += 1;
            return <String, Object?>{
              'data': <Object?>[
                <String, Object?>{
                  'name': 'Default',
                  'mode': 'default',
                  'model': null,
                  'reasoning_effort': null,
                },
              ],
            };
          },
        );
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final first = await provider.listConversationModes();
        final second = await provider.listConversationModes();

        expect(second, same(first));
        expect(first.presets, hasLength(1));
        expect(responseCalls, 1);
        expect(provider.capabilities.supportsModeSelection, isFalse);
      },
    );

    test('coalesces concurrent collaboration mode catalog requests', () async {
      final gate = Completer<void>();
      final peer = _FakeJsonRpcPeer();
      peer.blockNextRequest('collaborationMode/list', gate);
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final firstFuture = provider.listConversationModes();
      await _waitUntil(
        () => peer.requestMethods.contains('collaborationMode/list'),
      );
      final secondFuture = provider.listConversationModes();
      await Future<void>.delayed(Duration.zero);

      expect(
        peer.requestMethods
            .where((method) => method == 'collaborationMode/list')
            .length,
        1,
      );

      gate.complete();
      final catalogs = await Future.wait(<Future<AgentConversationModeCatalog>>[
        firstFuture,
        secondFuture,
      ]);

      expect(catalogs[1], same(catalogs[0]));
    });

    test(
      'drops a disposed epoch catalog and reloads in a new runtime',
      () async {
        final gate = Completer<void>();
        final firstPeer = _FakeJsonRpcPeer();
        firstPeer.blockNextRequest('collaborationMode/list', gate);
        final firstProvider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: firstPeer,
        );

        final staleCatalog = firstProvider.listConversationModes();
        await _waitUntil(
          () => firstPeer.requestMethods.contains('collaborationMode/list'),
        );
        final disposeFuture = firstProvider.dispose();
        gate.complete();
        await staleCatalog;
        await disposeFuture;

        expect(firstProvider.capabilities.supportsModeSelection, isFalse);

        final secondPeer = _FakeJsonRpcPeer(
          collaborationModeListResponseProvider: (_) =>
              _conversationModeListResponse(planName: 'Plan next runtime'),
        );
        final secondProvider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: secondPeer,
        );
        addTearDown(secondProvider.dispose);

        final currentCatalog = await secondProvider.listConversationModes();

        expect(currentCatalog.presets.last.displayName, 'Plan next runtime');
        expect(secondPeer.requestMethods, contains('collaborationMode/list'));
        expect(secondProvider.capabilities.supportsModeSelection, isTrue);
      },
    );

    test('maps notifications to unified AgentEvents', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification('item/agentMessage/delta', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'itemId': 'message-1',
        'delta': 'Hello',
      });
      peer.emitNotification('item/started', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'item': <String, Object?>{
          'id': 'tool-1',
          'type': 'execute',
          'command': 'flutter test',
        },
        'startedAtMs': 1,
      });
      await Future<void>.delayed(Duration.zero);

      final messageDelta = events.whereType<AgentMessageDeltaEvent>().single;
      expect(messageDelta.messageId, 'message-1');
      expect(messageDelta.sourceMessageId, 'message-1');
      expect(messageDelta.kind, AgentMessageKind.regular);
      expect(messageDelta.delta, 'Hello');
      expect(
        events.whereType<AgentToolCallEvent>().single.toolCall.id,
        'tool-1',
      );
      expect(
        events.whereType<AgentToolCallEvent>().single.toolCall.sessionId,
        'thread-1',
      );
      expect(
        events.whereType<AgentToolCallEvent>().single.toolCall.turnId,
        'turn-1',
      );
      expect(
        events.whereType<AgentToolCallEvent>().single.toolCall.kind,
        AgentToolKind.execute,
      );

      await subscription.cancel();
      await provider.dispose();
    });

    test(
      'preserves stable item identity through message tool message',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitNotification('item/agentMessage/delta', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'message-a',
          'delta': 'A1',
        });
        peer.emitNotification('item/agentMessage/delta', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'message-a',
          'delta': 'A2',
        });
        peer.emitNotification('item/started', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'startedAtMs': 1000,
          'item': <String, Object?>{
            'id': 'tool-1',
            'type': 'commandExecution',
            'command': 'flutter test',
            'status': 'inProgress',
          },
        });
        peer.emitNotification('item/agentMessage/delta', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'message-b',
          'delta': 'B',
        });
        peer.emitNotification('item/completed', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'completedAtMs': 2000,
          'item': <String, Object?>{
            'id': 'message-a',
            'type': 'agentMessage',
            'text': 'A1A2',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(Duration.zero);

        final itemEvents = events
            .where(
              (event) =>
                  event is AgentMessageDeltaEvent ||
                  event is AgentToolCallEvent ||
                  event is AgentMessageUpdatedEvent,
            )
            .toList();
        expect(itemEvents, hasLength(5));
        final first = itemEvents[0] as AgentMessageDeltaEvent;
        final second = itemEvents[1] as AgentMessageDeltaEvent;
        final tool = itemEvents[2] as AgentToolCallEvent;
        final third = itemEvents[3] as AgentMessageDeltaEvent;
        final completed = itemEvents[4] as AgentMessageUpdatedEvent;
        expect(first.messageId, 'message-a');
        expect(second.messageId, first.messageId);
        expect('${first.delta}${second.delta}', 'A1A2');
        expect(tool.toolCall.id, 'tool-1');
        expect(third.messageId, 'message-b');
        expect(third.messageId, isNot(first.messageId));
        expect(completed.messageId, first.messageId);
        expect(completed.sourceMessageId, first.sourceMessageId);
        expect(completed.text, 'A1A2');
        expect(completed.status, AgentMessageStatus.completed);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test('tolerates a future item type and continues the connection', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification('item/started', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'startedAtMs': 1000,
        'item': <String, Object?>{
          'id': 'future-1',
          'type': 'futureCapability',
          'status': 'inProgress',
        },
      });
      peer.emitNotification('item/agentMessage/delta', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'itemId': 'message-after-future',
        'delta': 'still connected',
      });
      await Future<void>.delayed(Duration.zero);

      final futureItem = events.whereType<AgentToolCallEvent>().single.toolCall;
      expect(futureItem.id, 'future-1');
      expect(futureItem.kind, AgentToolKind.other);
      expect(
        events.whereType<AgentMessageDeltaEvent>().single.messageId,
        'message-after-future',
      );

      await subscription.cancel();
      await provider.dispose();
    });

    test('maps local turn_aborted into an interrupted history turn', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final sessionFile = await _writeJsonlFile(<Object?>[
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:00.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'task_started',
            'turn_id': 'turn-aborted',
            // Codex JSONL ? app-server Turn ??? Unix ??
            'started_at': 1783144800,
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:02.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'turn_aborted',
            'turn_id': 'turn-aborted',
            'completed_at': '2026-07-04T06:00:02.000Z',
            'duration_ms': 2000,
            'reason': 'user_cancelled',
          },
        },
      ]);
      addTearDown(() => sessionFile.parent.delete(recursive: true));

      final history = await provider.readThreadHistory(
        threadId: 'thread-aborted',
        sessionPath: sessionFile.path,
      );

      expect(history.turns.single.status, AgentHistoryTurnStatus.interrupted);
      expect(history.turns.single.duration, const Duration(seconds: 2));
      expect(history.turns.single.errorMessage, 'user_cancelled');
      await provider.dispose();
    });

    test(
      'maps reasoning stream notifications to AgentReasoningDeltaEvent',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitNotification('item/reasoning/textDelta', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'reasoning-1',
          'contentIndex': 0,
          'delta': 'raw thought',
        });
        peer.emitNotification(
          'item/reasoning/summaryTextDelta',
          <String, Object?>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reasoning-1',
            'summaryIndex': 0,
            'delta': 'summary A',
          },
        );
        peer.emitNotification(
          'item/reasoning/summaryPartAdded',
          <String, Object?>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reasoning-1',
            'summaryIndex': 1,
          },
        );
        peer.emitNotification('item/started', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'reasoning-1',
            'type': 'reasoning',
            'summary': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'summary_text',
                'text': 'final summary',
              },
            ],
          },
        });
        await Future<void>.delayed(Duration.zero);

        final deltas = events.whereType<AgentReasoningDeltaEvent>().toList();
        expect(deltas, hasLength(3));
        expect(deltas[0].kind, AgentReasoningDeltaKind.text);
        expect(deltas[0].sourceItemId, 'reasoning-1');
        expect(deltas[0].delta, 'raw thought');
        expect(deltas[0].contentIndex, 0);
        expect(deltas[1].kind, AgentReasoningDeltaKind.summaryText);
        expect(deltas[1].sourceItemId, 'reasoning-1');
        expect(deltas[1].delta, 'summary A');
        expect(deltas[1].summaryIndex, 0);
        expect(deltas[2].kind, AgentReasoningDeltaKind.summaryPart);
        expect(deltas[2].sourceItemId, 'reasoning-1');
        expect(deltas[2].delta, isEmpty);
        expect(deltas[2].summaryIndex, 1);

        final tool = events.whereType<AgentToolCallEvent>().single.toolCall;
        expect(tool.id, 'reasoning-1');
        expect(tool.kind, AgentToolKind.think);
        expect(tool.title, '思考');
        expect(tool.content, 'final summary');

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test('does not log realtime notifications and server requests', () async {
      const privateCodexHome = r'C:\private\codex-home-sentinel';
      final records = <LogEvent>[];
      late OutputCallback logListener;
      logListener = (event) => records.add(event.origin);
      await resetAppLoggingForTesting();
      Logger.addOutputListener(logListener);
      Logger.level = Level.all;
      configureAppLogging();
      addTearDown(() {
        Logger.removeOutputListener(logListener);
        return resetAppLoggingForTesting();
      });

      final peer = _FakeJsonRpcPeer(
        initializeResponse: const <String, Object?>{
          'codexHome': privateCodexHome,
          'platformFamily': 'windows',
          'platformOs': 'windows',
          'userAgent': 'codex_cli_rs/0.144.1',
        },
      );
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      peer.emitNotification('turn/started', <String, Object?>{
        'threadId': 'thread-1',
        'turn': <String, Object?>{'id': 'turn-1'},
      });
      peer.emitNotification('item/agentMessage/delta', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'itemId': 'message-1',
        'delta': 'Hello',
      });
      peer.emitServerRequest(
        id: 1,
        method: 'item/commandExecution/requestApproval',
        params: <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'command': 'flutter test',
        },
      );
      await Future<void>.delayed(Duration.zero);

      final fineMessages = records
          .where((record) => record.level == Level.trace)
          .map((record) => record.message)
          .toList();

      expect(
        fineMessages,
        isNot(anyElement(contains('Realtime notification'))),
      );
      expect(
        fineMessages.where(
          (message) => message.contains('Realtime server request'),
        ),
        isEmpty,
      );
      final renderedLogs = records
          .map(
            (record) => <Object?>[
              record.message,
              record.error,
              record.stackTrace,
            ].whereType<Object>().join(' '),
          )
          .join('\n');
      expect(renderedLogs, isNot(contains(privateCodexHome)));
      expect(renderedLogs, isNot(contains('flutter test')));
    });

    test('logs every unmatched notification and counts occurrences', () async {
      final records = <LogEvent>[];
      late OutputCallback logListener;
      logListener = (event) => records.add(event.origin);
      await resetAppLoggingForTesting();
      Logger.addOutputListener(logListener);
      Logger.level = Level.all;
      configureAppLogging();
      addTearDown(() {
        Logger.removeOutputListener(logListener);
        return resetAppLoggingForTesting();
      });

      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);

      await provider.initialize();
      await Future<void>.delayed(Duration.zero);
      events.clear();
      records.clear();

      peer.emitNotification('account/updated', <String, Object?>{
        'account': <String, Object?>{'type': 'chatgpt'},
      });
      peer.emitNotification('account/updated', <String, Object?>{
        'account': <String, Object?>{'type': 'apiKey'},
      });
      peer.emitNotification('skills/changed', <String, Object?>{
        'skills': <Object?>[],
      });
      await Future<void>.delayed(Duration.zero);

      final unmatchedFineMessages = records
          .where(
            (record) =>
                record.level == Level.trace &&
                record.message.contains(
                  'Ignoring unmatched Codex notification',
                ),
          )
          .map((record) => record.message)
          .toList();
      final skillsChangedMessages = records
          .where(
            (record) =>
                record.level == Level.trace &&
                record.message.contains('skills/changed received'),
          )
          .map((record) => record.message)
          .toList();

      expect(events, isEmpty);
      expect(unmatchedFineMessages, hasLength(2));
      expect(unmatchedFineMessages, everyElement(contains('account/updated')));
      expect(skillsChangedMessages, hasLength(1));
      expect(provider.unmatchedNotificationCountsForTesting, <String, int>{
        'account/updated': 2,
      });
      expect(provider.ignoredNotificationCountsForTesting, <String, int>{
        'account/updated|unsupported notification method': 2,
      });
    });

    test(
      'logs provider-filtered notifications without creating events',
      () async {
        final records = <LogEvent>[];
        late OutputCallback logListener;
        logListener = (event) => records.add(event.origin);
        await resetAppLoggingForTesting();
        Logger.addOutputListener(logListener);
        Logger.level = Level.all;
        configureAppLogging();
        addTearDown(() {
          Logger.removeOutputListener(logListener);
          return resetAppLoggingForTesting();
        });

        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);

        await provider.initialize();
        await Future<void>.delayed(Duration.zero);
        events.clear();
        records.clear();
        peer.emitNotification(
          'mcpServer/startupStatus/updated',
          <String, Object?>{'status': 'starting', 'message': 'warming'},
        );
        await Future<void>.delayed(Duration.zero);

        final codexFineMessages = records
            .where((record) => record.level == Level.trace)
            .map((record) => record.message)
            .toList();

        expect(events, isEmpty);
        expect(
          codexFineMessages.where(
            (message) => message.contains('mcpServer/startupStatus/updated'),
          ),
          hasLength(1),
        );
        expect(
          codexFineMessages.single,
          contains('reason=filtered by provider policy'),
        );
        expect(provider.unmatchedNotificationCountsForTesting, isEmpty);
        expect(provider.ignoredNotificationCountsForTesting, <String, int>{
          'mcpServer/startupStatus/updated|filtered by provider policy': 1,
        });
      },
    );

    test(
      'logs malformed thread and unsupported live item details safely',
      () async {
        final records = <LogEvent>[];
        late OutputCallback logListener;
        logListener = (event) => records.add(event.origin);
        await resetAppLoggingForTesting();
        Logger.addOutputListener(logListener);
        Logger.level = Level.all;
        configureAppLogging();
        addTearDown(() {
          Logger.removeOutputListener(logListener);
          return resetAppLoggingForTesting();
        });

        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);

        await provider.initialize();
        await Future<void>.delayed(Duration.zero);
        events.clear();
        records.clear();

        peer.emitNotification('thread/started', <String, Object?>{
          'thread': <String, Object?>{'title': 'private thread title'},
        });
        peer.emitNotification('thread/status/changed', <String, Object?>{
          'threadId': 'thread-1',
        });
        peer.emitNotification('item/completed', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'user-item-1',
            'type': 'userMessage',
            'text': 'private user content',
          },
        });
        peer.emitNotification('thread/tokenUsage/updated', <String, Object?>{
          'threadId': 'thread-1',
          'tokenUsage': <String, Object?>{},
        });
        await Future<void>.delayed(Duration.zero);

        final ignoredFineMessages = records
            .where(
              (record) =>
                  record.level == Level.trace &&
                  record.message.contains('Ignoring Codex notification'),
            )
            .map((record) => record.message)
            .toList();

        expect(events, isEmpty);
        expect(ignoredFineMessages, hasLength(4));
        expect(
          ignoredFineMessages,
          contains(
            allOf(
              contains('thread/started'),
              contains('reason=missing thread details'),
              contains('thread=present'),
            ),
          ),
        );
        expect(
          ignoredFineMessages,
          contains(
            allOf(
              contains('thread/status/changed'),
              contains('reason=missing thread status details'),
            ),
          ),
        );
        expect(
          ignoredFineMessages,
          contains(
            allOf(
              contains('item/completed'),
              contains('reason=user message is handled by the local send path'),
              contains('itemType=userMessage'),
            ),
          ),
        );
        expect(
          ignoredFineMessages,
          contains(
            allOf(
              contains('thread/tokenUsage/updated'),
              contains('reason=invalid token usage details'),
            ),
          ),
        );
        final renderedLogs = records.map((record) => record.message).join('\n');
        expect(renderedLogs, contains('thread/started'));
        expect(renderedLogs, contains('count=1'));
        expect(renderedLogs, isNot(contains('raw=')));
        expect(renderedLogs, isNot(contains('private thread title')));
        expect(renderedLogs, isNot(contains('private user content')));
      },
    );

    test(
      'maps completed agent message notifications without creating tool cards',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitNotification('item/agentMessage/delta', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'message-1',
          'delta': 'Done',
          'phase': 'commentary',
        });
        peer.emitNotification('item/completed', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'message-1',
            'type': 'agentMessage',
            'text': 'Done',
            'phase': 'commentary',
            'status': 'completed',
            'startedAtMs': 1000,
            'completedAtMs': 103000,
          },
        });
        await Future<void>.delayed(Duration.zero);

        final delta = events.whereType<AgentMessageDeltaEvent>().single;
        expect(delta.messageId, 'message-1');
        expect(delta.sourceMessageId, 'message-1');
        expect(delta.kind, AgentMessageKind.regular);
        expect(delta.phase, AgentMessagePhase.commentary);

        final update = events.whereType<AgentMessageUpdatedEvent>().single;
        expect(update.messageId, delta.messageId);
        expect(update.sourceMessageId, delta.sourceMessageId);
        expect(update.kind, delta.kind);
        expect(update.phase, AgentMessagePhase.commentary);
        expect(update.status, AgentMessageStatus.completed);
        expect(update.duration, const Duration(seconds: 102));
        expect(events.whereType<AgentToolCallEvent>(), isEmpty);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test(
      'maps agentMessage final_answer phase to AgentMessagePhase.response',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitNotification('item/agentMessage/delta', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'message-final',
          'delta': 'Done summary',
          'phase': 'final_answer',
        });
        peer.emitNotification('item/completed', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'message-final',
            'type': 'agentMessage',
            'text': 'Done summary',
            'phase': 'final_answer',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(Duration.zero);

        final delta = events.whereType<AgentMessageDeltaEvent>().single;
        expect(delta.sourceMessageId, 'message-final');
        expect(delta.kind, AgentMessageKind.regular);
        expect(delta.phase, AgentMessagePhase.response);

        final update = events.whereType<AgentMessageUpdatedEvent>().single;
        expect(update.messageId, delta.messageId);
        expect(update.sourceMessageId, delta.sourceMessageId);
        expect(update.kind, delta.kind);
        expect(update.phase, AgentMessagePhase.response);
        expect(update.status, AgentMessageStatus.completed);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test('maps item/plan/delta into streaming plan message deltas', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification('item/plan/delta', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'itemId': 'plan-1',
        'delta': '# Plan\n',
      });
      peer.emitNotification('item/plan/delta', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'itemId': 'plan-1',
        'delta': '- Step one',
      });
      await Future<void>.delayed(Duration.zero);

      final deltas = events.whereType<AgentMessageDeltaEvent>().toList();
      expect(deltas, hasLength(2));
      expect(deltas[0].messageId, 'plan-1');
      expect(deltas[0].sourceMessageId, 'plan-1');
      expect(deltas[0].kind, AgentMessageKind.plan);
      expect(deltas[0].delta, '# Plan\n');
      expect(deltas[0].status, AgentMessageStatus.streaming);
      expect(deltas[0].raw['type'], isNull);
      expect(deltas[0].sessionId, 'thread-1');
      expect(deltas[0].turnId, 'turn-1');
      expect(deltas[1].delta, '- Step one');
      expect(deltas[1].messageId, deltas[0].messageId);
      expect(deltas[1].sourceMessageId, deltas[0].sourceMessageId);
      expect(deltas[1].kind, deltas[0].kind);

      await subscription.cancel();
      await provider.dispose();
    });

    test(
      'maps turn/plan/updated schema steps into active plan entries',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitNotification('turn/plan/updated', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'plan': <Object?>[
            <String, Object?>{'step': 'Inspect code', 'status': 'completed'},
            <String, Object?>{'step': 'Build panel', 'status': 'inProgress'},
            <String, Object?>{'content': 'Run tests', 'status': 'pending'},
            <String, Object?>{'text': '  Legacy text  ', 'status': 'pending'},
            <String, Object?>{'step': '   ', 'status': 'pending'},
            <String, Object?>{'status': 'pending'},
          ],
        });
        await Future<void>.delayed(Duration.zero);

        final update = events.whereType<AgentPlanUpdatedEvent>().single;
        expect(update.sessionId, 'thread-1');
        expect(update.turnId, 'turn-1');
        expect(update.entries.map((entry) => entry.content), <String>[
          'Inspect code',
          'Build panel',
          'Run tests',
          'Legacy text',
        ]);
        expect(
          update.entries.map((entry) => entry.normalizedStatus),
          <AgentPlanEntryStatus>[
            AgentPlanEntryStatus.completed,
            AgentPlanEntryStatus.inProgress,
            AgentPlanEntryStatus.pending,
            AgentPlanEntryStatus.pending,
          ],
        );

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test('maps turn/diff/updated into typed live-only snapshot', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification('turn/diff/updated', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'diff':
            'diff --git a/lib/a.dart b/lib/a.dart\n'
            '--- a/lib/a.dart\n'
            '+++ b/lib/a.dart\n'
            '@@ -1 +1 @@\n'
            '-old\n'
            '+new\n',
      });
      await Future<void>.delayed(Duration.zero);

      final event = events.whereType<AgentTurnFileChangesEvent>().single;
      expect(event.sessionId, 'thread-1');
      expect(event.turnId, 'turn-1');
      expect(
        event.snapshot.replayability,
        AgentFileChangeReplayability.liveOnly,
      );
      expect(event.snapshot.changes, hasLength(1));
      expect(event.snapshot.changes.single.path, 'lib/a.dart');
      expect(event.snapshot.changes.single.kind, AgentFileChangeKind.modified);
      expect(
        (event.snapshot.changes.single.evidence as AgentUnifiedPatchEvidence)
            .patch,
        contains('+new'),
      );

      await subscription.cancel();
      await provider.dispose();
    });

    test(
      'maps pinned structured lifecycle and suppresses later aggregate',
      () async {
        final fixture = await _loadFileChangeFixture(
          'codex_structured_file_change_schema_0_144_5.json',
        );
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        for (final value in fixture['events']! as List<Object?>) {
          final event = (value! as Map).cast<String, Object?>();
          peer.emitNotification(
            event['method']! as String,
            (event['params']! as Map).cast<String, Object?>(),
          );
        }
        await Future<void>.delayed(Duration.zero);

        final tools = events.whereType<AgentToolCallEvent>().toList();
        expect(tools, hasLength(3));
        expect(tools.map((event) => event.toolCall.status), <AgentToolStatus>[
          AgentToolStatus.inProgress,
          AgentToolStatus.inProgress,
          AgentToolStatus.completed,
        ]);
        final envelopes = canonicalFileChangeEnvelopes(events);
        expect(envelopes.map((event) => event.status), <String>[
          'inProgress',
          'inProgress',
          'completed',
        ]);
        expect(envelopes.map((event) => event.ownerId).toSet(), hasLength(1));
        expect(
          envelopes.map((event) => event.snapshotSignature).toSet(),
          hasLength(1),
        );
        for (final event in tools) {
          final snapshot = event.toolCall.fileChanges;
          expect(snapshot?.revision, 1);
          expect(
            snapshot?.replayability,
            AgentFileChangeReplayability.replayable,
          );
          expect(snapshot?.changes, hasLength(1));
          expect(
            snapshot?.changes.single.path,
            '<WORKSPACE_REDACTED>/sample.txt',
          );
          expect(snapshot?.changes.single.kind, AgentFileChangeKind.modified);
          expect(
            snapshot?.changes.single.evidence,
            isA<AgentUnifiedPatchEvidence>(),
          );
        }
        expect(events.whereType<AgentTurnFileChangesEvent>(), isEmpty);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test(
      'clears an earlier turn fallback before emitting tool evidence',
      () async {
        final fixture = await _loadFileChangeFixture(
          'codex_structured_file_change_schema_0_144_5.json',
        );
        final fixtureEvents = fixture['events']! as List<Object?>;
        final turnDiff = (fixtureEvents[3]! as Map).cast<String, Object?>();
        final toolStarted = (fixtureEvents[0]! as Map).cast<String, Object?>();
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitNotification(
          turnDiff['method']! as String,
          (turnDiff['params']! as Map).cast<String, Object?>(),
        );
        peer.emitNotification(
          toolStarted['method']! as String,
          (toolStarted['params']! as Map).cast<String, Object?>(),
        );
        await Future<void>.delayed(Duration.zero);

        final fileEvents = events
            .where(
              (event) =>
                  event is AgentTurnFileChangesEvent ||
                  event is AgentToolCallEvent,
            )
            .toList();
        expect(fileEvents, hasLength(3));
        final fallback = fileEvents[0] as AgentTurnFileChangesEvent;
        final clear = fileEvents[1] as AgentTurnFileChangesEvent;
        final tool = fileEvents[2] as AgentToolCallEvent;
        expect(fallback.snapshot.changes, isNotEmpty);
        expect(
          fallback.snapshot.replayability,
          AgentFileChangeReplayability.liveOnly,
        );
        expect(clear.snapshot.changes, isEmpty);
        expect(clear.snapshot.revision, 2);
        expect(tool.toolCall.fileChanges?.changes, isNotEmpty);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test(
      'keeps command-only live, history, and replay free of file snapshots',
      () async {
        final fixture = await _loadFileChangeFixture(
          'codex_command_edit_0_144_1.json',
        );
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        for (final value in fixture['events']! as List<Object?>) {
          final event = (value! as Map).cast<String, Object?>();
          if (event['direction'] != 'notification') {
            continue;
          }
          peer.emitNotification(
            event['method']! as String,
            (event['params']! as Map).cast<String, Object?>(),
          );
        }
        await Future<void>.delayed(Duration.zero);

        final tools = events.whereType<AgentToolCallEvent>().toList();
        expect(tools, hasLength(2));
        expect(
          tools.map((event) => event.toolCall.kind),
          everyElement(AgentToolKind.execute),
        );
        expect(
          tools.map((event) => event.toolCall.fileChanges),
          everyElement(isNull),
        );
        expect(events.whereType<AgentTurnFileChangesEvent>(), isEmpty);

        final completedNotification = (fixture['events']! as List<Object?>)
            .map((value) => (value! as Map).cast<String, Object?>())
            .singleWhere((event) => event['method'] == 'item/completed');
        final completedItem =
            ((completedNotification['params']! as Map)['item']! as Map)
                .cast<String, Object?>();
        final historyPeer = _FakeJsonRpcPeer(
          threadReadResponseProvider: (_) => <String, Object?>{
            'thread': <String, Object?>{
              'id': 'codex-thread-redacted',
              'turns': <Object?>[
                <String, Object?>{
                  'id': 'codex-turn-redacted',
                  'status': 'completed',
                  'items': <Object?>[completedItem],
                },
              ],
            },
          },
        );
        final historyProvider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: historyPeer,
        );
        final history = await historyProvider.readThreadHistory(
          threadId: 'codex-thread-redacted',
        );
        final replay = await historyProvider.readThreadHistory(
          threadId: 'codex-thread-redacted',
        );
        final rebuiltTools = <AgentToolCall>[
          (history.turns.single.entries.single as AgentHistoryToolEntry)
              .toolCall,
          (replay.turns.single.entries.single as AgentHistoryToolEntry)
              .toolCall,
        ];
        expect(
          rebuiltTools.map((tool) => tool.kind),
          everyElement(AgentToolKind.execute),
        );
        expect(
          rebuiltTools.map((tool) => tool.fileChanges),
          everyElement(isNull),
        );

        await subscription.cancel();
        await provider.dispose();
        await historyProvider.dispose();
      },
    );

    test('maps thread/status/changed with active waiting flags', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification('thread/status/changed', <String, Object?>{
        'threadId': 'thread-1',
        'status': <String, Object?>{
          'type': 'active',
          'activeFlags': <String>['waitingOnApproval', 'waitingOnUserInput'],
        },
      });
      peer.emitNotification('thread/status/changed', <String, Object?>{
        'threadId': 'thread-1',
        'status': <String, Object?>{'type': 'idle'},
      });
      await Future<void>.delayed(Duration.zero);

      final statusEvents = events
          .whereType<AgentThreadStatusChangedEvent>()
          .toList();
      expect(statusEvents, hasLength(2));
      expect(statusEvents[0].threadId, 'thread-1');
      expect(statusEvents[0].status, AgentThreadRuntimeStatus.active);
      expect(statusEvents[0].waitingOnApproval, isTrue);
      expect(statusEvents[0].waitingOnUserInput, isTrue);
      expect(statusEvents[1].status, AgentThreadRuntimeStatus.idle);
      expect(statusEvents[1].waitingOnApproval, isFalse);
      expect(statusEvents[1].waitingOnUserInput, isFalse);

      await subscription.cancel();
      await provider.dispose();
    });

    test(
      'maps item/mcpToolCall/progress into AgentToolCallEvent progress append',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitNotification('item/mcpToolCall/progress', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'mcp-1',
          'message': 'Fetching resources?',
        });
        await Future<void>.delayed(Duration.zero);

        final toolEvent = events.whereType<AgentToolCallEvent>().single;
        expect(toolEvent.toolCall.id, 'mcp-1');
        expect(toolEvent.toolCall.title, 'MCP tool');
        expect(toolEvent.toolCall.kind, AgentToolKind.other);
        expect(toolEvent.toolCall.status, AgentToolStatus.inProgress);
        expect(toolEvent.toolCall.content, 'Fetching resources?');
        expect(toolEvent.toolCall.sessionId, 'thread-1');
        expect(toolEvent.toolCall.turnId, 'turn-1');
        expect(toolEvent.toolCall.raw['_progressAppend'], isTrue);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test(
      'maps remaining ThreadItem types from item/started and item/completed',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitNotification('item/started', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'search-1',
            'type': 'webSearch',
            'query': 'codex app-server',
            'action': <String, Object?>{
              'type': 'openPage',
              'url': 'https://example.com/docs',
            },
          },
        });
        peer.emitNotification('item/started', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'image-view-1',
            'type': 'imageView',
            'path': '/tmp/preview.png',
          },
        });
        peer.emitNotification('item/completed', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'image-gen-1',
            'type': 'imageGeneration',
            'status': 'completed',
            'result': 'generated',
            'savedPath': '/tmp/out.png',
          },
        });
        peer.emitNotification('item/started', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'collab-1',
            'type': 'collabAgentToolCall',
            'tool': 'spawnAgent',
            'status': 'inProgress',
            'senderThreadId': 'thread-1',
            'receiverThreadIds': <String>['thread-child'],
            'agentsStates': <String, Object?>{},
            'prompt': 'Investigate auth',
          },
        });
        peer.emitNotification('item/started', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'review-1',
            'type': 'enteredReviewMode',
            'review': 'Review uncommitted changes',
          },
        });
        peer.emitNotification('item/completed', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'compact-1',
            'type': 'contextCompaction',
          },
        });
        peer.emitNotification('item/started', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'hook-1',
            'type': 'hookPrompt',
            'fragments': <Object?>[
              <String, Object?>{
                'hookRunId': 'run-1',
                'text': 'Pre-commit checks',
              },
            ],
          },
        });
        peer.emitNotification('item/started', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'sleep-1',
            'type': 'sleep',
            'durationMs': 1500,
          },
        });
        peer.emitNotification('item/started', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'sub-1',
            'type': 'subAgentActivity',
            'agentPath': 'worker/auth',
            'agentThreadId': 'thread-child',
            'kind': 'started',
          },
        });
        await Future<void>.delayed(Duration.zero);

        final tools = events.whereType<AgentToolCallEvent>().toList();
        expect(tools, hasLength(4));
        expect(tools[0].toolCall.kind, AgentToolKind.search);
        expect(tools[0].toolCall.title, 'Web 搜索');
        expect(tools[0].toolCall.content, 'https://example.com/docs');
        expect(tools[1].toolCall.kind, AgentToolKind.read);
        expect(tools[1].toolCall.content, '/tmp/preview.png');
        expect(tools[2].toolCall.kind, AgentToolKind.fetch);
        expect(tools[2].toolCall.status, AgentToolStatus.completed);
        expect(tools[2].toolCall.locations, <String>['/tmp/out.png']);
        expect(tools[3].toolCall.title, '协作: spawnAgent');
        expect(tools[3].toolCall.content, 'Investigate auth');

        final systemItems = events.whereType<AgentSystemItemEvent>().toList();
        expect(systemItems, hasLength(5));
        expect(systemItems[0].entry.title, '进入评审模式');
        expect(systemItems[0].entry.description, 'Review uncommitted changes');
        expect(systemItems[1].entry.title, '上下文已压缩');
        expect(systemItems[2].entry.title, 'Hook 提示');
        expect(systemItems[2].entry.content, 'Pre-commit checks');
        expect(systemItems[3].entry.title, '等待中');
        expect(systemItems[3].entry.description, '休眠 1 秒');
        expect(systemItems[4].entry.title, '子代理活动');
        expect(systemItems[4].entry.description, '已启动 · worker/auth');

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test('maps model/rerouted into AgentModelReroutedEvent', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification('model/rerouted', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'fromModel': 'gpt-5.4',
        'toModel': 'gpt-5.5',
        'reason': 'highRiskCyberActivity',
      });
      await Future<void>.delayed(Duration.zero);

      final event = events.whereType<AgentModelReroutedEvent>().single;
      expect(event.threadId, 'thread-1');
      expect(event.turnId, 'turn-1');
      expect(event.fromModel, 'gpt-5.4');
      expect(event.toModel, 'gpt-5.5');
      expect(event.reason, 'highRiskCyberActivity');

      await subscription.cancel();
      await provider.dispose();
    });

    test('maps deprecationNotice into AgentDeprecationNoticeEvent', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification('deprecationNotice', <String, Object?>{
        'summary': 'turn/tokenCount is deprecated',
        'details': 'Use thread/tokenUsage/updated instead.',
      });
      await Future<void>.delayed(Duration.zero);

      final event = events.whereType<AgentDeprecationNoticeEvent>().single;
      expect(event.summary, 'turn/tokenCount is deprecated');
      expect(event.details, 'Use thread/tokenUsage/updated instead.');

      await subscription.cancel();
      await provider.dispose();
    });

    test('maps completed plan items into message updates', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification('item/completed', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'item': <String, Object?>{
          'id': 'turn-1-plan',
          'type': 'Plan',
          'text': '# Summary\n\n- First item',
          'status': 'completed',
        },
      });
      await Future<void>.delayed(Duration.zero);

      final update = events.whereType<AgentMessageUpdatedEvent>().single;
      expect(update.messageId, 'turn-1-plan');
      expect(update.sourceMessageId, 'turn-1-plan');
      expect(update.kind, AgentMessageKind.plan);
      expect(update.text, '# Summary\n\n- First item');
      expect(update.role, AgentMessageRole.agent);
      expect(update.status, AgentMessageStatus.completed);
      expect(events.whereType<AgentToolCallEvent>(), isEmpty);

      await subscription.cancel();
      await provider.dispose();
    });

    test(
      'maps approval requests and writes decisions back to JSON-RPC',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final approvalFuture = provider.events
            .where((event) => event is AgentPermissionRequestedEvent)
            .cast<AgentPermissionRequestedEvent>()
            .first;

        await provider.initialize();
        peer.emitServerRequest(
          id: 'approval-1',
          method: 'item/commandExecution/requestApproval',
          params: <String, Object?>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'item-1',
            'command': 'dart format .',
            'startedAtMs': 1,
            'commandActions': <Object?>[
              <String, Object?>{
                'type': 'read',
                'command': 'cat',
                'name': 'README.md',
                'path': '/repo/README.md',
              },
            ],
            'proposedExecpolicyAmendment': <Object?>['prefix:dart'],
          },
        );

        final approval = await approvalFuture;
        expect(approval.request.kind, AgentPermissionKind.commandExecution);
        expect(approval.request.command, 'dart format .');
        expect(approval.request.sessionId, 'thread-1');
        expect(approval.request.turnId, 'turn-1');
        expect(approval.request.commandActions, isNotEmpty);
        expect(approval.request.proposedExecpolicyAmendment, <String>[
          'prefix:dart',
        ]);

        await provider.respondToPermission(
          AgentPermissionDecision(
            requestId: approval.request.id,
            approved: true,
            commandDecision:
                AgentCommandApprovalDecisionKind.acceptWithExecpolicyAmendment,
            execpolicyAmendment: approval.request.proposedExecpolicyAmendment,
          ),
        );

        expect(peer.responses['approval-1'], <String, Object?>{
          'decision': <String, Object?>{
            'acceptWithExecpolicyAmendment': <String, Object?>{
              'execpolicy_amendment': <String>['prefix:dart'],
            },
          },
        });
        await provider.dispose();
      },
    );

    test(
      'clears pending approval on serverRequest/resolved without responding',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitServerRequest(
          id: 42,
          method: 'item/commandExecution/requestApproval',
          params: <String, Object?>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'command': 'flutter test',
          },
        );
        await Future<void>.delayed(Duration.zero);

        final requested = events
            .whereType<AgentPermissionRequestedEvent>()
            .single;
        expect(requested.request.id, '42');

        peer.emitNotification('serverRequest/resolved', <String, Object?>{
          'requestId': 42,
          'threadId': 'thread-1',
        });
        await Future<void>.delayed(Duration.zero);

        final resolved = events
            .whereType<AgentPermissionResolvedEvent>()
            .single;
        expect(resolved.requestId, '42');
        expect(resolved.threadId, 'thread-1');

        // ??????????????????????
        await provider.respondToPermission(
          AgentPermissionDecision(requestId: '42', approved: true),
        );
        expect(peer.responses.containsKey(42), isFalse);
        expect(peer.responses.containsKey('42'), isFalse);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test(
      'rejects unknown server requests with JSON-RPC error responses',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitServerRequest(
          id: 'unknown-1',
          method: 'some/unknown/request',
          params: const <String, Object?>{},
        );
        peer.emitServerRequest(
          id: 'tool-call-1',
          method: 'item/tool/call',
          params: const <String, Object?>{'tool': 'my_tool'},
        );
        peer.emitServerRequest(
          id: 'auth-1',
          method: 'account/chatgptAuthTokens/refresh',
          params: const <String, Object?>{},
        );
        await Future<void>.delayed(Duration.zero);

        // ????????? UI ?????
        expect(events.whereType<AgentPermissionRequestedEvent>(), isEmpty);

        final unknown = peer.errorResponses['unknown-1'];
        expect(unknown?.code, -32601);
        expect(unknown?.message, contains('some/unknown/request'));
        expect(peer.errorResponses['tool-call-1']?.code, -32601);
        expect(
          peer.errorResponses['tool-call-1']?.message,
          contains('Dynamic tool calls'),
        );
        expect(peer.errorResponses['auth-1']?.code, -32601);
        expect(peer.responses, isEmpty);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test(
      'responds to tool user input requests with schema-valid answers',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitServerRequest(
          id: 'input-1',
          method: 'item/tool/requestUserInput',
          params: const <String, Object?>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'item-1',
            'questions': <Object?>[
              <String, Object?>{
                'id': 'q1',
                'header': 'Destination',
                'question': 'Where should logs go?',
                'options': <Object?>[
                  <String, Object?>{
                    'label': 'stdout',
                    'description': 'Print to stdout',
                  },
                  <String, Object?>{
                    'label': 'file',
                    'description': 'Write to a file',
                  },
                ],
                'isOther': true,
              },
              <String, Object?>{
                'id': 'q2',
                'header': 'Secret',
                'question': 'API token?',
                'isSecret': true,
              },
            ],
          },
        );
        peer.emitServerRequest(
          id: 'input-2',
          method: 'item/tool/requestUserInput',
          params: const <String, Object?>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'item-2',
            'questions': <Object?>[],
          },
        );
        await Future<void>.delayed(Duration.zero);

        final requests = events
            .whereType<AgentQuestionRequestedEvent>()
            .toList();
        expect(requests, hasLength(2));
        expect(requests.first.request.questions, hasLength(2));
        expect(requests.first.request.questions.first.questionId, 'q1');
        expect(requests.first.request.questions.first.options, <String>[
          'stdout',
          'file',
        ]);
        expect(requests.first.request.questions.first.isOther, isTrue);
        expect(requests.first.request.questions[1].isSecret, isTrue);

        expect(events.whereType<AgentPermissionRequestedEvent>(), isEmpty);

        await provider.respondToQuestion(
          AgentQuestionResponse(
            requestId: requests[0].request.id,
            answers: const <String, List<String>>{
              'q1': <String>['stdout'],
              'q2': <String>['secret-token'],
            },
          ),
        );
        await provider.respondToQuestion(
          AgentQuestionResponse(requestId: requests[1].request.id),
        );

        expect(peer.responses['input-1'], <String, Object?>{
          'answers': <String, Object?>{
            'q1': <String, Object?>{
              'answers': <String>['stdout'],
            },
            'q2': <String, Object?>{
              'answers': <String>['secret-token'],
            },
          },
        });
        expect(peer.responses['input-2'], <String, Object?>{
          'answers': <String, Object?>{},
        });

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test(
      'clears pending user question on serverRequest/resolved without responding',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        await provider.initialize();
        peer.emitServerRequest(
          id: 'input-resolved',
          method: 'item/tool/requestUserInput',
          params: const <String, Object?>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'item-1',
            'questions': <Object?>[],
          },
        );
        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<AgentQuestionRequestedEvent>(), hasLength(1));

        peer.emitNotification('serverRequest/resolved', <String, Object?>{
          'requestId': 'input-resolved',
          'threadId': 'thread-1',
        });
        await Future<void>.delayed(Duration.zero);

        final resolved = events.whereType<AgentQuestionResolvedEvent>().single;
        expect(resolved.requestId, 'input-resolved');
        expect(resolved.threadId, 'thread-1');
        expect(events.whereType<AgentPermissionResolvedEvent>(), isEmpty);

        await provider.respondToQuestion(
          const AgentQuestionResponse(requestId: 'input-resolved'),
        );
        expect(peer.responses.containsKey('input-resolved'), isFalse);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    test('responds to MCP elicitation requests with action variants', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      for (final id in <String>['elicit-1', 'elicit-2', 'elicit-3']) {
        peer.emitServerRequest(
          id: id,
          method: 'mcpServer/elicitation/request',
          params: const <String, Object?>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
          },
        );
      }
      await Future<void>.delayed(Duration.zero);

      final requests = events
          .whereType<AgentPermissionRequestedEvent>()
          .toList();
      expect(requests, hasLength(3));

      await provider.respondToPermission(
        AgentPermissionDecision(
          requestId: requests[0].request.id,
          approved: true,
        ),
      );
      await provider.respondToPermission(
        AgentPermissionDecision(
          requestId: requests[1].request.id,
          approved: false,
        ),
      );
      await provider.respondToPermission(
        AgentPermissionDecision(
          requestId: requests[2].request.id,
          approved: false,
          cancelTurn: true,
        ),
      );

      expect(peer.responses['elicit-1'], <String, Object?>{
        'action': 'accept',
        'content': <String, Object?>{},
      });
      expect(peer.responses['elicit-2'], <String, Object?>{
        'action': 'decline',
      });
      expect(peer.responses['elicit-3'], <String, Object?>{'action': 'cancel'});

      await subscription.cancel();
      await provider.dispose();
    });

    test('lists project threads with Codex pagination params', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      final page = await provider.listThreads(
        query: const AgentThreadListQuery(
          projectPath: '/repo',
          limit: 5,
          cursor: 'cursor-1',
        ),
      );

      expect(peer.requestMethods, <String>['initialize', 'thread/list']);
      expect(peer.requestParams.last, <String, Object?>{
        'cwd': '/repo',
        'limit': 5,
        'cursor': 'cursor-1',
        'sortKey': 'updated_at',
        'sortDirection': 'desc',
        'archived': false,
      });
      expect(page.nextCursor, 'cursor-2');
      expect(page.threads.single.id, 'thread-1');
      expect(page.threads.single.projectPath, '/repo');
      expect(page.threads.single.sessionPath, '/tmp/thread-1.jsonl');
      expect(page.threads.single.displayName, 'Refactor provider');
      expect(
        page.threads.single.lastActiveAt,
        DateTime.fromMillisecondsSinceEpoch(130000),
      );
      expect(page.threads.single.status, AgentThreadRuntimeStatus.idle);
      await provider.dispose();
    });

    test('lists archived threads with searchTerm', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      await provider.listThreads(
        query: const AgentThreadListQuery(
          projectPath: '/repo',
          limit: 5,
          archived: true,
          searchTerm: 'refactor',
        ),
      );

      expect(peer.requestParams.last, <String, Object?>{
        'cwd': '/repo',
        'limit': 5,
        'sortKey': 'updated_at',
        'sortDirection': 'desc',
        'archived': true,
        'searchTerm': 'refactor',
      });
      await provider.dispose();
    });

    test('lists cross-project root threads by source kind', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      await provider.listThreads(
        query: const AgentThreadListQuery(
          projectPath: null,
          limit: 100,
          sourceKinds: <String>['cli', 'vscode', 'exec', 'appServer'],
        ),
      );

      expect(peer.requestParams.last, <String, Object?>{
        'limit': 100,
        'sortKey': 'updated_at',
        'sortDirection': 'desc',
        'archived': false,
        'sourceKinds': <String>['cli', 'vscode', 'exec', 'appServer'],
      });
      await provider.dispose();
    });

    test('reads Codex plan and rate-limit windows', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      final quota = await provider.readUsageQuota();

      expect(peer.requestMethods.last, 'account/rateLimits/read');
      expect(quota, isNotNull);
      expect(quota!.planType, 'plus');
      expect(quota.limitName, 'Codex');
      expect(quota.windows, hasLength(2));
      // primary 300min / secondary 10080min：标签走 windowDuration，limitName 仍用套餐名
      expect(quota.windows.first.label, '5 小时');
      expect(quota.windows.first.usedPercent, 36);
      expect(quota.windows.first.resetsAt, isNotNull);
      expect(quota.windows.first.windowDuration, const Duration(minutes: 300));
      expect(quota.windows.last.label, '1 周');
      expect(quota.windows.last.usedPercent, 72);
      expect(quota.windows.last.windowDuration, const Duration(minutes: 10080));
      expect(quota.credits?.unlimited, isFalse);
      expect(quota.credits?.balance, '12.50');
      // 明细可能被服务端截断，数量必须采用 availableCount。
      expect(quota.availableResetCreditCount, 2);
      await provider.dispose();
    });

    test(
      'keeps an explicit zero reset-card count without quota windows',
      () async {
        final peer = _FakeJsonRpcPeer(
          accountRateLimitsResponse: const <String, Object?>{
            'rateLimits': <String, Object?>{},
            'rateLimitResetCredits': <String, Object?>{'availableCount': 0},
          },
        );
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );

        final quota = await provider.readUsageQuota();

        expect(quota, isNotNull);
        expect(quota!.windows, isEmpty);
        expect(quota.availableResetCreditCount, 0);
        await provider.dispose();
      },
    );

    test('ignores malformed or negative reset-card counts', () async {
      for (final invalidCount in <Object?>[-1, '2']) {
        final peer = _FakeJsonRpcPeer(
          accountRateLimitsResponse: <String, Object?>{
            'rateLimits': const <String, Object?>{
              'primary': <String, Object?>{'usedPercent': 10},
            },
            'rateLimitResetCredits': <String, Object?>{
              'availableCount': invalidCount,
            },
          },
        );
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );

        final quota = await provider.readUsageQuota();

        expect(quota, isNotNull, reason: '$invalidCount');
        expect(
          quota!.availableResetCreditCount,
          isNull,
          reason: '$invalidCount',
        );
        await provider.dispose();
      }
    });

    test('thread lifecycle RPCs and notifications', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      await provider.initialize();

      await provider.renameThread(threadId: 'thread-1', name: 'New title');
      await provider.archiveThread('thread-1');
      await provider.unarchiveThread('thread-1');
      await provider.compactThread('thread-1');
      await provider.deleteThread('thread-1');

      expect(
        peer.requestMethods.where(
          (method) =>
              method == 'thread/name/set' ||
              method == 'thread/archive' ||
              method == 'thread/unarchive' ||
              method == 'thread/compact/start' ||
              method == 'thread/delete',
        ),
        <String>[
          'thread/name/set',
          'thread/archive',
          'thread/unarchive',
          'thread/compact/start',
          'thread/delete',
        ],
      );

      peer.emitNotification('thread/name/updated', <String, Object?>{
        'threadId': 'thread-1',
        'threadName': 'Renamed',
      });
      peer.emitNotification('thread/archived', <String, Object?>{
        'threadId': 'thread-1',
      });
      peer.emitNotification('thread/unarchived', <String, Object?>{
        'threadId': 'thread-2',
      });
      peer.emitNotification('thread/deleted', <String, Object?>{
        'threadId': 'thread-3',
      });
      peer.emitNotification('thread/closed', <String, Object?>{
        'threadId': 'thread-4',
      });
      peer.emitNotification('thread/compacted', <String, Object?>{
        'threadId': 'thread-5',
        'turnId': 'turn-1',
      });
      peer.emitNotification('thread/settings/updated', <String, Object?>{
        'threadId': 'thread-6',
        'threadSettings': <String, Object?>{'model': 'gpt-5.5'},
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        events.whereType<AgentThreadNameUpdatedEvent>().single.threadName,
        'Renamed',
      );
      expect(
        events.whereType<AgentThreadArchivedEvent>().single.threadId,
        'thread-1',
      );
      expect(
        events.whereType<AgentThreadUnarchivedEvent>().single.threadId,
        'thread-2',
      );
      expect(
        events.whereType<AgentThreadDeletedEvent>().single.threadId,
        'thread-3',
      );
      expect(
        events.whereType<AgentThreadClosedEvent>().single.threadId,
        'thread-4',
      );
      expect(
        events.whereType<AgentThreadCompactedEvent>().single.threadId,
        'thread-5',
      );
      expect(
        events.whereType<AgentThreadSettingsUpdatedEvent>().single.model,
        'gpt-5.5',
      );

      await subscription.cancel();
      await provider.dispose();
    });

    test('atomically maps all thread settings permission shapes', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);
      await provider.initialize();

      final cases =
          <
            ({
              String threadId,
              Map<String, Object?> settings,
              String? expectedOptionId,
            })
          >[
            (
              threadId: 'thread-policy-only',
              settings: <String, Object?>{
                'approvalPolicy': 'on-request',
                'sandboxPolicy': <String, Object?>{'type': 'readOnly'},
              },
              expectedOptionId: ':read-only',
            ),
            (
              threadId: 'thread-profile-only',
              settings: <String, Object?>{
                'activePermissionProfile': <String, Object?>{'id': 'team-safe'},
              },
              expectedOptionId: 'team-safe',
            ),
            (
              threadId: 'thread-combined',
              settings: <String, Object?>{
                'approvalPolicy': 'never',
                'sandboxPolicy': <String, Object?>{'type': 'dangerFullAccess'},
                'activePermissionProfile': <String, Object?>{
                  'id': 'team-safe',
                  'name': 'Team safe',
                },
              },
              expectedOptionId: 'team-safe',
            ),
            (
              threadId: 'thread-empty',
              settings: <String, Object?>{
                'approvalPolicy': '',
                'sandboxPolicy': '',
                'activePermissionProfile': <String, Object?>{'id': ''},
              },
              expectedOptionId: null,
            ),
            (
              threadId: 'thread-unknown-approval',
              settings: <String, Object?>{
                'approvalPolicy': 'future-policy',
                'sandboxPolicy': <String, Object?>{'type': 'readOnly'},
              },
              expectedOptionId: null,
            ),
            (
              threadId: 'thread-unknown-sandbox',
              settings: <String, Object?>{
                'approvalPolicy': 'on-request',
                'sandboxPolicy': <String, Object?>{'type': 'future-sandbox'},
              },
              expectedOptionId: null,
            ),
          ];
      for (final testCase in cases) {
        peer.emitNotification('thread/settings/updated', <String, Object?>{
          'threadId': testCase.threadId,
          'threadSettings': testCase.settings,
        });
      }
      await Future<void>.delayed(Duration.zero);

      final settingsEvents = events
          .whereType<AgentThreadSettingsUpdatedEvent>()
          .toList(growable: false);
      expect(settingsEvents, hasLength(cases.length));
      for (final testCase in cases) {
        final event = settingsEvents.singleWhere(
          (event) => event.threadId == testCase.threadId,
        );
        expect(
          event.permissionSelection?.optionId,
          testCase.expectedOptionId,
          reason: testCase.threadId,
        );
      }
    });

    test(
      'maps scoped thread settings collaboration modes into typed events',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);
        await provider.initialize();

        peer.emitNotification('thread/settings/updated', <String, Object?>{
          'threadId': 'thread-plan',
          'threadSettings': <String, Object?>{
            'model': 'gpt-5.4',
            'effort': 'high',
            'serviceTier': 'priority',
            'collaborationMode': <String, Object?>{
              'mode': ' PLAN ',
              'settings': <String, Object?>{
                'model': ' gpt-5.4 ',
                'reasoning_effort': ' medium ',
              },
            },
          },
        });
        peer.emitNotification('thread/settings/updated', <String, Object?>{
          'threadId': 'thread-default',
          'threadSettings': <String, Object?>{
            'collaborationMode': <String, Object?>{
              'mode': 'default',
              'settings': <String, Object?>{
                'model': 'gpt-5.4',
                'reasoning_effort': null,
              },
            },
          },
        });
        peer.emitNotification('thread/settings/updated', <String, Object?>{
          'threadId': 'thread-future',
          'threadSettings': <String, Object?>{
            'collaborationMode': <String, Object?>{
              'mode': 'Future-Mode',
              'settings': <String, Object?>{
                'model': 'gpt-next',
                'reasoning_effort': 'xhigh',
              },
            },
          },
        });
        peer.emitNotification('thread/settings/updated', <String, Object?>{
          'threadId': 'thread-malformed',
          'threadSettings': <String, Object?>{
            'model': 'gpt-5.4',
            'collaborationMode': <String, Object?>{
              'mode': 'plan',
              'settings': <String, Object?>{'model': '   '},
            },
          },
        });
        peer.emitNotification('thread/settings/updated', <String, Object?>{
          'threadSettings': <String, Object?>{
            'collaborationMode': <String, Object?>{
              'mode': 'plan',
              'settings': <String, Object?>{'model': 'gpt-5.4'},
            },
          },
        });
        await Future<void>.delayed(Duration.zero);

        final updates = events
            .whereType<AgentThreadSettingsUpdatedEvent>()
            .toList();
        expect(updates.map((event) => event.threadId), <String>[
          'thread-plan',
          'thread-default',
          'thread-future',
          'thread-malformed',
        ]);
        final plan = updates[0];
        expect(plan.model, 'gpt-5.4');
        expect(plan.reasoningEffort, 'high');
        expect(plan.serviceTierId, 'priority');
        expect(plan.collaborationMode?.modeId, AgentConversationModeId.plan);
        expect(plan.collaborationMode?.effectiveModelId, 'gpt-5.4');
        expect(plan.collaborationMode?.effectiveReasoningEffort, 'medium');

        expect(
          updates[1].collaborationMode?.modeId,
          AgentConversationModeId.defaultMode,
        );
        expect(updates[1].collaborationMode?.effectiveReasoningEffort, isNull);
        expect(
          updates[2].collaborationMode?.modeId.kind,
          AgentConversationModeKind.unknown,
        );
        expect(updates[2].collaborationMode?.modeId.rawValue, 'future-mode');
        expect(updates[3].model, 'gpt-5.4');
        expect(updates[3].collaborationMode, isNull);
      },
    );

    test(
      'serializes mutations per thread while allowing different threads',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.initialize();
        final archiveGate = Completer<void>();
        peer.blockNextRequest('thread/archive', archiveGate);

        final archive = provider.archiveThread('thread-1');
        await Future<void>.delayed(Duration.zero);
        final sameThreadDelete = provider.deleteThread('thread-1');
        final otherThreadDelete = provider.deleteThread('thread-2');
        await Future<void>.delayed(Duration.zero);

        expect(_deleteThreadIds(peer), <String>['thread-2']);

        archiveGate.complete();
        await Future.wait(<Future<void>>[
          archive,
          sameThreadDelete,
          otherThreadDelete,
        ]);
        expect(_deleteThreadIds(peer), <String>['thread-2', 'thread-1']);
      },
    );

    test('fork at turn sends stable inclusive lastTurnId boundary', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      final session = await provider.forkThread(
        threadId: 'thread-1',
        context: const AgentContext(projectPath: '/repo'),
        boundary: const AgentForkThroughTurn('turn-7'),
      );
      expect(session.id, isNotEmpty);
      expect(peer.requestMethods, contains('thread/fork'));
      expect(peer.requestParams.last, <String, Object?>{
        'threadId': 'thread-1',
        'lastTurnId': 'turn-7',
        'cwd': '/repo',
        'approvalPolicy': 'on-request',
        'permissions': ':workspace',
      });
      expect(peer.requestMethods, isNot(contains('thread/rollback')));

      await provider.dispose();
    });

    test('reads thread history with turns and maps items', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      final history = await provider.readThreadHistory(threadId: 'thread-1');

      expect(peer.requestMethods, <String>['initialize', 'thread/read']);
      expect(peer.requestParams.last, <String, Object?>{
        'threadId': 'thread-1',
        'includeTurns': true,
      });
      expect(history.threadId, 'thread-1');
      expect(_historyEntries(history), hasLength(8));
      expect(history.turns.map((turn) => turn.id), <String>['turn-1']);
      expect(history.currentTurn?.id, 'turn-1');

      final turn = _historyTurn(history, 'turn-1');
      expect(turn.entries, hasLength(8));
      expect(turn.status, AgentHistoryTurnStatus.completed);
      expect(turn.startedAt, DateTime.parse('2026-07-04T06:00:00.000Z'));
      expect(turn.completedAt, DateTime.parse('2026-07-04T06:00:03.000Z'));
      expect(turn.duration, const Duration(seconds: 3));
      expect(turn.cwd, '/repo');
      expect(turn.model, 'gpt-5');
      expect(turn.modelContextWindow, 258400);
      expect(turn.collaborationMode, AgentConversationModeId.defaultMode);
      expect(
        history.latestCollaborationMode,
        AgentConversationModeId.defaultMode,
      );

      final userMessage =
          _historyEntries(history)[0] as AgentHistoryMessageEntry;
      expect(userMessage.role, AgentMessageRole.user);
      expect(userMessage.text, 'Hello Agent');
      expect(userMessage.localImagePaths, <String>['/tmp/hello.png']);

      final agentMessage =
          _historyEntries(history)[1] as AgentHistoryMessageEntry;
      expect(agentMessage.role, AgentMessageRole.agent);
      expect(agentMessage.text, 'Hello human');
      expect(agentMessage.phase, AgentMessagePhase.commentary);
      expect(agentMessage.status, AgentMessageStatus.completed);
      expect(agentMessage.duration, const Duration(seconds: 102));

      final plan = _historyEntries(history)[2] as AgentHistoryMessageEntry;
      expect(plan.role, AgentMessageRole.agent);
      expect(plan.text, 'Check the project');
      expect(plan.status, AgentMessageStatus.completed);

      final command = _historyEntries(history)[3] as AgentHistoryToolEntry;
      expect(command.toolCall.kind, AgentToolKind.execute);
      expect(command.toolCall.status, AgentToolStatus.completed);
      expect(command.toolCall.content, 'All good');
      expect(command.toolCall.locations, <String>['/repo']);

      final fileChange = _historyEntries(history)[4] as AgentHistoryToolEntry;
      expect(fileChange.toolCall.kind, AgentToolKind.edit);
      expect(fileChange.toolCall.locations, <String>['lib/main.dart']);

      final webSearch = _historyEntries(history)[5] as AgentHistoryToolEntry;
      expect(webSearch.toolCall.kind, AgentToolKind.search);
      expect(webSearch.toolCall.title, 'Web 搜索');
      expect(webSearch.toolCall.content, 'zeta design system');

      final review = _historyEntries(history)[6] as AgentHistoryEventEntry;
      expect(review.kind, AgentHistoryEventKind.system);
      expect(review.title, '进入评审模式');
      expect(review.description, 'Review branch diff');

      final compact = _historyEntries(history)[7] as AgentHistoryEventEntry;
      expect(compact.kind, AgentHistoryEventKind.system);
      expect(compact.title, '上下文已压缩');
      await provider.dispose();
    });

    test(
      'rebuilds structured fileChange identically for live/history/replay',
      () async {
        final fixture = await _loadFileChangeFixture(
          'codex_structured_file_change_schema_0_144_5.json',
        );
        final item = (fixture['threadReadItem']! as Map)
            .cast<String, Object?>();
        final livePeer = _FakeJsonRpcPeer();
        final liveProvider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: livePeer,
        );
        final liveEvents = <AgentEvent>[];
        final liveSubscription = liveProvider.events.listen(liveEvents.add);
        await liveProvider.initialize();
        for (final value in fixture['events']! as List<Object?>) {
          final event = (value! as Map).cast<String, Object?>();
          livePeer.emitNotification(
            event['method']! as String,
            (event['params']! as Map).cast<String, Object?>(),
          );
        }
        await Future<void>.delayed(Duration.zero);
        final liveTool = liveEvents
            .whereType<AgentToolCallEvent>()
            .last
            .toolCall;

        final historyPeer = _FakeJsonRpcPeer(
          threadReadResponseProvider: (_) => <String, Object?>{
            'thread': <String, Object?>{
              'id': 'codex-thread-redacted',
              'turns': <Object?>[
                <String, Object?>{
                  'id': 'codex-turn-redacted',
                  'status': 'completed',
                  'items': <Object?>[item],
                },
              ],
            },
          },
        );
        final historyProvider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: historyPeer,
        );

        final history = await historyProvider.readThreadHistory(
          threadId: 'codex-thread-redacted',
        );
        final replay = await historyProvider.readThreadHistory(
          threadId: 'codex-thread-redacted',
        );
        final historyTool =
            (history.turns.single.entries.single as AgentHistoryToolEntry)
                .toolCall;
        final replayTool =
            (replay.turns.single.entries.single as AgentHistoryToolEntry)
                .toolCall;

        final liveEnvelope = canonicalFileChangeToolCall(liveTool);
        expect(
          canonicalFileChangeToolCall(historyTool).signature,
          liveEnvelope.signature,
        );
        expect(
          canonicalFileChangeToolCall(replayTool).signature,
          liveEnvelope.signature,
        );
        expect(historyTool.sessionId, 'codex-thread-redacted');
        expect(historyTool.turnId, 'codex-turn-redacted');
        expect(historyTool.kind, AgentToolKind.edit);
        expect(historyTool.status, AgentToolStatus.completed);
        expect(historyTool.fileChanges?.revision, 1);
        expect(
          historyTool.fileChanges?.replayability,
          AgentFileChangeReplayability.replayable,
        );
        expect(
          historyTool.fileChanges?.changes.single.kind,
          AgentFileChangeKind.modified,
        );
        expect(
          historyTool.fileChanges?.changes.single.evidence,
          isA<AgentUnifiedPatchEvidence>(),
        );
        expect(
          identical(liveTool.fileChanges, historyTool.fileChanges),
          isFalse,
        );
        expect(
          identical(historyTool.fileChanges, replayTool.fileChanges),
          isFalse,
        );

        await liveSubscription.cancel();
        await liveProvider.dispose();
        await historyProvider.dispose();
      },
    );

    test('prefers local session jsonl history when available', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final sessionFile = await _writeJsonlFile(<Object?>[
        <String, Object?>{
          'timestamp': '2026-07-04T05:59:59.000Z',
          'type': 'session_meta',
          'payload': <String, Object?>{
            'session_id': 'thread-1',
            'cwd': '/repo',
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:00.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'task_started',
            'turn_id': 'turn-local',
            'started_at': 1783144800,
            'model_context_window': 258400,
            'collaboration_mode_kind': 'Default',
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:00.100Z',
          'type': 'turn_context',
          'payload': <String, Object?>{
            'turn_id': 'turn-local',
            'cwd': '/repo',
            'model': 'gpt-5',
            'model_context_window': 258400,
            'collaboration_mode': 'Default',
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:00.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'user_message',
            'client_id': 'user-1',
            'message': 'Hello Agent',
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:01.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'agent_message',
            'message': 'Working on it',
            'phase': 'commentary',
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:02.000Z',
          'type': 'response_item',
          'payload': <String, Object?>{
            'type': 'function_call',
            'name': 'exec_command',
            'arguments': jsonEncode(<String, Object?>{
              'cmd': 'flutter test',
              'workdir': '/repo',
            }),
            'call_id': 'call-1',
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:03.000Z',
          'type': 'response_item',
          'payload': <String, Object?>{
            'type': 'function_call_output',
            'call_id': 'call-1',
            'output': 'Chunk ID: 1\nOutput:\nAll good\n',
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:04.000Z',
          'type': 'response_item',
          'payload': <String, Object?>{
            'type': 'custom_tool_call',
            'status': 'completed',
            'call_id': 'call-2',
            'name': 'apply_patch',
            'input':
                '*** Begin Patch\n*** Update File: lib/main.dart\n*** End Patch\n',
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:05.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'patch_apply_end',
            'call_id': 'call-2',
            'success': true,
            'stdout':
                'Success. Updated the following files:\nM lib/main.dart\n',
            'changes': <String, Object?>{
              'lib/main.dart': <String, Object?>{'type': 'update'},
            },
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:06.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'task_complete',
            'turn_id': 'turn-local',
            'completed_at': 1783144806,
            'duration_ms': 6000,
            'time_to_first_token_ms': 350,
          },
        },
      ]);
      addTearDown(() => sessionFile.parent.delete(recursive: true));

      final history = await provider.readThreadHistory(
        threadId: 'thread-1',
        sessionPath: sessionFile.path,
      );

      // 本地 JSONL 仍优先；同时 best-effort 读 thread/read 以叠终态错误。
      expect(peer.requestMethods, <String>['initialize', 'thread/read']);
      expect(history.threadId, 'thread-1');
      expect(_historyEntries(history), hasLength(4));
      expect(history.turns.map((turn) => turn.id), <String>['turn-local']);
      expect(history.currentTurn?.id, 'turn-local');

      final turn = _historyTurn(history, 'turn-local');
      expect(turn.entries, hasLength(4));
      expect(turn.status, AgentHistoryTurnStatus.completed);
      expect(turn.startedAt, DateTime.parse('2026-07-04T06:00:00.000Z'));
      expect(turn.completedAt, DateTime.parse('2026-07-04T06:00:06.000Z'));
      expect(turn.duration, const Duration(seconds: 6));
      expect(turn.timeToFirstToken, const Duration(milliseconds: 350));
      expect(turn.cwd, '/repo');
      expect(turn.model, 'gpt-5');
      expect(turn.modelContextWindow, 258400);
      expect(turn.collaborationMode, AgentConversationModeId.defaultMode);
      expect(
        history.latestCollaborationMode,
        AgentConversationModeId.defaultMode,
      );

      final userMessage =
          _historyEntries(history)[0] as AgentHistoryMessageEntry;
      expect(userMessage.role, AgentMessageRole.user);
      expect(userMessage.text, 'Hello Agent');

      final agentMessage =
          _historyEntries(history)[1] as AgentHistoryMessageEntry;
      expect(agentMessage.role, AgentMessageRole.agent);
      expect(agentMessage.phase, AgentMessagePhase.commentary);
      expect(agentMessage.text, 'Working on it');

      final command = _historyEntries(history)[2] as AgentHistoryToolEntry;
      expect(command.toolCall.title, 'flutter test');
      expect(command.toolCall.kind, AgentToolKind.execute);
      expect(command.toolCall.content, 'flutter test');
      expect(command.toolCall.locations, <String>['/repo']);

      final patch = _historyEntries(history)[3] as AgentHistoryToolEntry;
      expect(patch.toolCall.title, 'Apply patch');
      expect(patch.toolCall.kind, AgentToolKind.edit);
      expect(patch.toolCall.locations, <String>['lib/main.dart']);

      await provider.dispose();
    });

    test(
      'rebuilds typed file evidence from local patch_apply_end history',
      () async {
        final fixture = await _loadFileChangeFixture(
          'codex_patch_apply_end_history_0_144_1.json',
        );
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: _FakeJsonRpcPeer(),
        );
        addTearDown(provider.dispose);
        final sessionFile = await _writeJsonlFile(
          fixture['records']! as List<Object?>,
        );
        addTearDown(() => sessionFile.parent.delete(recursive: true));

        final history = await provider.readThreadHistory(
          threadId: 'codex-thread-redacted',
          sessionPath: sessionFile.path,
        );
        final tools = _historyEntries(history)
            .whereType<AgentHistoryToolEntry>()
            .map((entry) => entry.toolCall)
            .toList(growable: false);

        expect(tools, hasLength(4));
        expect(tools.first.title, 'Exec');
        expect(tools.first.kind, AgentToolKind.other);
        expect(tools.first.fileChanges, isNull);

        final patches = tools.skip(1).toList(growable: false);
        expect(patches.map((tool) => tool.title), everyElement('Apply patch'));
        expect(
          patches.map((tool) => tool.status),
          everyElement(AgentToolStatus.completed),
        );
        expect(
          patches.map((tool) => tool.fileChanges?.replayability),
          everyElement(AgentFileChangeReplayability.replayable),
        );

        final update = patches[0].fileChanges!.changes.single;
        expect(update.path, 'lib/example.dart');
        expect(update.kind, AgentFileChangeKind.modified);
        expect(
          (update.evidence as AgentUnifiedPatchEvidence).patch,
          contains('+[AFTER_REDACTED]'),
        );

        final created = patches[1].fileChanges!.changes.single;
        expect(created.path, 'lib/created.dart');
        expect(created.kind, AgentFileChangeKind.created);
        expect(
          (created.evidence as AgentWrittenContentEvidence).content,
          '[CREATED_CONTENT_REDACTED]\n',
        );

        final deleted = patches[2].fileChanges!.changes.single;
        expect(deleted.path, 'lib/deleted.dart');
        expect(deleted.kind, AgentFileChangeKind.deleted);
        expect(deleted.evidence, isNull);
      },
    );

    test(
      'normalizes online history modes and keeps the latest valid value',
      () async {
        final peer = _FakeJsonRpcPeer(
          threadReadResponseProvider: (_) => <String, Object?>{
            'thread': <String, Object?>{
              'id': 'thread-history',
              'turns': <Object?>[
                <String, Object?>{
                  'id': 'turn-plan',
                  'status': 'completed',
                  'collaborationMode': ' PLAN ',
                  'items': <Object?>[],
                },
                <String, Object?>{
                  'id': 'turn-default',
                  'status': 'completed',
                  'collaborationMode': <String, Object?>{'mode': ' Default '},
                  'items': <Object?>[],
                },
                <String, Object?>{
                  'id': 'turn-future',
                  'status': 'completed',
                  'collaboration_mode': <String, Object?>{
                    'mode': ' Future-Mode ',
                  },
                  'items': <Object?>[],
                },
                <String, Object?>{
                  'id': 'turn-missing',
                  'status': 'completed',
                  'items': <Object?>[],
                },
                <String, Object?>{
                  'id': 'turn-malformed',
                  'status': 'completed',
                  'collaborationMode': <String, Object?>{'mode': 42},
                  'items': <Object?>[],
                },
              ],
            },
          },
        );
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final history = await provider.readThreadHistory(
          threadId: 'thread-history',
        );

        expect(
          history.turns.map((turn) => turn.collaborationMode),
          <AgentConversationModeId?>[
            AgentConversationModeId.plan,
            AgentConversationModeId.defaultMode,
            AgentConversationModeId.fromRaw('future-mode'),
            null,
            null,
          ],
        );
        expect(
          history.latestCollaborationMode,
          AgentConversationModeId.fromRaw('future-mode'),
        );
      },
    );

    test(
      'normalizes JSONL history modes without losing the last valid value',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        final sessionFile = await _writeJsonlFile(<Object?>[
          <String, Object?>{
            'type': 'session_meta',
            'payload': <String, Object?>{'session_id': 'thread-jsonl-modes'},
          },
          <String, Object?>{
            'type': 'turn_context',
            'payload': <String, Object?>{
              'turn_id': 'turn-plan',
              'collaboration_mode': ' PLAN ',
            },
          },
          <String, Object?>{
            'type': 'turn_context',
            'payload': <String, Object?>{
              'turn_id': 'turn-future',
              'collaboration_mode': <String, Object?>{'mode': ' Future-Mode '},
            },
          },
          <String, Object?>{
            'type': 'turn_context',
            'payload': <String, Object?>{
              'turn_id': 'turn-future',
              'collaboration_mode': <String, Object?>{'mode': '   '},
            },
          },
          <String, Object?>{
            'type': 'turn_context',
            'payload': <String, Object?>{'turn_id': 'turn-missing'},
          },
        ]);
        addTearDown(() => sessionFile.parent.delete(recursive: true));

        final history = await provider.readThreadHistory(
          threadId: 'thread-jsonl-modes',
          sessionPath: sessionFile.path,
        );

        expect(peer.requestMethods, <String>['initialize', 'thread/read']);
        expect(
          _historyTurn(history, 'turn-plan').collaborationMode,
          AgentConversationModeId.plan,
        );
        final unknownMode = _historyTurn(
          history,
          'turn-future',
        ).collaborationMode;
        expect(unknownMode?.kind, AgentConversationModeKind.unknown);
        expect(unknownMode?.rawValue, 'future-mode');
        expect(_historyTurn(history, 'turn-missing').collaborationMode, isNull);
        expect(history.latestCollaborationMode, unknownMode);
      },
    );

    test(
      'maps permission warning and search entries from local session jsonl',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final sessionFile = await _writeJsonlFile(<Object?>[
          <String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'function_call',
              'name': 'request_user_input',
              'call_id': 'call-permission',
              'arguments': jsonEncode(<String, Object?>{
                'questions': <Object?>[
                  <String, Object?>{
                    'header': 'Data source',
                    'question': 'Which data source should we use?',
                    'options': <Object?>[
                      <String, Object?>{'label': 'Mock data'},
                      <String, Object?>{'label': 'Real files'},
                    ],
                  },
                ],
              }),
            },
          },
          <String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'tool_search_call',
              'call_id': 'call-search',
              'arguments': <String, Object?>{
                'query': 'rip_grep_packages',
                'limit': 8,
              },
            },
          },
          <String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'tool_search_output',
              'call_id': 'call-search',
              'tools': <Object?>[
                <String, Object?>{'name': 'rip_grep_packages'},
                <String, Object?>{'name': 'read_package_uris'},
              ],
            },
          },
          <String, Object?>{
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'config_warning',
              'message': 'History may be incomplete',
              'details': 'Partial session file detected',
            },
          },
          <String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'web_search_call',
              'id': 'ws-1',
              'action': <String, Object?>{
                'type': 'search',
                'query': 'OpenAI docs',
                'queries': <Object?>['OpenAI docs', 'Codex app-server'],
              },
            },
          },
          <String, Object?>{
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'web_search_end',
              'call_id': 'ws-1',
              'query': 'OpenAI docs',
              'action': <String, Object?>{
                'type': 'search',
                'query': 'OpenAI docs',
                'queries': <Object?>['OpenAI docs', 'Codex app-server'],
              },
            },
          },
        ]);
        addTearDown(() => sessionFile.parent.delete(recursive: true));

        final history = await provider.readThreadHistory(
          threadId: 'thread-1',
          sessionPath: sessionFile.path,
        );

        expect(peer.requestMethods, <String>['initialize', 'thread/read']);
        expect(_historyEntries(history), hasLength(4));
        expect(
          _historyEntries(
            history,
          ).whereType<AgentHistoryEventEntry>().map((entry) => entry.kind),
          <AgentHistoryEventKind>[
            AgentHistoryEventKind.permission,
            AgentHistoryEventKind.search,
            AgentHistoryEventKind.warning,
            AgentHistoryEventKind.search,
          ],
        );

        final permission =
            _historyEntries(history)[0] as AgentHistoryEventEntry;
        expect(permission.title, 'Requested user input');
        expect(permission.description, 'Which data source should we use?');
        expect(permission.content, contains('Mock data'));

        final toolSearch =
            _historyEntries(history)[1] as AgentHistoryEventEntry;
        expect(toolSearch.title, 'Tool search');
        expect(toolSearch.content, 'rip_grep_packages\nlimit=8');

        final warning = _historyEntries(history)[2] as AgentHistoryEventEntry;
        expect(warning.title, 'Config Warning');
        expect(warning.description, 'History may be incomplete');

        final webSearch = _historyEntries(history)[3] as AgentHistoryEventEntry;
        expect(webSearch.title, 'Web search');
        expect(webSearch.description, 'OpenAI docs');
        expect(webSearch.content, contains('Codex app-server'));

        await provider.dispose();
      },
    );

    test(
      'backfills request_user_input answers from function_call_output',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final sessionFile = await _writeJsonlFile(<Object?>[
          <String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'function_call',
              'name': 'request_user_input',
              'call_id': 'call-qa',
              'arguments': jsonEncode(<String, Object?>{
                'questions': <Object?>[
                  <String, Object?>{
                    'id': 'logging_destination',
                    'header': '????',
                    'question': '?????????',
                    'options': <Object?>[
                      <String, Object?>{'label': '???? (Recommended)'},
                      <String, Object?>{'label': '??????'},
                    ],
                  },
                  <String, Object?>{
                    'id': 'logging_api',
                    'header': '????',
                    'question': '?? API ????????',
                    'options': <Object?>[
                      <String, Object?>{'label': '???? (Recommended)'},
                      <String, Object?>{'label': 'logging ?'},
                    ],
                  },
                ],
              }),
            },
          },
          <String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'function_call_output',
              'call_id': 'call-qa',
              'output': jsonEncode(<String, Object?>{
                'answers': <String, Object?>{
                  'logging_destination': <String, Object?>{
                    'answers': <String>['???? (Recommended)'],
                  },
                  'logging_api': <String, Object?>{
                    'answers': <String>['logging ?'],
                  },
                },
              }),
            },
          },
        ]);
        addTearDown(() => sessionFile.parent.delete(recursive: true));

        final history = await provider.readThreadHistory(
          threadId: 'thread-1',
          sessionPath: sessionFile.path,
        );

        final entry = _historyEntries(history).single as AgentHistoryEventEntry;
        expect(entry.title, 'Requested user input');
        expect(entry.qaPairs, isNotNull);
        expect(entry.qaPairs, hasLength(2));

        final first = entry.qaPairs![0];
        expect(first.questionId, 'logging_destination');
        expect(first.question, '?????????');
        expect(first.header, '????');
        expect(first.options, <String>['???? (Recommended)', '??????']);
        expect(first.answers, <String>['???? (Recommended)']);

        final second = entry.qaPairs![1];
        expect(second.questionId, 'logging_api');
        expect(second.question, '?? API ????????');
        expect(second.answers, <String>['logging ?']);

        await provider.dispose();
      },
    );

    test(
      'ignores custom_tool_call_output and keeps invocation preview',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final sessionFile = await _writeJsonlFile(<Object?>[
          <String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'custom_tool_call',
              'status': 'completed',
              'call_id': 'call-custom',
              'name': 'apply_patch',
              'input':
                  '*** Begin Patch\n*** Update File: lib/main.dart\n*** End Patch\n',
            },
          },
          <String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'custom_tool_call_output',
              'call_id': 'call-custom',
              'output':
                  'Success. Updated the following files:\nM lib/main.dart\n',
            },
          },
        ]);
        addTearDown(() => sessionFile.parent.delete(recursive: true));

        final history = await provider.readThreadHistory(
          threadId: 'thread-1',
          sessionPath: sessionFile.path,
        );

        final entry = _historyEntries(history).single as AgentHistoryToolEntry;
        expect(entry.toolCall.title, 'Apply patch');
        expect(entry.toolCall.content, 'lib/main.dart');
        expect(entry.toolCall.locations, <String>['lib/main.dart']);

        await provider.dispose();
      },
    );

    test('skips bad lines and keeps remaining local history', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final directory = Directory.systemTemp.createTempSync('zeta_jsonl_bad_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/session.jsonl');
      await file.writeAsString(
        <String>[
          'not-json',
          jsonEncode(<String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'function_call',
              'name': 'exec_command',
              'call_id': 'call-1',
              'arguments': jsonEncode(<String, Object?>{
                'cmd': 'dart format .',
              }),
            },
          }),
          jsonEncode(<String, Object?>{
            'type': 'response_item',
            'payload': <String, Object?>{
              'type': 'function_call_output',
              'call_id': 'missing-call',
              'output': 'Output:\nignored\n',
            },
          }),
          jsonEncode(<String, Object?>{
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'user_message',
              'client_id': 'user-1',
              'message': 'Still recover this',
            },
          }),
        ].join('\n'),
      );

      final history = await provider.readThreadHistory(
        threadId: 'thread-1',
        sessionPath: file.path,
      );

      expect(peer.requestMethods, <String>['initialize', 'thread/read']);
      expect(_historyEntries(history), hasLength(2));
      expect(
        (_historyEntries(history)[0] as AgentHistoryToolEntry).toolCall.title,
        'dart format .',
      );
      expect(
        (_historyEntries(history)[1] as AgentHistoryMessageEntry).text,
        'Still recover this',
      );

      await provider.dispose();
    });

    test(
      'maps local_images from session jsonl user_message into localImagePaths',
      () async {
        // 对齐真实 Codex rollout：event_msg.user_message.local_images 为绝对路径；
        // 历史气泡依赖 localImagePaths 渲染缩略图，不能只拼文本占位。
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        const imagePath =
            r'C:\Users\tester\AppData\Local\Temp\zeta-agent-images\paste-1.png';
        final sessionFile = await _writeJsonlFile(<Object?>[
          <String, Object?>{
            'timestamp': '2026-08-10T08:28:11.000Z',
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'task_started',
              'turn_id': 'turn-image',
              'started_at': 1786350491,
            },
          },
          <String, Object?>{
            'timestamp': '2026-08-10T08:28:11.448Z',
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'user_message',
              'client_id': 'msg-image-1',
              'message': 'What does this screenshot show?',
              'images': <Object?>[],
              'local_images': <Object?>[imagePath],
              'text_elements': <Object?>[],
            },
          },
          <String, Object?>{
            'timestamp': '2026-08-10T08:28:20.000Z',
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'task_complete',
              'turn_id': 'turn-image',
              'completed_at': 1786350500,
              'duration_ms': 9000,
            },
          },
        ]);
        addTearDown(() => sessionFile.parent.delete(recursive: true));

        final history = await provider.readThreadHistory(
          threadId: 'thread-1',
          sessionPath: sessionFile.path,
        );

        final user = _historyEntries(history)
            .whereType<AgentHistoryMessageEntry>()
            .singleWhere((entry) => entry.role == AgentMessageRole.user);
        expect(user.text, 'What does this screenshot show?');
        expect(user.localImagePaths, <String>[imagePath]);
        expect(user.text, isNot(contains('Local images')));
        expect(user.text, isNot(contains(imagePath)));

        await provider.dispose();
      },
    );

    test(
      'keeps image-only jsonl user_message when local_images is present',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        const imagePath = r'D:\tmp\zeta-only.png';
        final sessionFile = await _writeJsonlFile(<Object?>[
          <String, Object?>{
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'user_message',
              'client_id': 'msg-image-only',
              'message': '',
              'local_images': <Object?>[imagePath],
            },
          },
        ]);
        addTearDown(() => sessionFile.parent.delete(recursive: true));

        final history = await provider.readThreadHistory(
          threadId: 'thread-1',
          sessionPath: sessionFile.path,
        );

        final user = _historyEntries(history)
            .whereType<AgentHistoryMessageEntry>()
            .singleWhere((entry) => entry.role == AgentMessageRole.user);
        expect(user.text, isEmpty);
        expect(user.localImagePaths, <String>[imagePath]);

        await provider.dispose();
      },
    );

    test('thread/read extracts path from input_text image markup', () async {
      // thread/read 偶发把路径写在 <image path="…"> 标记里，而不是 localImage 字段。
      final peer = _FakeJsonRpcPeer(
        threadReadResponseProvider: (_) => <String, Object?>{
          'thread': <String, Object?>{
            'id': 'thread-markup',
            'turns': <Object?>[
              <String, Object?>{
                'id': 'turn-1',
                'status': 'completed',
                'items': <Object?>[
                  <String, Object?>{
                    'type': 'userMessage',
                    'id': 'user-1',
                    'content': <Object?>[
                      <String, Object?>{
                        'type': 'input_text',
                        'text': 'Describe the UI',
                      },
                      <String, Object?>{
                        'type': 'input_text',
                        'text':
                            r'<image name=[Image #1] path="D:\tmp\shot.png">',
                      },
                      <String, Object?>{
                        'type': 'input_image',
                        'image_url': 'data:image/png;base64,AAAA',
                        'detail': 'high',
                      },
                      <String, Object?>{
                        'type': 'input_text',
                        'text': '</image>',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        },
      );
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      final history = await provider.readThreadHistory(
        threadId: 'thread-markup',
      );

      final user = _historyEntries(history).single as AgentHistoryMessageEntry;
      expect(user.role, AgentMessageRole.user);
      expect(user.text, 'Describe the UI');
      expect(user.localImagePaths, <String>[r'D:\tmp\shot.png']);
      expect(user.text, isNot(contains('<image')));
      expect(user.text, isNot(contains('</image>')));

      await provider.dispose();
    });

    test(
      'falls back to thread/read when local session path is missing',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );

        final history = await provider.readThreadHistory(threadId: 'thread-1');

        expect(peer.requestMethods, <String>['initialize', 'thread/read']);
        expect(_historyEntries(history), isNotEmpty);
        await provider.dispose();
      },
    );

    test('falls back to thread/read when session file is empty', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final sessionFile = await _writeJsonlFile(<Object?>[
        <String, Object?>{
          'type': 'response_item',
          'payload': <String, Object?>{
            'type': 'reasoning',
            'encrypted_content': 'hidden',
          },
        },
      ]);
      addTearDown(() => sessionFile.parent.delete(recursive: true));

      final history = await provider.readThreadHistory(
        threadId: 'thread-1',
        sessionPath: sessionFile.path,
      );

      expect(peer.requestMethods, <String>['initialize', 'thread/read']);
      expect(_historyEntries(history), hasLength(8));
      await provider.dispose();
    });

    test('parses token_count events into turn token usage', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final sessionFile = await _writeJsonlFile(<Object?>[
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:00.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'task_started',
            'turn_id': 'turn-tokens',
            'started_at': '2026-07-04T06:00:00.000Z',
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:02.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'token_count',
            'turn_id': 'turn-tokens',
            'info': <String, Object?>{
              'total_token_usage': <String, Object?>{
                'input_tokens': 41910,
                'cached_input_tokens': 19712,
                'output_tokens': 1552,
                'reasoning_output_tokens': 780,
                'total_tokens': 43462,
              },
              'last_token_usage': <String, Object?>{
                'input_tokens': 26672,
                'cached_input_tokens': 14720,
                'output_tokens': 1051,
                'reasoning_output_tokens': 532,
                'total_tokens': 27723,
              },
              'model_context_window': 258400,
            },
          },
        },
        <String, Object?>{
          'timestamp': '2026-07-04T06:00:03.000Z',
          'type': 'event_msg',
          'payload': <String, Object?>{
            'type': 'task_complete',
            'turn_id': 'turn-tokens',
            'completed_at': '2026-07-04T06:00:03.000Z',
            'duration_ms': 3000,
          },
        },
      ]);
      addTearDown(() => sessionFile.parent.delete(recursive: true));

      final history = await provider.readThreadHistory(
        threadId: 'thread-1',
        sessionPath: sessionFile.path,
      );

      expect(history.turns, hasLength(1));
      final turn = history.turns.single;
      expect(turn.id, 'turn-tokens');
      expect(turn.tokenUsage, isNotNull);
      expect(turn.tokenUsage!.inputTokens, 41910);
      expect(turn.tokenUsage!.cachedInputTokens, 19712);
      expect(turn.tokenUsage!.outputTokens, 772);
      expect(turn.tokenUsage!.reasoningOutputTokens, 780);
      expect(turn.tokenUsage!.totalTokens, 43462);
      expect(turn.tokenUsage!.lastInputTokens, 26672);
      expect(turn.tokenUsage!.lastTotalTokens, 27723);
      expect(turn.modelContextWindow, 258400);
      await provider.dispose();
    });

    test(
      'emits AgentTokenUsageEvent for turn/tokenCount notifications',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.initialize();

        final events = <AgentEvent>[];
        final sub = provider.events.listen(events.add);
        addTearDown(sub.cancel);

        peer.emitNotification('turn/tokenCount', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-live',
          'info': <String, Object?>{
            'total_token_usage': <String, Object?>{
              'input_tokens': 1000,
              'cached_input_tokens': 200,
              'output_tokens': 300,
              'reasoning_output_tokens': 50,
              'total_tokens': 1300,
            },
            'last_token_usage': <String, Object?>{
              'input_tokens': 1000,
              'total_tokens': 1300,
            },
          },
        });
        await Future<void>.delayed(Duration.zero);

        final usageEvent = events.whereType<AgentTokenUsageEvent>().single;
        expect(usageEvent.sessionId, 'thread-1');
        expect(usageEvent.turnId, 'turn-live');
        expect(usageEvent.tokenUsage.totalTokens, 1300);
        expect(usageEvent.tokenUsage.inputTokens, 1000);
        expect(usageEvent.tokenUsage.cachedInputTokens, 200);
        expect(usageEvent.tokenUsage.outputTokens, 250);
        expect(usageEvent.tokenUsage.reasoningOutputTokens, 50);
        expect(usageEvent.tokenUsage.lastTotalTokens, 1300);
      },
    );

    test(
      'emits AgentTokenUsageEvent for thread/tokenUsage/updated notifications',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.initialize();

        final events = <AgentEvent>[];
        final sub = provider.events.listen(events.add);
        addTearDown(sub.cancel);

        // ???????tokenUsage ?? camelCase ? total/last breakdown?
        peer.emitNotification('thread/tokenUsage/updated', <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-live',
          'tokenUsage': <String, Object?>{
            'total': <String, Object?>{
              'inputTokens': 41910,
              'cachedInputTokens': 19712,
              'outputTokens': 1552,
              'reasoningOutputTokens': 780,
              'totalTokens': 43462,
            },
            'last': <String, Object?>{
              'inputTokens': 26672,
              'cachedInputTokens': 14720,
              'outputTokens': 1051,
              'reasoningOutputTokens': 532,
              'totalTokens': 27723,
            },
            'modelContextWindow': 258400,
          },
        });
        await Future<void>.delayed(Duration.zero);

        final usageEvent = events.whereType<AgentTokenUsageEvent>().single;
        expect(usageEvent.sessionId, 'thread-1');
        expect(usageEvent.turnId, 'turn-live');
        expect(usageEvent.tokenUsage.inputTokens, 41910);
        expect(usageEvent.tokenUsage.cachedInputTokens, 19712);
        expect(usageEvent.tokenUsage.outputTokens, 772);
        expect(usageEvent.tokenUsage.reasoningOutputTokens, 780);
        expect(usageEvent.tokenUsage.totalTokens, 43462);
        expect(usageEvent.tokenUsage.lastInputTokens, 26672);
        expect(usageEvent.tokenUsage.lastCachedInputTokens, 14720);
        expect(usageEvent.tokenUsage.lastOutputTokens, 519);
        expect(usageEvent.tokenUsage.lastReasoningOutputTokens, 532);

        expect(usageEvent.tokenUsage.lastTotalTokens, 27723);
        expect(usageEvent.tokenUsage.modelContextWindow, 258400);
      },
    );

    test('parses error notifications with nested TurnError payloads', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      await provider.initialize();

      final events = <AgentEvent>[];
      final sub = provider.events.listen(events.add);
      addTearDown(sub.cancel);

      // ??????????????? TurnError ????
      peer.emitNotification('error', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-live',
        'willRetry': true,
        'error': <String, Object?>{
          'message': 'Context window exceeded',
          'additionalDetails': 'Try compacting the thread',
          'codexErrorInfo': 'contextWindowExceeded',
        },
      });
      // ????? codexErrorInfo????????????
      peer.emitNotification('error', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-live',
        'willRetry': false,
        'error': <String, Object?>{
          'message': 'Connection failed',
          'codexErrorInfo': <String, Object?>{
            'httpConnectionFailed': <String, Object?>{'httpStatusCode': 502},
          },
        },
      });
      await Future<void>.delayed(Duration.zero);

      final errors = events.whereType<AgentErrorEvent>().toList();
      expect(errors, hasLength(2));
      expect(errors[0].message, 'Context window exceeded');
      expect(errors[0].details, 'Try compacting the thread');
      expect(errors[0].code, 'contextWindowExceeded');
      expect(errors[0].willRetry, isTrue);
      expect(errors[0].sessionId, 'thread-1');
      expect(errors[0].turnId, 'turn-live');
      expect(errors[1].message, 'Connection failed');
      expect(errors[1].code, 'httpConnectionFailed');
      expect(errors[1].willRetry, isFalse);

      peer.emitNotification('error', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-live',
        'willRetry': false,
        'error': <String, Object?>{
          'message': 'Session budget exceeded',
          'codexErrorInfo': 'sessionBudgetExceeded',
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        events.whereType<AgentErrorEvent>().last.code,
        'sessionBudgetExceeded',
      );
    });

    test(
      'parses turn/completed terminal status, error, and duration',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.initialize();

        final events = <AgentEvent>[];
        final sub = provider.events.listen(events.add);
        addTearDown(sub.cancel);

        peer.emitNotification('turn/completed', <String, Object?>{
          'threadId': 'thread-1',
          'turn': <String, Object?>{
            'id': 'turn-failed',
            'status': 'failed',
            'durationMs': 5250,
            'items': <Object?>[],
            'error': <String, Object?>{
              'message': 'Model provider rejected the request',
              'codexErrorInfo': 'badRequest',
            },
          },
        });
        peer.emitNotification('turn/completed', <String, Object?>{
          'threadId': 'thread-1',
          'turn': <String, Object?>{
            'id': 'turn-interrupted',
            'status': 'interrupted',
            'items': <Object?>[],
          },
        });
        peer.emitNotification('turn/completed', <String, Object?>{
          'threadId': 'thread-1',
          'turn': <String, Object?>{
            'id': 'turn-ok',
            'status': 'completed',
            'items': <Object?>[],
          },
        });
        await Future<void>.delayed(Duration.zero);

        final completed = events.whereType<AgentTurnCompletedEvent>().toList();
        expect(completed, hasLength(3));
        expect(completed[0].turnId, 'turn-failed');
        expect(completed[0].status, AgentHistoryTurnStatus.failed);
        expect(
          completed[0].errorMessage,
          'Model provider rejected the request',
        );
        expect(completed[0].errorCode, 'badRequest');
        expect(completed[0].duration, const Duration(milliseconds: 5250));
        expect(completed[1].turnId, 'turn-interrupted');
        expect(completed[1].status, AgentHistoryTurnStatus.interrupted);
        expect(completed[1].errorMessage, isNull);
        expect(completed[1].errorCode, isNull);
        expect(completed[2].turnId, 'turn-ok');
        expect(completed[2].status, AgentHistoryTurnStatus.completed);
      },
    );

    test('maps serverOverloaded error notifications for live UI', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      await provider.initialize();

      final events = <AgentEvent>[];
      final sub = provider.events.listen(events.add);
      addTearDown(sub.cancel);

      peer.emitNotification('error', <String, Object?>{
        'threadId': 'thread-1',
        'turnId': 'turn-capacity',
        'willRetry': false,
        'error': <String, Object?>{
          'message':
              'Selected model is at capacity. Please try a different model.',
          'codexErrorInfo': 'serverOverloaded',
        },
      });
      await Future<void>.delayed(Duration.zero);

      final error = events.whereType<AgentErrorEvent>().single;
      expect(error.code, 'serverOverloaded');
      expect(error.willRetry, isFalse);
      expect(error.message, contains('at capacity'));
      expect(error.sessionId, 'thread-1');
      expect(error.turnId, 'turn-capacity');
    });

    test(
      'overlays thread/read failed status onto local session history',
      () async {
        final peer = _FakeJsonRpcPeer(
          threadReadResponseProvider: (params) async {
            return <String, Object?>{
              'thread': <String, Object?>{
                'id': 'thread-capacity',
                'turns': <Object?>[
                  <String, Object?>{
                    'id': 'turn-capacity',
                    'status': 'failed',
                    'items': <Object?>[],
                    'error': <String, Object?>{
                      'message':
                          'Selected model is at capacity. Please try a different model.',
                      'codexErrorInfo': 'serverOverloaded',
                    },
                  },
                ],
              },
            };
          },
        );
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final sessionFile = await _writeJsonlFile(<Object?>[
          <String, Object?>{
            'timestamp': '2026-08-05T03:19:15.000Z',
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'task_started',
              'turn_id': 'turn-capacity',
              'started_at': 1785899955,
            },
          },
          <String, Object?>{
            'timestamp': '2026-08-05T03:19:16.000Z',
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'user_message',
              'message': 'Continue',
            },
          },
          <String, Object?>{
            'timestamp': '2026-08-05T03:31:55.000Z',
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'task_complete',
              'turn_id': 'turn-capacity',
              'completed_at': 1785900715,
              'duration_ms': 760000,
              'last_agent_message': null,
            },
          },
        ]);
        addTearDown(() => sessionFile.parent.delete(recursive: true));

        final history = await provider.readThreadHistory(
          threadId: 'thread-capacity',
          sessionPath: sessionFile.path,
        );

        expect(peer.requestMethods, contains('thread/read'));
        final turn = history.turns.single;
        expect(turn.id, 'turn-capacity');
        expect(turn.status, AgentHistoryTurnStatus.failed);
        expect(turn.errorMessage, contains('at capacity'));
        expect(turn.errorCode, 'serverOverloaded');
      },
    );

    test('keeps legacy flat error payloads readable', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      await provider.initialize();

      final events = <AgentEvent>[];
      final sub = provider.events.listen(events.add);
      addTearDown(sub.cancel);

      peer.emitNotification('error', <String, Object?>{
        'threadId': 'thread-1',
        'message': 'Legacy failure',
        'details': 'Old-style details',
      });
      await Future<void>.delayed(Duration.zero);

      final error = events.whereType<AgentErrorEvent>().single;
      expect(error.message, 'Legacy failure');
      expect(error.details, 'Old-style details');
      expect(error.code, isNull);
      expect(error.willRetry, isNull);
    });

    test('reads configWarning summary field as the message', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      await provider.initialize();

      final events = <AgentEvent>[];
      final sub = provider.events.listen(events.add);
      addTearDown(sub.cancel);

      peer.emitNotification('configWarning', <String, Object?>{
        'summary': 'Unknown config key `modle`',
        'details': 'Did you mean `model`?',
        'path': '/Users/dev/.codex/config.toml',
      });
      await Future<void>.delayed(Duration.zero);

      final warning = events.whereType<AgentErrorEvent>().single;
      expect(warning.message, 'Unknown config key `modle`');
      expect(warning.details, 'Did you mean `model`?');
    });

    test(
      'parses item_completed plan payloads from local session jsonl',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final sessionFile = await _writeJsonlFile(<Object?>[
          <String, Object?>{
            'timestamp': '2026-07-05T07:38:30.000Z',
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'task_started',
              'turn_id': 'turn-plan',
              'started_at': '2026-07-05T07:38:30.000Z',
            },
          },
          <String, Object?>{
            'timestamp': '2026-07-05T07:38:35.382Z',
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'item_completed',
              'thread_id': 'thread-1',
              'turn_id': 'turn-plan',
              'item': <String, Object?>{
                'type': 'Plan',
                'id': 'turn-plan-plan',
                'text': '# Summary\n\n- First item',
              },
            },
          },
          <String, Object?>{
            'timestamp': '2026-07-05T07:38:36.000Z',
            'type': 'event_msg',
            'payload': <String, Object?>{
              'type': 'task_complete',
              'turn_id': 'turn-plan',
              'completed_at': '2026-07-05T07:38:36.000Z',
              'duration_ms': 6000,
            },
          },
        ]);
        addTearDown(() => sessionFile.parent.delete(recursive: true));

        final history = await provider.readThreadHistory(
          threadId: 'thread-1',
          sessionPath: sessionFile.path,
        );

        expect(history.turns, hasLength(1));
        final turn = history.turns.single;
        expect(turn.entries, hasLength(1));
        final plan = turn.entries.single as AgentHistoryMessageEntry;
        expect(plan.role, AgentMessageRole.agent);
        expect(plan.text, '# Summary\n\n- First item');
        expect(plan.status, AgentMessageStatus.completed);

        await provider.dispose();
      },
    );

    test('coalesces concurrent provider initialization', () async {
      final peer = _FakeJsonRpcPeer(startCompleter: Completer<void>());
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      final firstList = provider.listThreads(
        query: const AgentThreadListQuery(projectPath: '/repo', limit: 5),
      );
      final secondList = provider.listThreads(
        query: const AgentThreadListQuery(projectPath: '/repo', limit: 5),
      );

      await Future<void>.delayed(Duration.zero);
      expect(peer.startCalls, 1);
      expect(peer.requestMethods, isEmpty);

      peer.completeStart();
      final results = await Future.wait<AgentThreadPage>(
        <Future<AgentThreadPage>>[firstList, secondList],
      );

      expect(results, hasLength(2));
      expect(peer.startCalls, 1);
      expect(
        peer.requestMethods.where((method) => method == 'initialize'),
        hasLength(1),
      );
      expect(
        peer.requestMethods.where((method) => method == 'thread/list'),
        hasLength(2),
      );
      expect(peer.notificationsSent, <String>['initialized']);
      await provider.dispose();
    });

    test('fetches model list on demand and emits event', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final sub = provider.events.listen(events.add);
      addTearDown(sub.cancel);
      addTearDown(provider.dispose);

      await provider.listModels();
      await Future<void>.delayed(Duration.zero);

      expect(
        peer.requestMethods.where((method) => method == 'model/list'),
        hasLength(1),
      );
      final modelEvent = events.whereType<AgentModelListEvent>().single;
      expect(modelEvent.models.models, hasLength(2));
      final defaultModel = modelEvent.models.models.first;
      expect(defaultModel.id, 'gpt-5.5');
      expect(defaultModel.displayName, 'GPT-5.5');
      expect(defaultModel.isDefault, isTrue);
      expect(defaultModel.supportedReasoningEfforts, hasLength(3));
      expect(defaultModel.defaultReasoningEffort, 'medium');
      expect(defaultModel.serviceTiers, hasLength(1));
      expect(defaultModel.serviceTiers.first.id, 'priority');
      expect(defaultModel.serviceTiers.first.name, 'Fast');
    });

    test(
      'ignores local MCP transport stderr when MCP app is not running',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final sub = provider.events.listen(events.add);
        addTearDown(sub.cancel);
        addTearDown(provider.dispose);

        await provider.initialize();
        peer.emitStderr(
          'mrmcp::transport::worker worker quit with fatal: '
          'Transport channel closed, when Client(HttpRequest(HttpRequest('
          '"http/request failed: error sending request for url '
          '(http://127.0.0.1:64342/stream)")))',
        );
        peer.emitStderr(
          '[2m2026-07-09T03:10:26.498446Z[0m [31mERROR[0m '
          '[2mrmcp::transport::worker[0m [2m:[0m worker quit with fatal: '
          'Transport channel closed, when UnexpectedServerResponse('
          '"HTTP 404: 404 Not Found")',
        );
        await Future<void>.delayed(Duration.zero);

        expect(events.whereType<AgentErrorEvent>(), isEmpty);
      },
    );

    test('keeps non-MCP stderr diagnostic-only', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final sub = provider.events.listen(events.add);
      addTearDown(sub.cancel);
      addTearDown(provider.dispose);

      await provider.initialize();
      peer
        ..emitStderr(
          '\u001b[31mERROR\u001b[0m codex_core::tools::router: Exit code: 1',
        )
        ..emitStderr('\u001b[31;1mGet-CimInstance: ????\u001b[0m');
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<AgentErrorEvent>(), isEmpty);
    });

    test('listModels returns cached list without extra request', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      await provider.initialize();
      final firstList = await provider.listModels();
      final secondList = await provider.listModels();

      expect(firstList.models, hasLength(2));
      expect(secondList.models, hasLength(2));
      expect(
        peer.requestMethods.where((method) => method == 'model/list'),
        hasLength(1),
      );

      await provider.refreshModels();
      expect(
        peer.requestMethods.where((method) => method == 'model/list'),
        hasLength(2),
      );
    });

    test('paginates and caches the complete model catalog', () async {
      final peer = _FakeJsonRpcPeer(
        modelListResponseProvider: (params) {
          final map = params! as Map<String, Object?>;
          if (map['cursor'] == null) {
            return <String, Object?>{
              'data': <Object?>[
                <String, Object?>{
                  'id': 'model-a',
                  'model': 'model-a',
                  'displayName': 'Model A',
                },
              ],
              'nextCursor': 'page-2',
            };
          }
          return <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': 'model-a',
                'model': 'model-a',
                'displayName': 'Model A',
              },
              <String, Object?>{
                'id': 'model-b',
                'model': 'model-b',
                'displayName': 'Model B',
              },
            ],
            'nextCursor': null,
          };
        },
      );
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final models = await provider.listModels(limit: 1);
      final cached = await provider.listModels(limit: 1);

      expect(models.models.map((model) => model.id), <String>[
        'model-a',
        'model-b',
      ]);
      expect(cached.models, hasLength(2));
      expect(
        peer.requestMethods.where((method) => method == 'model/list'),
        hasLength(2),
      );
      expect(
        peer.requestParams.whereType<Map<String, Object?>>().last['cursor'],
        'page-2',
      );
    });

    test('retries model discovery after a failed request', () async {
      var attempts = 0;
      final peer = _FakeJsonRpcPeer(
        modelListResponseProvider: (_) {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('model endpoint unavailable');
          }
          return <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': 'model-after-retry',
                'model': 'model-after-retry',
                'displayName': 'Model after retry',
              },
            ],
            'nextCursor': null,
          };
        },
      );
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      await expectLater(provider.listModels(), throwsStateError);
      final models = await provider.listModels();

      expect(models.models.single.id, 'model-after-retry');
      expect(attempts, 2);
      expect(
        peer.requestMethods.where((method) => method == 'model/list'),
        hasLength(2),
      );
    });

    test(
      'keeps previous thread subscribed when starting another session',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
        );
        await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
        );

        expect(
          peer.requestMethods.where((method) => method == 'thread/start'),
          hasLength(2),
        );
        expect(peer.requestMethods, isNot(contains('thread/unsubscribe')));
      },
    );

    test(
      'keeps previous thread subscribed when resuming another session',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
        );
        await provider.resumeSession(
          'thread-2',
          context: const AgentContext(projectPath: '/repo'),
        );

        expect(
          peer.requestMethods,
          containsAll(<String>['thread/start', 'thread/resume']),
        );
        expect(peer.requestMethods, isNot(contains('thread/unsubscribe')));
      },
    );

    test('unsubscribeThread sends thread/unsubscribe', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      await provider.unsubscribeThread('thread-9');

      expect(peer.requestMethods, contains('thread/unsubscribe'));
      final unsubscribeIndex = peer.requestMethods.indexOf(
        'thread/unsubscribe',
      );
      final params =
          peer.requestParams[unsubscribeIndex]! as Map<String, Object?>;
      expect(params['threadId'], 'thread-9');
    });

    test('does not unsubscribe when resuming the same session id', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
      );
      await provider.resumeSession(
        'thread-1',
        context: const AgentContext(projectPath: '/repo'),
      );

      expect(peer.requestMethods, isNot(contains('thread/unsubscribe')));
    });

    test('encodes localImage inputs in turn/start', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
      );
      await provider.sendMessage(
        session: session,
        inputs: const <AgentUserInput>[
          AgentUserInput.text('describe this'),
          AgentUserInput.localImage(path: r'D:\tmp\shot.png'),
        ],
        context: const AgentContext(projectPath: '/repo'),
      );

      final turnStartIndex = peer.requestMethods.indexOf('turn/start');
      expect(turnStartIndex, isNot(-1));
      final params =
          peer.requestParams[turnStartIndex]! as Map<String, Object?>;
      expect(params['input'], <Object?>[
        <String, Object?>{'type': 'text', 'text': 'describe this'},
        <String, Object?>{'type': 'localImage', 'path': r'D:\tmp\shot.png'},
      ]);
    });

    test(
      'restores custom team-safe profile from config and encodes permissions',
      () async {
        final config = AgentProviderConfig.defaultCodex
            .withPermissionPreference('team-safe');
        // V2 round-trip 只保留 optionId；自定义 profile 不得变成 :workspace。
        final decoded = AgentProviderSettingsCodec(
          migrationRegistry: AgentProviderPermissionMigrationRegistry(
            <AgentProviderKind, AgentProviderPermissionPreferenceMigrator>{
              AgentProviderKind.codexAppServer:
                  const CodexPermissionPreferenceMigrator(),
            },
          ),
        ).decodeProvider(config.toJson());
        expect(decoded, isNotNull);
        expect(decoded!.selectedPermissionOptionId, 'team-safe');
        expect(decoded.resolvedPermissionOptionId, 'team-safe');

        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: decoded,
          peer: peer,
        );
        addTearDown(provider.dispose);

        await provider.sendMessage(
          session: const AgentSession(
            id: 'thread-team-safe',
            providerId: defaultAgentProviderId,
          ),
          message: 'hello',
          context: const AgentContext(projectPath: '/repo'),
          clientUserMessageId: 'client-team-safe',
        );

        final turnStartIndex = peer.requestMethods.indexOf('turn/start');
        expect(peer.requestParams[turnStartIndex], <String, Object?>{
          'threadId': 'thread-team-safe',
          'input': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'hello'},
          ],
          'cwd': '/repo',
          'approvalPolicy': 'on-request',
          'permissions': 'team-safe',
          'clientUserMessageId': 'client-team-safe',
        });
      },
    );

    test('keeps legacy turn/start params unchanged without mode', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      provider.updateModelSelection(
        const AgentModelSelection(
          modelId: 'gpt-5.4-mini',
          reasoningEffort: 'high',
          serviceTierId: 'priority',
        ),
      );

      await provider.sendMessage(
        session: const AgentSession(
          id: 'thread-legacy',
          providerId: defaultAgentProviderId,
        ),
        message: 'hello',
        context: const AgentContext(projectPath: '/repo'),
        clientUserMessageId: 'client-legacy',
        configuration: const AgentTurnConfiguration(
          permissionSnapshot: AgentPermissionRequestSnapshot.resolved(
            selection: AgentPermissionSelection(
              optionId: ':danger-full-access',
            ),
            source: AgentPermissionRequestSource.threadEffective,
          ),
        ),
      );

      final turnStartIndex = peer.requestMethods.indexOf('turn/start');
      expect(peer.requestParams[turnStartIndex], <String, Object?>{
        'threadId': 'thread-legacy',
        'input': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'hello'},
        ],
        'cwd': '/repo',
        'model': 'gpt-5.4-mini',
        'effort': 'high',
        'serviceTier': 'priority',
        'approvalPolicy': 'never',
        // Full access 已关联内置 profile，优先下发 permissions。
        'permissions': ':danger-full-access',
        'clientUserMessageId': 'client-legacy',
      });
    });

    test(
      'permission apply never mutates the config fallback used by requests',
      () async {
        final config = AgentProviderConfig.defaultCodex
            .withPermissionPreference(':workspace');
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: config,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final applied = await provider.permissionPolicy
            .applyPermissionSelection(
              const AgentPermissionSelection(optionId: ':danger-full-access'),
            );
        expect(applied.normalizedSelection.optionId, ':danger-full-access');

        await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
        );
        await provider.sendMessage(
          session: const AgentSession(
            id: 'fallback-thread',
            providerId: defaultAgentProviderId,
          ),
          message: 'uses config fallback',
          context: const AgentContext(projectPath: '/repo'),
        );

        final threadParams =
            peer.requestParams[peer.requestMethods.indexOf('thread/start')]!
                as Map<String, Object?>;
        final turnParams =
            peer.requestParams[peer.requestMethods.indexOf('turn/start')]!
                as Map<String, Object?>;
        expect(threadParams['permissions'], ':workspace');
        expect(turnParams['permissions'], ':workspace');
        expect(threadParams['approvalPolicy'], 'on-request');
        expect(turnParams['approvalPolicy'], 'on-request');
      },
    );

    test(
      'concurrent turns keep immutable permission snapshots per thread',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex.withPermissionPreference(
            ':workspace',
          ),
          peer: peer,
        );
        addTearDown(provider.dispose);
        const threadA = AgentSession(
          id: 'thread-a',
          providerId: defaultAgentProviderId,
        );
        const threadB = AgentSession(
          id: 'thread-b',
          providerId: defaultAgentProviderId,
        );
        const snapshotA = AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: 'team-safe'),
          source: AgentPermissionRequestSource.threadEffective,
        );
        const snapshotB = AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: ':danger-full-access'),
          source: AgentPermissionRequestSource.threadEffective,
        );

        await Future.wait(<Future<AgentTurn>>[
          provider.sendMessage(
            session: threadA,
            message: 'A',
            context: const AgentContext(projectPath: '/repo'),
            configuration: const AgentTurnConfiguration(
              permissionSnapshot: snapshotA,
            ),
          ),
          provider.sendMessage(
            session: threadB,
            message: 'B',
            context: const AgentContext(projectPath: '/repo'),
            configuration: const AgentTurnConfiguration(
              permissionSnapshot: snapshotB,
            ),
          ),
        ]);

        final turnParams = <Map<String, Object?>>[
          for (var index = 0; index < peer.requestMethods.length; index++)
            if (peer.requestMethods[index] == 'turn/start')
              peer.requestParams[index]! as Map<String, Object?>,
        ];
        final byThread = <String, Map<String, Object?>>{
          for (final params in turnParams)
            params['threadId']! as String: params,
        };
        expect(byThread['thread-a']?['permissions'], 'team-safe');
        expect(byThread['thread-a']?['approvalPolicy'], 'on-request');
        expect(byThread['thread-b']?['permissions'], ':danger-full-access');
        expect(byThread['thread-b']?['approvalPolicy'], 'never');
      },
    );

    test(
      'encodes Plan mode without conflicting top-level model settings',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        provider.updateModelSelection(
          const AgentModelSelection(
            modelId: 'legacy-model',
            reasoningEffort: 'high',
            serviceTierId: 'priority',
          ),
        );
        await provider.sendMessage(
          session: const AgentSession(
            id: 'thread-plan',
            providerId: defaultAgentProviderId,
          ),
          inputs: const <AgentUserInput>[
            AgentUserInput.text(
              'inspect @main.dart',
              textElements: <AgentTextElement>[
                AgentTextElement(start: 8, end: 17, placeholder: 'main.dart'),
              ],
            ),
            AgentUserInput.localImage(path: r'D:\tmp\shot.png', detail: 'high'),
            AgentUserInput.mention(
              name: 'main.dart',
              path: '/repo/lib/main.dart',
            ),
          ],
          context: const AgentContext(projectPath: '/repo'),
          clientUserMessageId: 'client-plan',
          configuration: AgentTurnConfiguration(
            conversationMode: AgentConversationModeSelection(
              modeId: AgentConversationModeId.plan,
              effectiveModelId: 'gpt-5.4',
              effectiveReasoningEffort: 'medium',
            ),
          ),
        );

        final turnStartIndex = peer.requestMethods.indexOf('turn/start');
        expect(peer.requestParams[turnStartIndex], <String, Object?>{
          'threadId': 'thread-plan',
          'input': <Object?>[
            <String, Object?>{
              'type': 'text',
              'text': 'inspect @main.dart',
              'text_elements': <Object?>[
                <String, Object?>{
                  'byteRange': <int>[8, 17],
                  'placeholder': 'main.dart',
                },
              ],
            },
            <String, Object?>{
              'type': 'localImage',
              'path': r'D:\tmp\shot.png',
              'detail': 'high',
            },
            <String, Object?>{
              'type': 'mention',
              'name': 'main.dart',
              'path': '/repo/lib/main.dart',
            },
          ],
          'cwd': '/repo',
          'collaborationMode': <String, Object?>{
            'mode': 'plan',
            'settings': <String, Object?>{
              'model': 'gpt-5.4',
              'reasoning_effort': 'medium',
              'developer_instructions': null,
            },
          },
          'serviceTier': 'priority',
          'approvalPolicy': 'on-request',
          'permissions': ':workspace',
          'clientUserMessageId': 'client-plan',
        });
        final params =
            peer.requestParams[turnStartIndex]! as Map<String, Object?>;
        expect(params.containsKey('model'), isFalse);
        expect(params.containsKey('effort'), isFalse);
        expect(params.containsKey('sandboxPolicy'), isFalse);
      },
    );

    test('encodes explicit Default mode after Plan mode', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      const session = AgentSession(
        id: 'thread-mode-switch',
        providerId: defaultAgentProviderId,
      );

      await provider.sendMessage(
        session: session,
        message: 'plan first',
        context: const AgentContext(projectPath: '/repo'),
        configuration: AgentTurnConfiguration(
          conversationMode: AgentConversationModeSelection(
            modeId: AgentConversationModeId.plan,
            effectiveModelId: 'gpt-5.4',
            effectiveReasoningEffort: 'medium',
          ),
        ),
      );
      await provider.sendMessage(
        session: session,
        message: 'return to default',
        context: const AgentContext(projectPath: '/repo'),
        configuration: AgentTurnConfiguration(
          conversationMode: AgentConversationModeSelection(
            modeId: AgentConversationModeId.defaultMode,
            effectiveModelId: 'gpt-5.4',
          ),
        ),
      );

      final turnStartIndex = peer.requestMethods.lastIndexOf('turn/start');
      final params =
          peer.requestParams[turnStartIndex]! as Map<String, Object?>;
      expect(params['collaborationMode'], <String, Object?>{
        'mode': 'default',
        'settings': <String, Object?>{
          'model': 'gpt-5.4',
          'reasoning_effort': null,
          'developer_instructions': null,
        },
      });
      expect(params.containsKey('model'), isFalse);
      expect(params.containsKey('effort'), isFalse);
    });

    test(
      'turn/start carries permission selection and clientUserMessageId',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        const permissionSnapshot = AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: ':danger-full-access'),
          source: AgentPermissionRequestSource.threadEffective,
        );

        final session = await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
          permissionSnapshot: permissionSnapshot,
        );
        final threadStartIndex = peer.requestMethods.indexOf('thread/start');
        expect(threadStartIndex, isNot(-1));
        final threadParams =
            peer.requestParams[threadStartIndex]! as Map<String, Object?>;
        expect(threadParams['approvalPolicy'], 'never');
        expect(threadParams['permissions'], ':danger-full-access');
        expect(threadParams.containsKey('sandbox'), isFalse);

        await provider.sendMessage(
          session: session,
          message: 'hello',
          context: const AgentContext(projectPath: '/repo'),
          clientUserMessageId: 'client-msg-1',
          configuration: const AgentTurnConfiguration(
            permissionSnapshot: permissionSnapshot,
          ),
        );

        final turnStartIndex = peer.requestMethods.indexOf('turn/start');
        expect(turnStartIndex, isNot(-1));
        final params =
            peer.requestParams[turnStartIndex]! as Map<String, Object?>;
        expect(params['approvalPolicy'], 'never');
        expect(params['permissions'], ':danger-full-access');
        expect(params.containsKey('sandboxPolicy'), isFalse);
        expect(params['clientUserMessageId'], 'client-msg-1');
      },
    );

    test(
      'prefers permissions profile over legacy sandbox fields when available',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        const permissionSnapshot = AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: ':workspace'),
          source: AgentPermissionRequestSource.threadEffective,
        );

        final session = await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
          permissionSnapshot: permissionSnapshot,
        );
        final threadStartIndex = peer.requestMethods.indexOf('thread/start');
        final threadParams =
            peer.requestParams[threadStartIndex]! as Map<String, Object?>;
        expect(threadParams['permissions'], ':workspace');
        expect(threadParams.containsKey('sandbox'), isFalse);

        await provider.sendMessage(
          session: session,
          message: 'hello',
          context: const AgentContext(projectPath: '/repo'),
          configuration: const AgentTurnConfiguration(
            permissionSnapshot: permissionSnapshot,
          ),
        );

        final turnStartIndex = peer.requestMethods.indexOf('turn/start');
        final turnParams =
            peer.requestParams[turnStartIndex]! as Map<String, Object?>;
        expect(turnParams['permissions'], ':workspace');
        expect(turnParams.containsKey('sandboxPolicy'), isFalse);
      },
    );

    test('turn/steer requires active expectedTurnId and omits cwd', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
      );
      final turn = await provider.sendMessage(
        session: session,
        message: 'start',
        context: const AgentContext(projectPath: '/repo'),
      );
      await provider.steerTurn(
        session: session,
        expectedTurnId: turn.id,
        message: 'continue',
        context: const AgentContext(projectPath: '/different-repo'),
      );

      final index = peer.requestMethods.indexOf('turn/steer');
      final params = peer.requestParams[index]! as Map<String, Object?>;
      expect(params['expectedTurnId'], turn.id);
      expect(params.containsKey('cwd'), isFalse);
      await expectLater(
        provider.steerTurn(
          session: session,
          expectedTurnId: 'stale-turn',
          message: 'stale',
          context: const AgentContext(projectPath: '/repo'),
        ),
        throwsStateError,
      );
    });

    test(
      'normalizes removed on-failure approval policy before encoding',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
          permissionSnapshot: const AgentPermissionRequestSnapshot.resolved(
            selection: AgentPermissionSelection(optionId: ':workspace'),
            source: AgentPermissionRequestSource.threadEffective,
          ),
        );
        final threadIndex = peer.requestMethods.indexOf('thread/start');
        final threadParams =
            peer.requestParams[threadIndex]! as Map<String, Object?>;
        expect(threadParams['approvalPolicy'], 'on-request');
      },
    );

    test(
      'maps initialize response into version-gated runtime capabilities',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        await provider.initialize();

        expect(provider.runtimeInfo?.cliVersion, '0.144.5');
        expect(provider.runtimeInfo?.runtimeId, isNotEmpty);
        expect(provider.runtimeInfo?.connectionEpoch, 1);
        expect(provider.runtimeInfo?.experimentalApiEnabled, isTrue);
        expect(provider.lifecycleState, AgentProviderLifecycleState.ready);
        expect(
          provider.runtimeInfo?.compatibilityStatus,
          AgentRuntimeCompatibilityStatus.supported,
        );
        expect(provider.capabilities.canForkThreadAtTurn, isTrue);
      },
    );

    test('dispose closes pending approvals and rejects new RPC', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);

      await provider.initialize();
      peer.emitServerRequest(
        id: 'approval-closing',
        method: 'item/commandExecution/requestApproval',
        params: <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'command': 'dart format .',
        },
      );
      await Future<void>.delayed(Duration.zero);

      final firstDispose = provider.dispose();
      final secondDispose = provider.dispose();
      expect(identical(firstDispose, secondDispose), isTrue);
      await firstDispose;

      expect(provider.lifecycleState, AgentProviderLifecycleState.closed);
      final resolved = events.whereType<AgentPermissionResolvedEvent>().single;
      expect(resolved.requestId, 'approval-closing');
      expect(resolved.raw['reason'], 'connectionClosed');
      final requestCount = peer.requestMethods.length;
      await expectLater(
        provider.listThreads(
          query: const AgentThreadListQuery(projectPath: '/repo', limit: 20),
        ),
        throwsA(isA<ProviderOperationSchedulerClosedException>()),
      );
      expect(peer.requestMethods, hasLength(requestCount));
    });

    test('unexpected connection close clears pending approval UI', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);

      await provider.initialize();
      peer.emitServerRequest(
        id: 'approval-disconnected',
        method: 'item/commandExecution/requestApproval',
        params: <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'command': 'flutter test',
        },
      );
      await Future<void>.delayed(Duration.zero);

      await peer.simulateUnexpectedExit();
      await Future<void>.delayed(Duration.zero);

      expect(provider.lifecycleState, AgentProviderLifecycleState.failed);
      final resolved = events.whereType<AgentPermissionResolvedEvent>().single;
      expect(resolved.requestId, 'approval-disconnected');
      expect(resolved.raw['reason'], 'connectionClosed');
      expect(
        events.whereType<AgentStatusEvent>().last.status.state,
        AgentProviderConnectionState.unavailable,
      );
    });

    test('keeps fork-at-turn closed for older Codex runtime', () async {
      final peer = _FakeJsonRpcPeer(
        initializeResponse: const <String, Object?>{
          'codexHome': '/home/test/.codex',
          'platformFamily': 'unix',
          'platformOs': 'linux',
          'userAgent': 'codex_cli_rs/0.144.4',
        },
      );
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      await provider.initialize();

      expect(
        provider.runtimeInfo?.compatibilityStatus,
        AgentRuntimeCompatibilityStatus.supportedWithLimitedCapabilities,
      );
      expect(provider.capabilities.canForkThreadAtTurn, isFalse);
      await expectLater(
        provider.forkThread(
          threadId: 'thread-1',
          context: const AgentContext(projectPath: '/repo'),
          boundary: const AgentForkThroughTurn('turn-1'),
        ),
        throwsUnsupportedError,
      );
    });

    test('encodes mention inputs in turn/start', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
      );
      await provider.sendMessage(
        session: session,
        inputs: const <AgentUserInput>[
          AgentUserInput.text(
            'look at @main.dart',
            textElements: <AgentTextElement>[
              AgentTextElement(start: 8, end: 17, placeholder: 'main.dart'),
            ],
          ),
          AgentUserInput.mention(
            name: 'main.dart',
            path: '/repo/lib/main.dart',
          ),
        ],
        context: const AgentContext(projectPath: '/repo'),
      );

      final turnStartIndex = peer.requestMethods.indexOf('turn/start');
      final params =
          peer.requestParams[turnStartIndex]! as Map<String, Object?>;
      expect(params['input'], <Object?>[
        <String, Object?>{
          'type': 'text',
          'text': 'look at @main.dart',
          'text_elements': <Object?>[
            <String, Object?>{
              'byteRange': <int>[8, 17],
              'placeholder': 'main.dart',
            },
          ],
        },
        <String, Object?>{
          'type': 'mention',
          'name': 'main.dart',
          'path': '/repo/lib/main.dart',
        },
      ]);
    });

    test('encodes skill inputs in turn/start', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
      );
      await provider.sendMessage(
        session: session,
        inputs: const <AgentUserInput>[
          AgentUserInput.text(r'$skill-creator Add a skill'),
          AgentUserInput.skill(
            name: 'skill-creator',
            path: '/skills/skill-creator/SKILL.md',
          ),
        ],
        context: const AgentContext(projectPath: '/repo'),
      );

      final turnStartIndex = peer.requestMethods.indexOf('turn/start');
      final params =
          peer.requestParams[turnStartIndex]! as Map<String, Object?>;
      expect(params['input'], <Object?>[
        <String, Object?>{
          'type': 'text',
          'text': r'$skill-creator Add a skill',
        },
        <String, Object?>{
          'type': 'skill',
          'name': 'skill-creator',
          'path': '/skills/skill-creator/SKILL.md',
        },
      ]);
    });

    test('lists skills and emits skillsChanged', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      expect(provider.capabilities.supportsSkillInput, isTrue);
      expect(provider, isA<AgentSkillsCatalogProvider>());

      final changed = <void>[];
      final subscription = provider.skillsChanged.listen(changed.add);
      addTearDown(subscription.cancel);

      final catalog = await provider.listSkills(
        cwds: const <String>['/repo'],
        forceReload: true,
      );
      expect(peer.requestMethods, contains('skills/list'));
      expect(catalog.allSkills.single.name, 'skill-creator');
      expect(catalog.allSkills.single.enabled, isTrue);

      peer.emitNotification('skills/changed', const <String, Object?>{});
      await Future<void>.delayed(Duration.zero);
      expect(changed, hasLength(1));
    });

    test('maps autoApprovalReview notifications', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.initialize();
      peer.emitNotification(
        'item/autoApprovalReview/started',
        <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'reviewId': 'review-1',
          'startedAtMs': 1,
          'action': <String, Object?>{
            'type': 'command',
            'command': 'ls',
            'cwd': '/repo',
            'source': 'shell',
          },
          'review': <String, Object?>{'status': 'inProgress'},
        },
      );
      peer.emitNotification(
        'item/autoApprovalReview/completed',
        <String, Object?>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'reviewId': 'review-1',
          'startedAtMs': 1,
          'completedAtMs': 2,
          'decisionSource': 'agent',
          'action': <String, Object?>{
            'type': 'command',
            'command': 'ls',
            'cwd': '/repo',
            'source': 'shell',
          },
          'review': <String, Object?>{
            'status': 'denied',
            'rationale': 'risky',
            'riskLevel': 'high',
          },
        },
      );
      await Future<void>.delayed(Duration.zero);

      final reviews = events.whereType<AgentAutoApprovalReviewEvent>().toList();
      expect(reviews, hasLength(2));
      expect(reviews.first.status, 'inProgress');
      expect(reviews.last.status, 'denied');
      expect(reviews.last.rationale, 'risky');

      await provider.approveGuardianDeniedAction(
        threadId: 'thread-1',
        event: reviews.last.raw,
      );
      expect(
        peer.requestMethods,
        contains('thread/approveGuardianDeniedAction'),
      );
      await subscription.cancel();
    });

    test('updateModelSelection overrides turn/start params', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      provider.updateModelSelection(
        const AgentModelSelection(
          modelId: 'gpt-5.4-mini',
          reasoningEffort: 'high',
          serviceTierId: 'priority',
        ),
      );

      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
      );
      await provider.sendMessage(
        session: session,
        message: 'hello',
        context: const AgentContext(projectPath: '/repo'),
      );

      final turnStartIndex = peer.requestMethods.indexOf('turn/start');
      expect(turnStartIndex, isNot(-1));
      final params = peer.requestParams[turnStartIndex] as Map<String, Object?>;
      expect(params['model'], 'gpt-5.4-mini');
      // ?????? `effort`,???? `reasoningEffort`?
      expect(params['effort'], 'high');
      expect(params.containsKey('reasoningEffort'), isFalse);
      expect(params['serviceTier'], 'priority');
    });

    test('falls back to config.defaultModel when selection is empty', () async {
      final config = AgentProviderConfig.defaultCodex.copyWith(
        defaultModel: 'gpt-5.5',
      );
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(config: config, peer: peer);
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
      );
      await provider.sendMessage(
        session: session,
        message: 'hello',
        context: const AgentContext(projectPath: '/repo'),
      );

      final turnStartIndex = peer.requestMethods.indexOf('turn/start');
      final params = peer.requestParams[turnStartIndex] as Map<String, Object?>;
      expect(params['model'], 'gpt-5.5');
      expect(params.containsKey('effort'), isFalse);
      expect(params.containsKey('serviceTier'), isFalse);
    });
  });
}

Future<Map<String, Object?>> _loadFileChangeFixture(String name) async {
  final value = jsonDecode(
    await File('test/fixtures/agent_file_change_evidence/$name').readAsString(),
  );
  return (value as Map).cast<String, Object?>();
}

Future<File> _writeJsonlFile(List<Object?> records) async {
  final directory = Directory.systemTemp.createTempSync('zeta_jsonl_');
  final file = File('${directory.path}/session.jsonl');
  final sink = file.openWrite();
  for (final record in records) {
    sink.writeln(jsonEncode(record));
  }
  await sink.close();
  return file;
}

class _FakeJsonRpcPeer implements JsonRpcPeer {
  _FakeJsonRpcPeer({
    this._startCompleter,
    this.modelListResponseProvider,
    this.collaborationModeListResponseProvider,
    this.threadReadResponseProvider,
    this.accountRateLimitsResponse,
    this.initializeResponse = const <String, Object?>{
      'codexHome': '/home/test/.codex',
      'platformFamily': 'unix',
      'platformOs': 'linux',
      'userAgent': 'codex_cli_rs/0.144.5',
    },
  });

  final StreamController<JsonRpcNotification> _notifications =
      StreamController<JsonRpcNotification>.broadcast();
  final StreamController<JsonRpcRequest> _serverRequests =
      StreamController<JsonRpcRequest>.broadcast();
  final StreamController<String> _stderrLines =
      StreamController<String>.broadcast();
  final StreamController<JsonRpcProtocolException> _protocolErrors =
      StreamController<JsonRpcProtocolException>.broadcast();

  final List<String> requestMethods = <String>[];
  final List<Object?> requestParams = <Object?>[];
  final List<String> notificationsSent = <String>[];
  final Map<Object, Object?> responses = <Object, Object?>{};
  final Map<Object, JsonRpcError> errorResponses = <Object, JsonRpcError>{};
  final Map<String, List<Completer<void>>> _requestGates =
      <String, List<Completer<void>>>{};
  final Completer<void>? _startCompleter;
  final Map<String, Object?> initializeResponse;
  final Object? Function(Object? params)? modelListResponseProvider;
  final FutureOr<Object?> Function(Object? params)?
  collaborationModeListResponseProvider;
  final FutureOr<Object?> Function(Object? params)? threadReadResponseProvider;
  final Map<String, Object?>? accountRateLimitsResponse;
  int startCalls = 0;
  int _threadStartCount = 0;
  bool _closed = false;

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  @override
  Stream<JsonRpcRequest> get serverRequests => _serverRequests.stream;

  @override
  Stream<String> get stderrLines => _stderrLines.stream;

  @override
  Stream<JsonRpcProtocolException> get protocolErrors => _protocolErrors.stream;

  @override
  Future<void> start() async {
    startCalls += 1;
    await _startCompleter?.future;
  }

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requestMethods.add(method);
    requestParams.add(params);
    final gates = _requestGates[method];
    if (gates != null && gates.isNotEmpty) {
      await gates.removeAt(0).future;
    }
    final paramsMap = params is Map<String, Object?>
        ? params
        : const <String, Object?>{};
    if (method == 'collaborationMode/list') {
      final responseProvider = collaborationModeListResponseProvider;
      if (responseProvider != null) {
        return await responseProvider(params);
      }
      return _conversationModeListResponse();
    }
    if (method == 'thread/read') {
      final responseProvider = threadReadResponseProvider;
      if (responseProvider != null) {
        return await responseProvider(params);
      }
    }
    return switch (method) {
      'initialize' => initializeResponse,
      'thread/start' => () {
        _threadStartCount += 1;
        return <String, Object?>{
          'thread': <String, Object?>{'id': 'thread-$_threadStartCount'},
        };
      }(),
      'thread/resume' => <String, Object?>{
        'thread': <String, Object?>{'id': paramsMap['threadId'] ?? 'thread-1'},
      },
      'thread/unsubscribe' => <String, Object?>{'status': 'unsubscribed'},
      'thread/name/set' => <String, Object?>{},
      'thread/archive' => <String, Object?>{},
      'thread/unarchive' => <String, Object?>{},
      'thread/delete' => <String, Object?>{},
      'thread/compact/start' => <String, Object?>{},
      'thread/approveGuardianDeniedAction' => <String, Object?>{},
      'permissionProfile/list' => <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': ':workspace',
            'allowed': true,
            'description': 'Workspace write',
          },
        ],
      },
      'thread/fork' => <String, Object?>{
        'thread': <String, Object?>{
          'id': 'forked-thread',
          'name': 'Forked',
          'cwd': paramsMap['cwd'] ?? '/repo',
          'preview': 'Forked',
          'createdAt': 100,
          'updatedAt': 120,
          'status': <String, Object?>{'type': 'idle'},
          'turns': <Object?>[],
        },
        'approvalPolicy': 'on-request',
        'approvalsReviewer': 'user',
        'cwd': paramsMap['cwd'] ?? '/repo',
        'model': 'gpt-5.5',
        'modelProvider': 'openai',
        'sandbox': 'workspace-write',
      },
      'thread/list' => <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'thread-1',
            'cwd': '/repo',
            'path': '/tmp/thread-1.jsonl',
            'preview': 'Refactor provider',
            'createdAt': 100,
            'updatedAt': 120,
            'recencyAt': 130,
            'status': <String, Object?>{'type': 'idle'},
          },
        ],
        'nextCursor': 'cursor-2',
      },
      'thread/read' => <String, Object?>{
        'thread': <String, Object?>{
          'id': 'thread-1',
          'turns': <Object?>[
            <String, Object?>{
              'id': 'turn-1',
              'status': 'completed',
              'startedAt': 1783144800,
              'completedAt': 1783144803,
              'durationMs': 3000,
              'cwd': '/repo',
              'model': 'gpt-5',
              'modelContextWindow': 258400,
              'collaborationMode': 'Default',
              'items': <Object?>[
                <String, Object?>{
                  'type': 'userMessage',
                  'id': 'user-1',
                  'content': <Object?>[
                    <String, Object?>{'type': 'text', 'text': 'Hello Agent'},
                    <String, Object?>{
                      'type': 'localImage',
                      'path': '/tmp/hello.png',
                    },
                  ],
                },
                <String, Object?>{
                  'type': 'agentMessage',
                  'id': 'agent-1',
                  'text': 'Hello human',
                  'phase': 'commentary',
                  'status': 'completed',
                  'durationMs': 102000,
                },
                <String, Object?>{
                  'type': 'plan',
                  'id': 'plan-1',
                  'text': 'Check the project',
                },
                <String, Object?>{
                  'type': 'commandExecution',
                  'id': 'command-1',
                  'command': 'flutter test',
                  'cwd': '/repo',
                  'status': 'completed',
                  'aggregatedOutput': 'All good',
                },
                <String, Object?>{
                  'type': 'fileChange',
                  'id': 'file-1',
                  'status': 'completed',
                  'changes': <Object?>[
                    <String, Object?>{
                      'path': 'lib/main.dart',
                      'kind': 'update',
                    },
                  ],
                },
                <String, Object?>{
                  'type': 'webSearch',
                  'id': 'search-1',
                  'query': 'zeta design system',
                },
                <String, Object?>{
                  'type': 'enteredReviewMode',
                  'id': 'review-enter-1',
                  'review': 'Review branch diff',
                },
                <String, Object?>{
                  'type': 'contextCompaction',
                  'id': 'compact-1',
                },
              ],
            },
          ],
        },
      },
      'account/rateLimits/read' =>
        accountRateLimitsResponse ??
            <String, Object?>{
              'rateLimits': <String, Object?>{
                'planType': 'plus',
                'limitName': 'Codex',
                'primary': <String, Object?>{
                  'usedPercent': 36,
                  'resetsAt': 1783785600,
                  'windowDurationMins': 300,
                },
                'secondary': <String, Object?>{
                  'usedPercent': 72,
                  'resetsAt': 1784246400,
                  'windowDurationMins': 10080,
                },
                'credits': <String, Object?>{
                  'hasCredits': true,
                  'unlimited': false,
                  'balance': '12.50',
                },
              },
              'rateLimitResetCredits': <String, Object?>{
                'availableCount': 2,
                'credits': <Object?>[
                  <String, Object?>{'id': 'reset-credit-1'},
                ],
              },
            },
      'turn/start' => <String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      },
      'model/list' =>
        modelListResponseProvider?.call(params) ??
            <String, Object?>{
              'data': <Object?>[
                <String, Object?>{
                  'id': 'gpt-5.5',
                  'model': 'gpt-5.5',
                  'displayName': 'GPT-5.5',
                  'description': 'Frontier model',
                  'hidden': false,
                  'supportedReasoningEfforts': <Object?>[
                    <String, Object?>{
                      'reasoningEffort': 'low',
                      'description': 'Fast responses with lighter reasoning',
                    },
                    <String, Object?>{
                      'reasoningEffort': 'medium',
                      'description': 'Balances speed and reasoning depth',
                    },
                    <String, Object?>{
                      'reasoningEffort': 'high',
                      'description': 'Greater reasoning depth',
                    },
                  ],
                  'defaultReasoningEffort': 'medium',
                  'serviceTiers': <Object?>[
                    <String, Object?>{
                      'id': 'priority',
                      'name': 'Fast',
                      'description': '1.5x speed, increased usage',
                    },
                  ],
                  'defaultServiceTier': null,
                  'isDefault': true,
                },
                <String, Object?>{
                  'id': 'gpt-5.4-mini',
                  'model': 'gpt-5.4-mini',
                  'displayName': 'GPT-5.4-Mini',
                  'hidden': false,
                  'supportedReasoningEfforts': <Object?>[
                    <String, Object?>{'reasoningEffort': 'low'},
                    <String, Object?>{'reasoningEffort': 'medium'},
                  ],
                  'defaultReasoningEffort': 'medium',
                  'serviceTiers': <Object?>[],
                  'defaultServiceTier': null,
                  'isDefault': false,
                },
              ],
              'nextCursor': null,
            },
      'skills/list' => <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'cwd':
                (paramsMap['cwds'] is List &&
                    (paramsMap['cwds']! as List).isNotEmpty)
                ? (paramsMap['cwds']! as List).first
                : '/repo',
            'skills': <Object?>[
              <String, Object?>{
                'name': 'skill-creator',
                'path': '/skills/skill-creator/SKILL.md',
                'description': 'Create or update a Codex skill',
                'enabled': true,
                'scope': 'user',
                'interface': <String, Object?>{
                  'displayName': 'Skill Creator',
                  'shortDescription': 'Create skills',
                  'defaultPrompt': 'Add a new skill',
                },
              },
              <String, Object?>{
                'name': 'disabled-skill',
                'path': '/skills/disabled/SKILL.md',
                'description': 'Should be filtered',
                'enabled': false,
              },
            ],
            'errors': <Object?>[],
          },
        ],
      },
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
    if (error != null) {
      errorResponses[id] = error;
      return;
    }
    responses[id] = result;
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _notifications.close();
    await _serverRequests.close();
    await _stderrLines.close();
    await _protocolErrors.close();
  }

  Future<void> simulateUnexpectedExit() => close();

  void blockNextRequest(String method, Completer<void> gate) {
    _requestGates.putIfAbsent(method, () => <Completer<void>>[]).add(gate);
  }

  void emitNotification(String method, Map<String, Object?> params) {
    _notifications.add(
      JsonRpcNotification(
        method: method,
        params: params,
        raw: <String, Object?>{'method': method, 'params': params},
      ),
    );
  }

  void emitServerRequest({
    required Object id,
    required String method,
    required Map<String, Object?> params,
  }) {
    _serverRequests.add(
      JsonRpcRequest(
        id: id,
        method: method,
        params: params,
        raw: <String, Object?>{'id': id, 'method': method, 'params': params},
      ),
    );
  }

  void emitStderr(String line) {
    _stderrLines.add(line);
  }

  void completeStart() {
    _startCompleter?.complete();
  }
}

Map<String, Object?> _conversationModeListResponse({String planName = 'Plan'}) {
  return <String, Object?>{
    'data': <Object?>[
      <String, Object?>{
        'name': 'Default',
        'mode': 'default',
        'model': null,
        'reasoning_effort': null,
      },
      <String, Object?>{
        'name': planName,
        'mode': 'plan',
        'model': null,
        'reasoning_effort': 'medium',
      },
    ],
  };
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

List<String> _deleteThreadIds(_FakeJsonRpcPeer peer) {
  final ids = <String>[];
  for (var index = 0; index < peer.requestMethods.length; index += 1) {
    if (peer.requestMethods[index] != 'thread/delete') {
      continue;
    }
    final params = peer.requestParams[index]! as Map<String, Object?>;
    ids.add(params['threadId']! as String);
  }
  return ids;
}

List<AgentHistoryEntry> _historyEntries(AgentThreadHistorySnapshot history) {
  return <AgentHistoryEntry>[for (final turn in history.turns) ...turn.entries];
}

AgentHistoryTurn _historyTurn(
  AgentThreadHistorySnapshot history,
  String turnId,
) {
  return history.turns.singleWhere((turn) => turn.id == turnId);
}
