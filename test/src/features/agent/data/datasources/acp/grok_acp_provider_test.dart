import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
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

    test('injects permission mode meta on session/new', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok.copyWith(
          selectedPermissionOptionId: 'always-approve',
        ),
        peer: peer,
      );
      addTearDown(provider.dispose);

      await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );

      final newIndex = peer.requestMethods.indexOf('session/new');
      expect(newIndex, isNonNegative);
      final params = peer.requestParams[newIndex]! as Map<String, Object?>;
      final meta = params['_meta']! as Map<String, Object?>;
      expect(meta['yoloMode'], isTrue);
      expect(meta['clientIdentifier'], 'zeta');
      expect(meta.containsKey('autoMode'), isFalse);
    });

    test('session/new and session/load share identical Ask meta', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok.copyWith(
          // 旧 default 别名必须归一化为 Ask。
          selectedPermissionOptionId: 'default',
        ),
        peer: peer,
      );
      addTearDown(provider.dispose);

      await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );
      await provider.resumeSession(
        'sess-1',
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );

      final newIndex = peer.requestMethods.indexOf('session/new');
      final loadIndex = peer.requestMethods.indexOf('session/load');
      expect(newIndex, isNonNegative);
      expect(loadIndex, isNonNegative);
      final newMeta =
          (peer.requestParams[newIndex]! as Map<String, Object?>)['_meta']!
              as Map<String, Object?>;
      final loadMeta =
          (peer.requestParams[loadIndex]! as Map<String, Object?>)['_meta']!
              as Map<String, Object?>;
      expect(newMeta, <String, Object?>{'clientIdentifier': 'zeta'});
      expect(loadMeta, newMeta);
      expect(newMeta.containsKey('yoloMode'), isFalse);
      expect(newMeta.containsKey('autoMode'), isFalse);
    });

    test('session/new meta covers Auto and Ask elevated baselines', () async {
      Future<Map<String, Object?>> metaFor(String optionId) async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok.copyWith(
            selectedPermissionOptionId: optionId,
          ),
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
        final newIndex = peer.requestMethods.indexOf('session/new');
        return (peer.requestParams[newIndex]! as Map<String, Object?>)['_meta']!
            as Map<String, Object?>;
      }

      expect(await metaFor('auto'), <String, Object?>{
        'autoMode': true,
        'clientIdentifier': 'zeta',
      });
      expect(await metaFor('ask'), <String, Object?>{
        'clientIdentifier': 'zeta',
      });
      expect(await metaFor(''), <String, Object?>{'clientIdentifier': 'zeta'});
    });

    test(
      'broadcasts single _x.ai/yolo_mode_changed on permission updates',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.initialize();

        await provider.permissionPolicy.applyPermissionSelection(
          const AgentPermissionSelection(optionId: 'auto'),
        );

        expect(peer.notificationsSent, <String>['_x.ai/yolo_mode_changed']);
        expect(
          peer.notificationsSent,
          isNot(contains('x.ai/yolo_mode_changed')),
        );
        final params = peer.notificationParams.single! as Map<String, Object?>;
        expect(params['permission_mode'], 'auto');
        expect(params['auto_mode'], isTrue);
        expect(params['yolo_mode'], isFalse);

        // Always approve → Ask 后必须显式关闭自动批准。
        await provider.permissionPolicy.applyPermissionSelection(
          const AgentPermissionSelection(optionId: 'always-approve'),
        );
        await provider.permissionPolicy.applyPermissionSelection(
          const AgentPermissionSelection(optionId: 'ask'),
        );
        final askParams = peer.notificationParams.last! as Map<String, Object?>;
        expect(askParams['permission_mode'], 'ask');
        expect(askParams['yolo_mode'], isFalse);
        expect(askParams['auto_mode'], isFalse);
        expect(
          peer.notificationsSent.where((m) => m == '_x.ai/yolo_mode_changed'),
          hasLength(3),
        );
      },
    );

    test(
      'permissionPolicy catalog exposes only Ask Auto Always approve',
      () async {
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: _FakeJsonRpcPeer(),
        );
        addTearDown(provider.dispose);

        final catalog = await provider.permissionPolicy.listPermissionOptions();
        final options = catalog.options;
        expect(options.map((o) => o.id).toList(), <String>[
          'ask',
          'auto',
          'always-approve',
        ]);
        expect(options.map((o) => o.description).toList(), <String>[
          'Ask',
          'Auto',
          'Always approve',
        ]);
      },
    );

    test('reads Grok billing plan windows and reset time', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );

      final quota = await provider.readUsageQuota();

      expect(peer.requestMethods, contains('_x.ai/billing'));
      expect(quota, isNotNull);
      expect(quota!.planType, 'SuperGrok');
      expect(quota.windows, hasLength(1));
      expect(quota.windows.single.usedPercent, 35);
      expect(quota.windows.single.label, '周额度');
      expect(
        quota.windows.single.resetsAt,
        DateTime.parse('2026-08-01T08:38:01.643958+00:00').toLocal(),
      );
      await provider.dispose();
    });

    test('lists Grok skills via _x.ai/skills/list', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final catalog = await provider.listSkills(cwds: <String>['/repo']);

      expect(peer.requestMethods, contains('_x.ai/skills/list'));
      final skillsIndex = peer.requestMethods.indexOf('_x.ai/skills/list');
      final params = peer.requestParams[skillsIndex]! as Map<String, Object?>;
      expect(params['cwd'], '/repo');
      expect(catalog.entries, hasLength(1));
      final entry = catalog.entries.single;
      expect(entry.cwd, '/repo');
      // fixture 中 pdf 处于禁用态，被 dropped。
      expect(entry.skills, hasLength(3));
      expect(entry.skills.first.name, 'create-skill');
      expect(entry.skills.first.displayName, 'Create Skill');
    });

    test('listSkills falls back to process cwd when no cwd provided', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final catalog = await provider.listSkills();

      expect(peer.requestMethods, contains('_x.ai/skills/list'));
      final skillsIndex = peer.requestMethods.indexOf('_x.ai/skills/list');
      final params = peer.requestParams[skillsIndex]! as Map<String, Object?>;
      expect(params['cwd'], '.');
      expect(catalog.entries, hasLength(1));
      expect(catalog.entries.single.cwd, '.');
    });

    test(
      'invalidates skills catalog on plugins_changed notification',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.initialize();

        final changed = <void>[];
        final subscription = provider.skillsChanged.listen(
          (_) => changed.add(null),
        );
        addTearDown(subscription.cancel);

        peer.emitNotification('x.ai/session_notification', <String, Object?>{
          'sessionId': 'sess-1',
          'update': <String, Object?>{
            'sessionUpdate': 'plugins_changed',
            'plugins': <Object?>[],
          },
          '_meta': <String, Object?>{'eventId': 'evt-1'},
        });

        await _waitUntil(() => changed.isNotEmpty);
        expect(changed, hasLength(1));
      },
    );

    test('ignores non-skill session notifications for skillsChanged', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      addTearDown(provider.dispose);
      await provider.initialize();

      final changed = <void>[];
      final subscription = provider.skillsChanged.listen(
        (_) => changed.add(null),
      );
      addTearDown(subscription.cancel);

      peer.emitNotification('x.ai/session_notification', <String, Object?>{
        'sessionId': 'sess-1',
        'update': <String, Object?>{'sessionUpdate': 'auto_compact_started'},
        '_meta': <String, Object?>{'eventId': 'evt-1'},
      });

      await _waitUntil(() => changed.isNotEmpty);
      expect(changed, isEmpty);
    });

    test(
      'sends skills as \$name text and skips structured skill inputs',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'/repo'),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'/repo'),
          // composer 真实形态：文本（已含 `$name`）与结构化 skill 输入并列。
          inputs: <AgentUserInput>[
            AgentUserInput.text(r'$create-skill make a skill'),
            AgentUserInput.skill(
              name: 'create-skill',
              path: '/repo/.grok/skills/create-skill/SKILL.md',
            ),
          ],
        );

        final promptIndex = peer.requestMethods.indexOf('session/prompt');
        final params = peer.requestParams[promptIndex]! as Map<String, Object?>;
        final prompt = params['prompt'] as List<Object?>;
        // skill 结构化输入被跳过，仅保留文本 `$name`，避免重复。
        expect(prompt, hasLength(1));
        final textBlock = prompt.single as Map<Object?, Object?>;
        expect(textBlock['type'], 'text');
        expect(textBlock['text'], r'$create-skill make a skill');
      },
    );

    test('synthesizes \$name text for skill-only sends', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'/repo'),
      );
      await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'/repo'),
        inputs: <AgentUserInput>[
          AgentUserInput.skill(
            name: 'create-skill',
            path: '/repo/.grok/skills/create-skill/SKILL.md',
          ),
        ],
      );

      final promptIndex = peer.requestMethods.indexOf('session/prompt');
      final params = peer.requestParams[promptIndex]! as Map<String, Object?>;
      final prompt = params['prompt'] as List<Object?>;
      final textBlock = prompt.single as Map<Object?, Object?>;
      expect(textBlock['type'], 'text');
      expect(textBlock['text'], r'$create-skill');
    });

    test(
      'enriches live context occupancy with the active model window',
      () async {
        final peer = _FakeJsonRpcPeer()..promptCompleter = Completer<Object?>();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);
        addTearDown(provider.dispose);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
        final turnFuture = provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
          message: 'track context',
        );
        await _waitUntil(
          () => events.whereType<AgentTurnStartedEvent>().isNotEmpty,
        );

        peer.emitNotification('session/update', <String, Object?>{
          'sessionId': session.id,
          'update': <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'content': <String, Object?>{'type': 'text', 'text': 'working'},
          },
          '_meta': <String, Object?>{
            'eventId': 'context-1',
            'totalTokens': 125000,
          },
        });
        await _waitUntil(
          () => events.whereType<AgentContextWindowUsageEvent>().isNotEmpty,
        );

        final contextUsage = events
            .whereType<AgentContextWindowUsageEvent>()
            .single;
        expect(contextUsage.usedTokens, 125000);
        expect(contextUsage.modelContextWindow, 500000);

        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await turnFuture;
      },
    );

    test(
      'keeps an active session reducer when another session resumes',
      () async {
        final peer = _FakeJsonRpcPeer()..promptCompleter = Completer<Object?>();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);
        addTearDown(provider.dispose);

        final first = await provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
        final firstTurn = provider.sendMessage(
          session: first,
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
          message: 'keep running',
        );
        await _waitUntil(
          () => events.whereType<AgentTurnStartedEvent>().isNotEmpty,
        );

        await provider.resumeSession(
          'sess-2',
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
        peer.emitNotification('session/update', <String, Object?>{
          'sessionId': first.id,
          'update': <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'messageId': 'shared-runtime-message',
            'content': <String, Object?>{'type': 'text', 'text': 'still alive'},
          },
          '_meta': <String, Object?>{'eventId': 'shared-runtime-event'},
        });
        await _waitUntil(
          () => events.whereType<AgentMessageDeltaEvent>().any(
            (event) =>
                event.sessionId == first.id && event.delta == 'still alive',
          ),
        );

        expect(
          events.whereType<AgentMessageDeltaEvent>().any(
            (event) =>
                event.sessionId == first.id && event.delta == 'still alive',
          ),
          isTrue,
        );

        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await firstTurn;
      },
    );

    test('keeps unmatched response diagnostics out of the timeline', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);
      addTearDown(provider.dispose);
      await provider.initialize();

      peer.emitProtocolError(
        const JsonRpcProtocolException(
          'Response for unknown request id (String)',
          kind: JsonRpcProtocolErrorKind.unexpectedResponse,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<AgentErrorEvent>(), isEmpty);

      peer.emitProtocolError(
        const JsonRpcProtocolException('Invalid JSON on stdout'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<AgentErrorEvent>(), hasLength(1));
    });

    test(
      'logs original payload in shared ignored-message diagnostics across Grok notification paths',
      () async {
        final records = <LogRecord>[];
        await resetAppLoggingForTesting();
        configureAppLogging(level: Level.ALL, sink: records.add);
        addTearDown(resetAppLoggingForTesting);

        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);
        addTearDown(provider.dispose);
        await provider.initialize();
        await Future<void>.delayed(Duration.zero);
        events.clear();
        records.clear();

        peer.emitNotification('future/method', <String, Object?>{
          'secret': 'private notification content',
        });
        peer.emitNotification('future/method', <String, Object?>{
          'secret': 'private notification content',
        });
        peer.emitNotification('session/update', <String, Object?>{
          'sessionId': 'sess-1',
          'update': <String, Object?>{
            'sessionUpdate': 'future_update',
            'content': 'private update content',
          },
        });
        peer.emitNotification('session/update', <String, Object?>{
          'sessionId': 'sess-1',
          'update': <String, Object?>{
            'sessionUpdate': 'future_update',
            'content': 'private update content',
          },
        });
        await Future<void>.delayed(Duration.zero);

        final fineMessages = records
            .where(
              (record) =>
                  record.loggerName == 'zeta.agent.grok_acp' &&
                  record.level == Level.FINE,
            )
            .map((record) => record.message)
            .toList();
        expect(
          events.where(
            (event) =>
                event is! AgentStatusEvent && event is! AgentModelListEvent,
          ),
          isEmpty,
        );
        expect(
          fineMessages.where((message) => message.contains('future/method')),
          hasLength(2),
        );
        expect(
          fineMessages.where((message) => message.contains('session/update')),
          hasLength(2),
        );
        expect(fineMessages, everyElement(contains('Ignoring')));
        expect(fineMessages, everyElement(contains('raw=')));
        expect(provider.ignoredNotificationCountsForTesting, <String, int>{
          'future/method|unsupported notification method': 2,
          'session/update|unknown_kind': 2,
        });
        expect(provider.unmatchedNotificationCountsForTesting, <String, int>{
          'future/method': 2,
          'session/update': 2,
        });
        final renderedLogs = records.map((record) => record.message).join('\n');
        expect(renderedLogs, contains('"method":"future/method"'));
        expect(renderedLogs, contains('"method":"session/update"'));
        expect(
          renderedLogs,
          contains('"secret":"private notification content"'),
        );
        expect(renderedLogs, contains('"content":"private update content"'));
      },
    );

    test('renames and deletes Grok sessions via xAI extensions', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);
      addTearDown(provider.dispose);

      expect(provider.capabilities.canRenameThread, isTrue);
      expect(provider.capabilities.canDeleteThread, isTrue);
      expect(provider.capabilities.canArchiveThread, isFalse);

      await provider.renameThread(threadId: 'sess-1', name: '  Renamed  ');
      expect(peer.requestMethods, contains('_x.ai/session/rename'));
      final renameIndex = peer.requestMethods.lastIndexOf(
        '_x.ai/session/rename',
      );
      expect(peer.requestParams[renameIndex], <String, Object?>{
        'sessionId': 'sess-1',
        'title': 'Renamed',
      });
      expect(
        events.whereType<AgentThreadNameUpdatedEvent>().single.threadName,
        'Renamed',
      );

      await provider.deleteThread('sess-1');
      expect(peer.requestMethods, contains('_x.ai/session/delete'));
      final deleteIndex = peer.requestMethods.lastIndexOf(
        '_x.ai/session/delete',
      );
      expect(peer.requestParams[deleteIndex], <String, Object?>{
        'sessionId': 'sess-1',
      });
      expect(
        events.whereType<AgentThreadDeletedEvent>().single.threadId,
        'sess-1',
      );
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
        expect(provider.capabilities.canArchiveThread, isFalse);
        expect(provider.capabilities.canForkThread, isFalse);
      },
    );

    test(
      'encodes plan conversation mode as session/prompt _meta.mode',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'/repo'),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'/repo'),
          message: 'hello',
          configuration: AgentTurnConfiguration(
            conversationMode: AgentConversationModeSelection(
              modeId: AgentConversationModeId.plan,
              effectiveModelId: 'grok-4.5',
            ),
          ),
        );

        final promptIndex = peer.requestMethods.lastIndexOf('session/prompt');
        final params = peer.requestParams[promptIndex]! as Map<String, Object?>;
        expect(params['_meta'], <String, Object?>{'mode': 'plan'});
      },
    );

    test('encodes default conversation mode as agent _meta.mode', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'/repo'),
      );
      await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'/repo'),
        message: 'hello',
        configuration: AgentTurnConfiguration(
          conversationMode: AgentConversationModeSelection(
            modeId: AgentConversationModeId.defaultMode,
            effectiveModelId: 'grok-4.5',
          ),
        ),
      );

      final promptIndex = peer.requestMethods.lastIndexOf('session/prompt');
      final params = peer.requestParams[promptIndex]! as Map<String, Object?>;
      expect(params['_meta'], <String, Object?>{'mode': 'agent'});
    });

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

        // turn 完成时 summary 尚无 generated_title；稍后异步写入以覆盖延迟刷新路径。
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

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );
      peer.promptCompleter = Completer<Object?>();
      final promptFuture = provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
        message: 'ping',
      );
      await _waitUntil(() => peer.requestMethods.contains('session/prompt'));
      peer.emitNotification('session/update', <String, Object?>{
        'sessionId': 'sess-1',
        'update': <String, Object?>{
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'msg-1',
          'content': <String, Object?>{'type': 'text', 'text': 'Hello Grok'},
          '_meta': <String, Object?>{'promptId': 'provider-prompt-1'},
        },
        '_meta': <String, Object?>{'eventId': 'message-1'},
      });
      peer.emitNotification('session/update', <String, Object?>{
        'sessionId': 'sess-1',
        'update': <String, Object?>{
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-1',
          'title': 'Read file',
          'kind': 'read',
          'status': 'completed',
          '_meta': <String, Object?>{'promptId': 'provider-prompt-1'},
        },
        '_meta': <String, Object?>{'eventId': 'tool-1'},
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

      peer.promptCompleter!.complete(<String, Object?>{
        'stopReason': 'end_turn',
      });
      await promptFuture;

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

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );
      peer.promptCompleter = Completer<Object?>();
      final promptFuture = provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
        message: 'ping',
      );
      await _waitUntil(() => peer.requestMethods.contains('session/prompt'));
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

      final turn = events.whereType<AgentTurnStartedEvent>().last.turn;
      await provider.cancelTurn(turn);
      await Future<void>.delayed(Duration.zero);

      expect(peer.notificationsSent, contains('session/cancel'));
      expect(peer.responses, isNotEmpty);
      final cancelled = peer.responses.last['result']! as Map<String, Object?>;
      final outcome = cancelled['outcome']! as Map<String, Object?>;
      expect(outcome['outcome'], 'cancelled');
      expect(
        events.whereType<AgentTurnCompletedEvent>().last.status,
        AgentHistoryTurnStatus.interrupted,
      );
      expect(provider.streamIdentityDiagnostics.terminalAccepted, 1);

      peer.promptCompleter!.complete(<String, Object?>{
        'stopReason': 'cancelled',
      });
      await promptFuture;

      await subscription.cancel();
      await provider.dispose();
    });

    test(
      'keeps concurrent session prompts isolated and defers global ready',
      () async {
        final peer = _FakeJsonRpcPeer()
          ..promptCompleterQueue = <Completer<Object?>>[];
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(() async {
          await subscription.cancel();
          await provider.dispose();
        });

        final sessionA = await provider.startSession(
          context: const AgentContext(projectPath: r'/repo'),
        );
        final sessionB = await provider.resumeSession(
          'sess-2',
          context: const AgentContext(projectPath: r'/repo'),
        );
        expect(sessionA.id, isNot(sessionB.id));

        final turnAFuture = provider.sendMessage(
          session: sessionA,
          context: const AgentContext(projectPath: r'/repo'),
          message: 'work A',
        );
        final turnBFuture = provider.sendMessage(
          session: sessionB,
          context: const AgentContext(projectPath: r'/repo'),
          message: 'work B',
        );
        await _waitUntil(() => peer.promptCompleterQueue!.length == 2);

        final started = events.whereType<AgentTurnStartedEvent>().toList();
        expect(started, hasLength(2));
        expect(started.map((e) => e.turn.sessionId).toSet(), <String>{
          sessionA.id,
          sessionB.id,
        });

        int readyCount() => events
            .whereType<AgentStatusEvent>()
            .where((e) => e.status.state == AgentProviderConnectionState.ready)
            .length;
        // initialize 会先发 ready；之后只关心是否新增 ready。
        final readyBeforeComplete = readyCount();

        // 完成 A 后，B 仍 running：不得新增 ready。
        peer.promptCompleterQueue![0].complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await turnAFuture;
        await Future<void>.delayed(Duration.zero);
        expect(readyCount(), readyBeforeComplete);

        peer.promptCompleterQueue![1].complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await turnBFuture;
        await Future<void>.delayed(Duration.zero);

        expect(readyCount(), greaterThan(readyBeforeComplete));
      },
    );

    test(
      'cancelTurn only clears pending interactions for that session',
      () async {
        final peer = _FakeJsonRpcPeer()
          ..promptCompleterQueue = <Completer<Object?>>[];
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(() async {
          await subscription.cancel();
          await provider.dispose();
        });

        final sessionA = await provider.startSession(
          context: const AgentContext(projectPath: r'/repo'),
        );
        final sessionB = await provider.resumeSession(
          'sess-2',
          context: const AgentContext(projectPath: r'/repo'),
        );

        final turnAFuture = provider.sendMessage(
          session: sessionA,
          context: const AgentContext(projectPath: r'/repo'),
          message: 'A',
        );
        final turnBFuture = provider.sendMessage(
          session: sessionB,
          context: const AgentContext(projectPath: r'/repo'),
          message: 'B',
        );
        await _waitUntil(() => peer.promptCompleterQueue!.length == 2);

        peer.emitServerRequest(
          id: 201,
          method: 'session/request_permission',
          params: <String, Object?>{
            'sessionId': sessionA.id,
            'toolCall': <String, Object?>{
              'toolCallId': 'perm-a',
              'title': 'A only',
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
        peer.emitServerRequest(
          id: 202,
          method: '_x.ai/ask_user_question',
          params: <String, Object?>{
            'sessionId': sessionB.id,
            'toolCallId': 'ask-b',
            'questions': <Object?>[
              <String, Object?>{
                'question': 'Keep B?',
                'options': <Object?>[
                  <String, Object?>{'label': 'Yes'},
                ],
              },
            ],
          },
        );
        await _waitUntil(
          () =>
              events.whereType<AgentPermissionRequestedEvent>().isNotEmpty &&
              events.whereType<AgentQuestionRequestedEvent>().isNotEmpty,
        );

        final turnA = events
            .whereType<AgentTurnStartedEvent>()
            .firstWhere((e) => e.turn.sessionId == sessionA.id)
            .turn;
        await provider.cancelTurn(turnA);
        await Future<void>.delayed(Duration.zero);

        // A 的 permission 被 cancel；B 的 question 仍 park，尚未响应。
        expect(peer.responses.any((r) => r['id'] == 201), isTrue);
        expect(peer.responses.any((r) => r['id'] == 202), isFalse);
        expect(events.whereType<AgentQuestionRequestedEvent>(), hasLength(1));

        // B 仍可正常作答。
        await provider.respondToQuestion(
          AgentQuestionResponse(
            requestId: 'ask-b',
            answers: <String, List<String>>{
              'Keep B?': <String>['Yes'],
            },
          ),
        );
        expect(peer.responses.any((r) => r['id'] == 202), isTrue);

        peer.promptCompleterQueue![0].complete(<String, Object?>{
          'stopReason': 'cancelled',
        });
        peer.promptCompleterQueue![1].complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await Future.wait(<Future<void>>[turnAFuture, turnBFuture]);
      },
    );

    test('rejects a second prompt on the same session while running', () async {
      final peer = _FakeJsonRpcPeer()..promptCompleter = Completer<Object?>();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'/repo'),
      );
      final first = provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'/repo'),
        message: 'first',
      );
      await _waitUntil(() => peer.requestMethods.contains('session/prompt'));

      await expectLater(
        provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'/repo'),
          message: 'second',
        ),
        throwsA(isA<StateError>()),
      );

      peer.promptCompleter!.complete(<String, Object?>{
        'stopReason': 'end_turn',
      });
      await first;
    });

    test(
      'prompt_complete notification can finish a running turn as fallback',
      () async {
        final peer = _FakeJsonRpcPeer()..promptCompleter = Completer<Object?>();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(() async {
          await subscription.cancel();
          await provider.dispose();
        });

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'/repo'),
        );
        final promptFuture = provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'/repo'),
          message: 'hang until notification',
        );
        await _waitUntil(() => peer.requestMethods.contains('session/prompt'));

        peer.emitNotification(
          '_x.ai/session/prompt_complete',
          <String, Object?>{'sessionId': session.id, 'stopReason': 'end_turn'},
        );
        await _waitUntil(
          () => events.whereType<AgentTurnCompletedEvent>().isNotEmpty,
        );

        expect(
          events.whereType<AgentTurnCompletedEvent>().last.status,
          AgentHistoryTurnStatus.completed,
        );
        expect(
          events.whereType<AgentStatusEvent>().any(
            (e) => e.status.state == AgentProviderConnectionState.ready,
          ),
          isTrue,
        );

        // 迟到的 RPC 终态应被 first-terminal-wins 吸收，不抛错。
        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await promptFuture;
      },
    );

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

    test('parks _x.ai/ask_user_question until the user answers', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await provider.dispose();
      });

      await provider.startSession(
        context: const AgentContext(projectPath: r'/repo'),
      );
      peer.emitServerRequest(
        id: 91,
        method: '_x.ai/ask_user_question',
        params: <String, Object?>{
          'sessionId': 'sess-1',
          'toolCallId': 'ask-call-1',
          'questions': <Object?>[
            <String, Object?>{
              'question': 'Which path?',
              'options': <Object?>[
                <String, Object?>{
                  'label': 'ACP bridge',
                  'description': 'Reuse existing transport',
                },
                <String, Object?>{'label': 'Native'},
              ],
            },
          ],
        },
      );
      await _waitUntil(
        () => events.whereType<AgentQuestionRequestedEvent>().isNotEmpty,
      );

      final request = events
          .whereType<AgentQuestionRequestedEvent>()
          .single
          .request;
      expect(request.id, 'ask-call-1');
      expect(request.sessionId, 'sess-1');
      expect(request.questions, hasLength(1));
      expect(request.questions.single.questionId, 'Which path?');
      expect(provider.capabilities.supportsUserQuestions, isTrue);
      expect(peer.responses, isEmpty);

      await provider.respondToQuestion(
        AgentQuestionResponse(
          requestId: request.id,
          answers: <String, List<String>>{
            'Which path?': <String>['ACP bridge'],
          },
        ),
      );

      expect(peer.responses, hasLength(1));
      final response = peer.responses.single;
      expect(response['id'], 91);
      final result = response['result']! as Map<String, Object?>;
      expect(result['type'], 'accepted');
      final answers = result['answers']! as Map<String, Object?>;
      expect(answers['Which path?'], 'ACP bridge');
    });

    test(
      'accepts x.ai/ask_user_question prefix and skips with empty answers',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(() async {
          await subscription.cancel();
          await provider.dispose();
        });

        await provider.initialize();
        peer.emitServerRequest(
          id: 92,
          method: 'x.ai/ask_user_question',
          params: <String, Object?>{
            'sessionId': 'sess-1',
            'toolCallId': 'ask-call-2',
            'questions': <Object?>[
              <String, Object?>{
                'question': 'Continue?',
                'options': <Object?>[
                  <String, Object?>{'label': 'Yes'},
                ],
              },
            ],
          },
        );
        await _waitUntil(
          () => events.whereType<AgentQuestionRequestedEvent>().isNotEmpty,
        );

        await provider.respondToQuestion(
          const AgentQuestionResponse(requestId: 'ask-call-2'),
        );

        final result = peer.responses.single['result']! as Map<String, Object?>;
        expect(result['type'], 'skip_interview');
      },
    );

    test('parks x.ai/exit_plan_mode until user approves the plan', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await provider.dispose();
      });

      await provider.startSession(
        context: const AgentContext(projectPath: r'/repo'),
      );
      peer.emitServerRequest(
        id: 55,
        method: 'x.ai/exit_plan_mode',
        params: <String, Object?>{
          'sessionId': 'sess-1',
          'toolCallId': 'plan-call-1',
          'planContent': '# Plan\n\n1. Refactor\n2. Test',
        },
      );
      await _waitUntil(
        () => events.whereType<AgentPlanApprovalRequestedEvent>().isNotEmpty,
      );

      final approval = events
          .whereType<AgentPlanApprovalRequestedEvent>()
          .single
          .request;
      expect(approval.id, 'plan-call-1');
      expect(approval.sessionId, 'sess-1');
      expect(approval.markdown, contains('Refactor'));

      // 审批在途：尚未有任何 ext 响应（shell 保持 park）。
      expect(peer.responses, isEmpty);

      await provider.respondToPlanApproval(
        AgentPlanApprovalDecision(
          requestId: approval.id,
          kind: AgentPlanApprovalDecisionKind.accepted,
        ),
      );
      expect(peer.responses, isNotEmpty);
      final response = peer.responses.single;
      expect(response['id'], 55);
      final result = response['result']! as Map<String, Object?>;
      expect(result['outcome'], 'approved');
    });

    test('parks _x.ai/exit_plan_mode with underscore prefix', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await provider.dispose();
      });

      await provider.startSession(
        context: const AgentContext(projectPath: r'/repo'),
      );
      peer.emitServerRequest(
        id: 56,
        method: '_x.ai/exit_plan_mode',
        params: <String, Object?>{
          'sessionId': 'sess-1',
          'toolCallId': 'plan-call-underscore',
          'planContent': '# Underscore plan',
        },
      );
      await _waitUntil(
        () => events.whereType<AgentPlanApprovalRequestedEvent>().isNotEmpty,
      );

      await provider.respondToPlanApproval(
        const AgentPlanApprovalDecision(
          requestId: 'plan-call-underscore',
          kind: AgentPlanApprovalDecisionKind.accepted,
        ),
      );
      expect(peer.responses.single['id'], 56);
      final result = peer.responses.single['result']! as Map<String, Object?>;
      expect(result['outcome'], 'approved');
    });

    test('rejects a plan with feedback mapped to cancelled', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await provider.dispose();
      });

      await provider.startSession(
        context: const AgentContext(projectPath: r'/repo'),
      );
      peer.emitServerRequest(
        id: 77,
        method: 'x.ai/exit_plan_mode',
        params: <String, Object?>{
          'sessionId': 'sess-1',
          'toolCallId': 'plan-call-2',
          'planContent': '# Plan',
        },
      );
      await _waitUntil(
        () => events.whereType<AgentPlanApprovalRequestedEvent>().isNotEmpty,
      );

      await provider.respondToPlanApproval(
        AgentPlanApprovalDecision(
          requestId: 'plan-call-2',
          kind: AgentPlanApprovalDecisionKind.rejected,
          reason: 'please add error handling',
        ),
      );
      final result = peer.responses.single['result']! as Map<String, Object?>;
      expect(result['outcome'], 'cancelled');
      expect(result['feedback'], 'please add error handling');
    });

    test(
      'replacing exit_plan_mode abandons the previous parked request',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(() async {
          await subscription.cancel();
          await provider.dispose();
        });

        await provider.startSession(
          context: const AgentContext(projectPath: r'/repo'),
        );
        peer.emitServerRequest(
          id: 101,
          method: 'x.ai/exit_plan_mode',
          params: <String, Object?>{
            'sessionId': 'sess-1',
            'toolCallId': 'plan-call-replace',
            'planContent': '# Plan v1',
          },
        );
        await _waitUntil(
          () => events.whereType<AgentPlanApprovalRequestedEvent>().isNotEmpty,
        );

        peer.emitServerRequest(
          id: 102,
          method: 'x.ai/exit_plan_mode',
          params: <String, Object?>{
            'sessionId': 'sess-1',
            'toolCallId': 'plan-call-replace',
            'planContent': '# Plan v2',
          },
        );
        await _waitUntil(() {
          final resolved = events.whereType<AgentPlanApprovalResolvedEvent>();
          final requested = events.whereType<AgentPlanApprovalRequestedEvent>();
          return resolved.isNotEmpty && requested.length >= 2;
        });

        // 旧 rpc id=101 必须以 abandoned 应答，新请求仍 park（无 102 响应）。
        expect(peer.responses, hasLength(1));
        expect(peer.responses.single['id'], 101);
        final abandoned =
            peer.responses.single['result']! as Map<String, Object?>;
        expect(abandoned['outcome'], 'abandoned');
        expect(
          events.whereType<AgentPlanApprovalResolvedEvent>().single.requestId,
          'plan-call-replace',
        );
        expect(
          events
              .whereType<AgentPlanApprovalRequestedEvent>()
              .last
              .request
              .markdown,
          contains('v2'),
        );

        await provider.respondToPlanApproval(
          AgentPlanApprovalDecision(
            requestId: 'plan-call-replace',
            kind: AgentPlanApprovalDecisionKind.accepted,
          ),
        );
        expect(peer.responses, hasLength(2));
        expect(peer.responses.last['id'], 102);
        final approved = peer.responses.last['result']! as Map<String, Object?>;
        expect(approved['outcome'], 'approved');
      },
    );

    test('dispose abandons parked exit_plan_mode requests', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      await provider.startSession(
        context: const AgentContext(projectPath: r'/repo'),
      );
      peer.emitServerRequest(
        id: 201,
        method: 'x.ai/exit_plan_mode',
        params: <String, Object?>{
          'sessionId': 'sess-1',
          'toolCallId': 'plan-call-dispose',
          'planContent': '# Plan',
        },
      );
      await _waitUntil(
        () => events.whereType<AgentPlanApprovalRequestedEvent>().isNotEmpty,
      );
      expect(peer.responses, isEmpty);

      await provider.dispose();
      await subscription.cancel();

      expect(peer.responses, isNotEmpty);
      expect(peer.responses.single['id'], 201);
      final result = peer.responses.single['result']! as Map<String, Object?>;
      expect(result['outcome'], 'abandoned');
      expect(
        events.whereType<AgentPlanApprovalResolvedEvent>().single.requestId,
        'plan-call-dispose',
      );
    });

    test(
      'permission boundary splits adapter message ids without TimelineStore',
      () async {
        final peer = _FakeJsonRpcPeer();
        final mapper = GrokAcpNotificationMapper();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
          notificationMapper: mapper,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
        peer.promptCompleter = Completer<Object?>();
        final promptFuture = provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
          message: 'ping',
        );
        await _waitUntil(() => peer.requestMethods.contains('session/prompt'));

        peer.emitNotification(
          'session/update',
          _messageParams(
            text: 'before',
            eventId: 'message-before',
            sourceMessageId: 'source-A',
          ),
        );
        peer.emitServerRequest(
          id: 88,
          method: 'session/request_permission',
          params: <String, Object?>{
            'sessionId': 'sess-1',
            'toolCall': <String, Object?>{
              'toolCallId': 'tool-permission',
              'title': 'Approve action',
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
        peer.emitNotification(
          'session/update',
          _messageParams(
            text: 'after',
            eventId: 'message-after',
            sourceMessageId: 'source-A',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final timelineEvents = events
            .where(
              (event) =>
                  event is AgentMessageDeltaEvent ||
                  event is AgentPermissionRequestedEvent,
            )
            .toList(growable: false);
        expect(timelineEvents, <Matcher>[
          isA<AgentMessageDeltaEvent>(),
          isA<AgentPermissionRequestedEvent>(),
          isA<AgentMessageDeltaEvent>(),
        ]);
        final messages = timelineEvents.whereType<AgentMessageDeltaEvent>();
        expect(messages.first.sourceMessageId, 'source-A');
        expect(messages.last.sourceMessageId, 'source-A');
        expect(messages.first.messageId, isNot(messages.last.messageId));

        final permission = events
            .whereType<AgentPermissionRequestedEvent>()
            .single;
        await provider.respondToPermission(
          AgentPermissionDecision(
            requestId: permission.request.id,
            approved: true,
          ),
        );
        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await promptFuture;
        await subscription.cancel();
        await provider.dispose();
      },
    );

    test('xAI notification wins prompt RPC terminal race once', () async {
      final peer = _FakeJsonRpcPeer();
      final mapper = GrokAcpNotificationMapper();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
        notificationMapper: mapper,
      );
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );
      peer.promptCompleter = Completer<Object?>();
      final promptFuture = provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
        message: 'ping',
      );
      await _waitUntil(() => peer.requestMethods.contains('session/prompt'));
      peer.emitNotification(
        'session/update',
        _messageParams(text: 'chunk', eventId: 'message-1'),
      );
      peer.emitNotification('_x.ai/session/update', <String, Object?>{
        'sessionId': 'sess-1',
        'update': <String, Object?>{
          'sessionUpdate': 'turn_completed',
          'prompt_id': 'provider-prompt-1',
          'stop_reason': 'end_turn',
        },
        '_meta': <String, Object?>{'eventId': 'xai-terminal'},
      });
      await Future<void>.delayed(Duration.zero);
      peer.promptCompleter!.complete(<String, Object?>{
        'stopReason': 'end_turn',
      });
      await promptFuture;

      expect(events.whereType<AgentTurnCompletedEvent>(), hasLength(1));
      expect(mapper.diagnostics.terminalAccepted, 1);
      expect(mapper.diagnostics.duplicateTerminalIgnored, 1);

      await subscription.cancel();
      await provider.dispose();
    });

    test(
      'late xAI terminal supplements usage after prompt RPC completes',
      () async {
        final peer = _FakeJsonRpcPeer();
        final mapper = GrokAcpNotificationMapper();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
          notificationMapper: mapper,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
        peer.promptCompleter = Completer<Object?>();
        final promptFuture = provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
          message: 'ping',
        );
        await _waitUntil(() => peer.requestMethods.contains('session/prompt'));
        peer.emitNotification('session/update', <String, Object?>{
          'sessionId': 'sess-1',
          'update': <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'messageId': 'message-before-rpc',
            'content': <String, Object?>{'type': 'text', 'text': 'done'},
            '_meta': <String, Object?>{'promptId': 'provider-prompt-1'},
          },
          '_meta': <String, Object?>{
            'eventId': 'message-before-rpc',
            'totalTokens': 1200,
          },
        });
        await Future<void>.delayed(Duration.zero);

        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await promptFuture;
        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<AgentTurnCompletedEvent>(), hasLength(1));
        expect(events.whereType<AgentTokenUsageEvent>(), isEmpty);

        peer.emitNotification('_x.ai/session/update', <String, Object?>{
          'sessionId': 'sess-1',
          'update': <String, Object?>{
            'sessionUpdate': 'turn_completed',
            'prompt_id': 'provider-prompt-1',
            'stop_reason': 'end_turn',
            'usage': <String, Object?>{
              'inputTokens': 1000,
              'outputTokens': 300,
              'totalTokens': 1300,
              'cachedReadTokens': 200,
              'reasoningTokens': 50,
            },
          },
          '_meta': <String, Object?>{'eventId': 'late-xai-terminal'},
        });
        await Future<void>.delayed(Duration.zero);

        expect(events.whereType<AgentTurnCompletedEvent>(), hasLength(1));
        final usage = events.whereType<AgentTokenUsageEvent>().single;
        expect(usage.tokenUsage.totalTokens, 1300);
        expect(usage.tokenUsage.lastTotalTokens, 1200);
        expect(mapper.diagnostics.terminalAccepted, 1);
        expect(mapper.diagnostics.duplicateTerminalIgnored, 1);

        await subscription.cancel();
        await provider.dispose();
      },
    );

    for (final scenario
        in <({String name, Object error, String message, bool connectionLost})>[
          (
            name: 'rate-limit JSON-RPC error',
            error: const JsonRpcException(
              JsonRpcError(
                code: -32003,
                message: 'Rate limited',
                data: <String, Object?>{'retryAfterSeconds': 30},
              ),
            ),
            message: 'Grok rate limit reached. Please try again later.',
            connectionLost: false,
          ),
          (
            name: 'generic JSON-RPC error',
            error: const JsonRpcException(
              JsonRpcError(code: -32603, message: 'Provider rejected request'),
            ),
            message: 'Grok request failed: Provider rejected request',
            connectionLost: false,
          ),
          (
            name: 'timeout',
            error: TimeoutException(
              'JSON-RPC request timed out: session/prompt',
              const Duration(seconds: 30),
            ),
            message: 'Grok request timed out. Please try again.',
            connectionLost: false,
          ),
          (
            name: 'connection close',
            error: const JsonRpcTransportClosedException(
              'JSON-RPC process exited with code 1',
            ),
            message: 'Grok connection closed. Reconnect and try again.',
            connectionLost: true,
          ),
          (
            name: 'unknown exception',
            error: StateError('redacted failure'),
            message: 'Grok request failed. Please try again.',
            connectionLost: false,
          ),
        ]) {
      test('normalizes prompt ${scenario.name} into one failed turn', () async {
        final peer = _FakeJsonRpcPeer();
        final mapper = GrokAcpNotificationMapper();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
          notificationMapper: mapper,
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
        peer.promptCompleter = Completer<Object?>();
        final promptFuture = provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
          message: 'ping',
        );
        await _waitUntil(() => peer.requestMethods.contains('session/prompt'));
        if (scenario.connectionLost) {
          await peer.closeNotificationStream();
        }
        peer.promptCompleter!.completeError(scenario.error);
        final turn = await promptFuture;
        await Future<void>.delayed(Duration.zero);

        final started = events.whereType<AgentTurnStartedEvent>().last;
        final completed = events.whereType<AgentTurnCompletedEvent>().single;
        final visibleError = events.whereType<AgentErrorEvent>().single;
        expect(turn.id, started.turn.id);
        expect(completed.status, AgentHistoryTurnStatus.failed);
        expect(completed.errorMessage, scenario.message);
        expect(completed.raw['operation'], 'session/prompt');
        expect(visibleError.message, scenario.message);
        expect(visibleError.details, isNull);
        expect(visibleError.sessionId, session.id);
        expect(visibleError.turnId, started.turn.id);
        expect(visibleError.exception, same(scenario.error));
        expect(visibleError.stackTrace, isNotNull);
        expect(visibleError.raw, completed.raw);
        expect(
          visibleError.raw['exceptionType'],
          scenario.error.runtimeType.toString(),
        );
        final finalStatus = events.whereType<AgentStatusEvent>().last.status;
        expect(
          finalStatus.state,
          scenario.connectionLost
              ? AgentProviderConnectionState.unavailable
              : AgentProviderConnectionState.ready,
        );
        expect(mapper.diagnostics.terminalAccepted, 1);
        if (!scenario.connectionLost) {
          expect(
            mapper
                .snapshot(
                  runtimeScope: provider.runtimeScope!,
                  sessionId: session.id,
                  turnId: started.turn.id,
                )!
                .terminal,
            isTrue,
          );
        }
        if (scenario.error case JsonRpcException(:final error)) {
          final rawRpcError =
              visibleError.raw['jsonRpcError']! as Map<String, Object?>;
          expect(rawRpcError['code'], error.code);
          expect(rawRpcError['message'], error.message);
          expect(rawRpcError['data'], error.data);
        }
      });
    }

    test('peer close and dispose invalidate reducer lifecycle state', () async {
      final peer = _FakeJsonRpcPeer();
      final mapper = GrokAcpNotificationMapper();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
        notificationMapper: mapper,
      );

      await provider.initialize();
      final scope = provider.runtimeScope!;
      mapper.beginTurn(
        runtimeScope: scope,
        sessionId: 'session-lifecycle',
        turnId: 'turn-lifecycle',
      );
      await peer.closeNotificationStream();
      await Future<void>.delayed(Duration.zero);

      expect(
        mapper
            .snapshot(
              runtimeScope: scope,
              sessionId: 'session-lifecycle',
              turnId: 'turn-lifecycle',
            )!
            .terminal,
        isTrue,
      );
      await provider.dispose();
      expect(
        mapper.snapshot(
          runtimeScope: scope,
          sessionId: 'session-lifecycle',
          turnId: 'turn-lifecycle',
        ),
        isNull,
      );
    });
  });

  group('GrokAcpNotificationMapper', () {
    const runtimeScope = AgentRuntimeScope(
      runtimeId: 'grok-mapper-test',
      connectionEpoch: 1,
    );
    late GrokAcpNotificationMapper mapper;

    setUp(() {
      mapper = GrokAcpNotificationMapper();
      mapper.beginTurn(
        runtimeScope: runtimeScope,
        sessionId: 's1',
        turnId: 't1',
      );
    });

    tearDown(() {
      mapper.dispose();
    });

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
        runtimeScope: runtimeScope,
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
        runtimeScope: runtimeScope,
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
        runtimeScope: runtimeScope,
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
        runtimeScope: runtimeScope,
      );
      final event = mapped.events.single as AgentTurnCompletedEvent;
      expect(event.sessionId, 's1');
      expect(event.turnId, 't1');
      expect(event.status, AgentHistoryTurnStatus.completed);
    });

    test('maps turn_completed usage as turn-absolute with apiDurationMs', () {
      mapper.beginTurn(
        runtimeScope: runtimeScope,
        sessionId: 'sess-1',
        turnId: 'local-turn-1',
      );
      final mapped = mapper.mapXaiSessionUpdate(
        params: readFixtureJsonMap(
          'grok/acp/xai_turn_completed_notification_redacted.json',
        ),
        runningTurnId: 'local-turn-1',
        runtimeScope: runtimeScope,
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
        runtimeScope: runtimeScope,
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

Map<String, Object?> _messageParams({
  required String text,
  required String eventId,
  String? sourceMessageId,
}) => <String, Object?>{
  'sessionId': 'sess-1',
  'update': <String, Object?>{
    'sessionUpdate': 'agent_message_chunk',
    'messageId': ?sourceMessageId,
    'content': <String, Object?>{'type': 'text', 'text': text},
    '_meta': <String, Object?>{'promptId': 'provider-prompt-1'},
  },
  '_meta': <String, Object?>{'eventId': eventId},
};

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
  final notificationParams = <Object?>[];

  /// 模拟 session/load 期间推送 isReplay 更新。
  bool loadSessionEmitsReplay = false;

  /// 模拟 initialize 返回的 session/load 能力。
  bool supportsLoadSession = true;

  /// 模拟旧 Grok initialize 不带模型状态，以覆盖 CLI 降级竞态。
  bool includeModelState = true;

  /// 非空时延迟 `session/prompt` 响应，便于测试 live 通知竞态。
  Completer<Object?>? promptCompleter;

  /// 非空时每个 `session/prompt` 入队独立 Completer，支持多 session 并发。
  List<Completer<Object?>>? promptCompleterQueue;

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
    if (method == 'session/prompt') {
      final queue = promptCompleterQueue;
      if (queue != null) {
        final completer = Completer<Object?>();
        queue.add(completer);
        return completer.future;
      }
      if (promptCompleter != null) {
        return promptCompleter!.future;
      }
    }
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
          // 在响应返回前同步发出回放通知，覆盖先通知后响应的时序。
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
      '_x.ai/skills/list' => readFixtureJsonMap(
        'grok/acp/xai_skills_list_response.json',
      ),
      '_x.ai/billing' => readFixtureJsonMap(
        'grok/acp/xai_billing_response_redacted.json',
      ),
      '_x.ai/session/rename' => <String, Object?>{'success': true},
      '_x.ai/session/delete' => <String, Object?>{'success': true},
      _ => <String, Object?>{},
    };
  }

  @override
  void sendNotification(String method, {Object? params}) {
    notificationsSent.add(method);
    notificationParams.add(params);
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
      JsonRpcNotification(
        method: method,
        params: params,
        raw: <String, Object?>{'method': method, 'params': params},
      ),
    );
  }

  void emitProtocolError(JsonRpcProtocolException error) {
    _protocolErrors.add(error);
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

  Future<void> closeNotificationStream() => _notifications.close();
}

class _DelayedModelsCli extends GrokModelsCli {
  _DelayedModelsCli(this.result);

  final Future<AgentModelList> result;

  @override
  Future<AgentModelList> listModels(AgentProviderConfig config) => result;
}
