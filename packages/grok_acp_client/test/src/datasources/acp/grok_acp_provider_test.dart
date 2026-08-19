// Mock setup reads more clearly without forced cascades; wire fixtures stay on
// one line so their exact protocol shape is visible.
// ignore_for_file: cascade_invocations, lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/src/datasources/acp/grok_acp_agent_provider.dart';
import 'package:grok_acp_client/src/datasources/acp/grok_models_cli.dart';
import 'package:grok_acp_client/src/grok_provider_bundle_factory.dart';
import 'package:grok_acp_client/src/history/grok_session_history_reader.dart';
import 'package:grok_acp_client/src/mappers/grok_acp_notification_mapper.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

import '../../../testing/fixture_reader.dart';

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
      'emits turn started context from the current model selection',
      () async {
        final peer = _FakeJsonRpcPeer()..promptCompleter = Completer<Object?>();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        provider.events.listen(events.add);
        provider.updateModelSelection(
          const AgentModelSelection(modelId: 'grok-4', reasoningEffort: 'high'),
        );

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
        final turnFuture = provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
          message: 'hello',
        );
        await _waitUntil(
          () => events.whereType<AgentTurnStartedEvent>().isNotEmpty,
        );
        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await turnFuture;

        final started = events.whereType<AgentTurnStartedEvent>().single;
        expect(started.modelId, 'grok-4');
        expect(started.reasoningEffort, 'high');
        expect(started.startedAt, isNotNull);
      },
    );

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
      expect(quota.windows.single.label, '1 week');
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
      'emits thread preview from last_turn_summary session notification',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.initialize();

        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);

        peer.emitNotification('_x.ai/session_notification', <String, Object?>{
          'sessionId': 'sess-preview-1',
          'update': <String, Object?>{
            'sessionUpdate': 'last_turn_summary',
            'summary': '排查图片生成是否被改坏',
            'prompt_id': 'prompt-1',
          },
          '_meta': <String, Object?>{'agentTimestampMs': 1786327109733},
        });

        await _waitUntil(
          () => events.whereType<AgentThreadPreviewUpdatedEvent>().isNotEmpty,
        );
        final previewEvent = events
            .whereType<AgentThreadPreviewUpdatedEvent>()
            .single;
        expect(previewEvent.threadId, 'sess-preview-1');
        expect(previewEvent.preview, '排查图片生成是否被改坏');
      },
    );

    test(
      'maps live retry_state session_notification to willRetry error',
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
          message: 'trigger transport retry',
        );
        await _waitUntil(
          () => events.whereType<AgentTurnStartedEvent>().isNotEmpty,
        );

        peer.emitNotification('_x.ai/session_notification', <String, Object?>{
          'sessionId': session.id,
          'update': <String, Object?>{
            'sessionUpdate': 'retry_state',
            'type': 'retrying',
            'attempt': 1,
            'max_retries': 15,
            'reason': 'reqwest error stream: Transport error: error decoding response body',
          },
          '_meta': <String, Object?>{
            'eventId': 'retry-live-1',
            'agentTimestampMs': 1786328859243,
          },
        });
        await _waitUntil(() => events.whereType<AgentErrorEvent>().isNotEmpty);

        final error = events.whereType<AgentErrorEvent>().single;
        expect(error.sessionId, session.id);
        expect(error.willRetry, isTrue);
        expect(error.code, 'responseStreamDisconnected');
        expect(error.message, contains('retry 1/15'));
        expect(error.message, isNot(contains('reqwest')));
        expect(events.whereType<AgentTurnCompletedEvent>(), isEmpty);

        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await turnFuture;
      },
    );

    test(
      'maps exhausted retry_state session_notification to failed turn',
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
          message: 'trigger exhausted retry',
        );
        await _waitUntil(
          () => events.whereType<AgentTurnStartedEvent>().isNotEmpty,
        );

        peer.emitNotification('x.ai/session_notification', <String, Object?>{
          'sessionId': session.id,
          'update': <String, Object?>{
            'sessionUpdate': 'retry_state',
            'type': 'exhausted',
            'attempts': 15,
            'reason': 'provider unavailable',
            'is_rate_limited': false,
          },
          '_meta': <String, Object?>{'eventId': 'retry-live-exhausted'},
        });
        await _waitUntil(
          () => events.whereType<AgentTurnCompletedEvent>().isNotEmpty,
        );

        final error = events.whereType<AgentErrorEvent>().single;
        final terminal = events.whereType<AgentTurnCompletedEvent>().single;
        expect(error.willRetry, isFalse);
        expect(error.message, 'Grok request failed. Please try again.');
        expect(terminal.status, AgentHistoryTurnStatus.failed);
        expect(terminal.errorMessage, error.message);

        // first-terminal-wins：后续 prompt RPC 终态不得再推进 timeline 终态。
        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await turnFuture;
        expect(events.whereType<AgentTurnCompletedEvent>(), hasLength(1));
      },
    );

    test(
      r'sends skills as $name text and skips structured skill inputs',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: '/repo'),
          // composer 真实形态：文本（已含 `$name`）与结构化 skill 输入并列。
          inputs: <AgentUserInput>[
            AgentUserInput.text(r'$create-skill make a skill'),
            const AgentUserInput.skill(
              name: 'create-skill',
              path: '/repo/.grok/skills/create-skill/SKILL.md',
            ),
          ],
        );

        final promptIndex = peer.requestMethods.indexOf('session/prompt');
        final params = peer.requestParams[promptIndex]! as Map<String, Object?>;
        final prompt = params['prompt']! as List<Object?>;
        // skill 结构化输入被跳过，仅保留文本 `$name`，避免重复。
        expect(prompt, hasLength(1));
        final textBlock = prompt.single! as Map<Object?, Object?>;
        expect(textBlock['type'], 'text');
        expect(textBlock['text'], r'$create-skill make a skill');
      },
    );

    test(r'synthesizes $name text for skill-only sends', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
      );
      await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: '/repo'),
        inputs: <AgentUserInput>[
          const AgentUserInput.skill(
            name: 'create-skill',
            path: '/repo/.grok/skills/create-skill/SKILL.md',
          ),
        ],
      );

      final promptIndex = peer.requestMethods.indexOf('session/prompt');
      final params = peer.requestParams[promptIndex]! as Map<String, Object?>;
      final prompt = params['prompt']! as List<Object?>;
      final textBlock = prompt.single! as Map<Object?, Object?>;
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

    test(
      'maps session_info_update and session_summary_generated to thread rename',
      () async {
        final peer = _FakeJsonRpcPeer();
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

        peer.emitNotification('session/update', <String, Object?>{
          'sessionId': session.id,
          'update': <String, Object?>{
            'sessionUpdate': 'session_info_update',
            'title': 'Realtime Session Grok retry_state Event Adaptation',
          },
        });
        await _waitUntil(
          () => events.whereType<AgentThreadNameUpdatedEvent>().isNotEmpty,
        );
        expect(
          events.whereType<AgentThreadNameUpdatedEvent>().last.threadName,
          'Realtime Session Grok retry_state Event Adaptation',
        );

        peer.emitNotification('_x.ai/session_notification', <String, Object?>{
          'sessionId': session.id,
          'update': <String, Object?>{
            'sessionUpdate': 'session_summary_generated',
            'session_summary':
                'Realtime Session Grok retry_state Event Adaptation',
          },
        });
        await Future<void>.delayed(Duration.zero);
        // 同文不重复推送（provider 侧已记 emitted title）。
        expect(events.whereType<AgentThreadNameUpdatedEvent>(), hasLength(1));
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
        const TransportMalformedFrame(
          message: 'Response for unknown request id',
          payloadLength: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<AgentErrorEvent>(), isEmpty);

      peer.emitProtocolError(
        const TransportMalformedFrame(
          message: 'Invalid JSON on stdout',
          payloadLength: 12,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<AgentErrorEvent>(), hasLength(1));
    });

    test(
      'logs only safe summaries across Grok ignored notification paths',
      () async {
        final records = <LogEvent>[];
        void listener(OutputEvent event) {
          records.add(event.origin);
        }

        await resetAppLoggingForTesting();
        Logger.addOutputListener(listener);
        Logger.level = Level.all;
        configureAppLogging();
        addTearDown(() {
          Logger.removeOutputListener(listener);
          return resetAppLoggingForTesting();
        });

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
            .where((record) => record.level == Level.trace)
            .map((record) => record.message.toString())
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
        expect(fineMessages, everyElement(isNot(contains('raw='))));
        expect(provider.ignoredNotificationCountsForTesting, <String, int>{
          'future/method|unsupported notification method': 2,
          'session/update|unknown_kind': 2,
        });
        expect(provider.unmatchedNotificationCountsForTesting, <String, int>{
          'future/method': 2,
          'session/update': 2,
        });
        final renderedLogs = records.map((record) => record.message).join('\n');
        expect(renderedLogs, contains('future/method'));
        expect(renderedLogs, contains('session/update'));
        expect(renderedLogs, contains('count=1'));
        expect(renderedLogs, contains('count=2'));
        expect(renderedLogs, contains('itemType=future_update'));
        expect(renderedLogs, isNot(contains('private notification content')));
        expect(renderedLogs, isNot(contains('private update content')));
        expect(renderedLogs, isNot(contains('secret')));
        expect(renderedLogs, isNot(contains('content')));
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

    test('does not publish unsupported thread lifecycle ports', () {
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: _FakeJsonRpcPeer(),
      );
      addTearDown(provider.dispose);
      final bundle = nativeBundleFromGrok(provider);

      expect(bundle.threadArchival, isNull);
      expect(bundle.threadBranching, isNull);
      expect(bundle.threadCompaction, isNull);
      expect(bundle.turnSteering, isNull);
      expect(provider.capabilities.canArchiveThread, isFalse);
      expect(provider.capabilities.canForkThread, isFalse);
    });

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
          context: const AgentContext(projectPath: '/repo'),
        );
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: '/repo'),
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
        context: const AgentContext(projectPath: '/repo'),
      );
      await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: '/repo'),
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
        ).writeAsString('''
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

        expect(history.turns.single.modelId, 'grok-4.5');
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
        AgentModelList(
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
        final encoded = Uri.encodeComponent(projectPath.replaceAll('/', r'\'));
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
          context: const AgentContext(projectPath: '/repo'),
        );
        final sessionB = await provider.resumeSession(
          'sess-2',
          context: const AgentContext(projectPath: '/repo'),
        );
        expect(sessionA.id, isNot(sessionB.id));

        final turnAFuture = provider.sendMessage(
          session: sessionA,
          context: const AgentContext(projectPath: '/repo'),
          message: 'work A',
        );
        final turnBFuture = provider.sendMessage(
          session: sessionB,
          context: const AgentContext(projectPath: '/repo'),
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
          context: const AgentContext(projectPath: '/repo'),
        );
        final sessionB = await provider.resumeSession(
          'sess-2',
          context: const AgentContext(projectPath: '/repo'),
        );

        final turnAFuture = provider.sendMessage(
          session: sessionA,
          context: const AgentContext(projectPath: '/repo'),
          message: 'A',
        );
        final turnBFuture = provider.sendMessage(
          session: sessionB,
          context: const AgentContext(projectPath: '/repo'),
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
        context: const AgentContext(projectPath: '/repo'),
      );
      final first = provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: '/repo'),
        message: 'first',
      );
      await _waitUntil(() => peer.requestMethods.contains('session/prompt'));

      await expectLater(
        provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: '/repo'),
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
          context: const AgentContext(projectPath: '/repo'),
        );
        final promptFuture = provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: '/repo'),
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
        context: const AgentContext(projectPath: '/repo'),
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
          AgentQuestionResponse(requestId: 'ask-call-2'),
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
        context: const AgentContext(projectPath: '/repo'),
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
        context: const AgentContext(projectPath: '/repo'),
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
        context: const AgentContext(projectPath: '/repo'),
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
        const AgentPlanApprovalDecision(
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
          context: const AgentContext(projectPath: '/repo'),
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
          const AgentPlanApprovalDecision(
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
        context: const AgentContext(projectPath: '/repo'),
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

    test(
      'session_notification turn_completed emits absolute token usage for footer',
      () async {
        // Arrange：真实 Grok 常把带 usage 的 turn_completed 放在
        // x.ai/session_notification，而不是 session/update。
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
            'content': <String, Object?>{'type': 'text', 'text': 'done'},
            '_meta': <String, Object?>{'promptId': 'provider-prompt-1'},
          },
          '_meta': <String, Object?>{
            'eventId': 'message-before-terminal',
            'totalTokens': 900,
          },
        });
        await Future<void>.delayed(Duration.zero);

        // Act：经 session_notification 通道下发权威终态 + 计费用量。
        peer.emitNotification('_x.ai/session_notification', <String, Object?>{
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
              'apiDurationMs': 4500,
            },
          },
          '_meta': <String, Object?>{
            'eventId': 'session-notification-terminal',
          },
        });
        await Future<void>.delayed(Duration.zero);
        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await promptFuture;

        // Assert：turn footer 依赖的绝对用量事件必须出现，且只完成一次。
        expect(events.whereType<AgentTurnCompletedEvent>(), hasLength(1));
        final usage = events.whereType<AgentTokenUsageEvent>().single;
        expect(usage.isSessionCumulative, isFalse);
        expect(usage.tokenUsage.totalTokens, 1300);
        expect(usage.tokenUsage.inputTokens, 1000);
        expect(usage.tokenUsage.cachedInputTokens, 200);
        expect(usage.tokenUsage.lastTotalTokens, 900);
        final completed = events.whereType<AgentTurnCompletedEvent>().single;
        expect(completed.duration, const Duration(milliseconds: 4500));
      },
    );

    test(
      'late session_notification turn_completed supplements usage after RPC',
      () async {
        // Arrange：prompt RPC 先结束生命周期；迟到的 session_notification 补 usage。
        final peer = _FakeJsonRpcPeer()..promptCompleter = Completer<Object?>();
        final mapper = GrokAcpNotificationMapper();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
          notificationMapper: mapper,
        );
        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);
        addTearDown(provider.dispose);

        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
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

        // Act：running turn 已清空后，迟到的 session_notification 仍应补 token。
        peer.emitNotification('x.ai/session_notification', <String, Object?>{
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
          '_meta': <String, Object?>{'eventId': 'late-session-notification'},
        });
        await Future<void>.delayed(Duration.zero);

        // Assert
        expect(events.whereType<AgentTurnCompletedEvent>(), hasLength(1));
        final usage = events.whereType<AgentTokenUsageEvent>().single;
        expect(usage.isSessionCumulative, isFalse);
        expect(usage.tokenUsage.totalTokens, 1300);
        expect(usage.tokenUsage.lastTotalTokens, 1200);
        expect(mapper.diagnostics.terminalAccepted, 1);
        expect(mapper.diagnostics.duplicateTerminalIgnored, 1);
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
            error: const TransportClosed('JSON-RPC process exited'),
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
          final rawRpcError = (visibleError.raw['jsonRpcError']! as Map)
              .cast<String, Object?>();
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

    test(
      'compatibility: initialization failures remain typed and visible',
      () async {
        final processPeer = _FakeJsonRpcPeer()
          ..startError = const ProcessException(
            'grok',
            <String>[],
            'missing',
            2,
          );
        final processProvider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: processPeer,
        );
        final processEvents = <AgentEvent>[];
        processProvider.events.listen(processEvents.add);
        expect(processProvider.runtimeInfo, isNull);

        await expectLater(
          processProvider.initialize(),
          throwsA(isA<ProcessException>()),
        );
        await _waitUntil(
          () => processEvents.whereType<AgentErrorEvent>().isNotEmpty,
        );
        expect(
          processProvider.lifecycleState,
          AgentProviderLifecycleState.failed,
        );
        expect(processEvents.whereType<AgentErrorEvent>(), isNotEmpty);
        await processProvider.dispose();

        final genericPeer = _FakeJsonRpcPeer()
          ..startError = StateError('fixture');
        final genericProvider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: genericPeer,
        );
        final genericEvents = <AgentEvent>[];
        genericProvider.events.listen(genericEvents.add);
        await expectLater(genericProvider.initialize(), throwsStateError);
        await _waitUntil(
          () => genericEvents.whereType<AgentErrorEvent>().isNotEmpty,
        );
        expect(
          genericEvents.whereType<AgentErrorEvent>().single.message,
          contains('Could not start'),
        );
        await genericProvider.dispose();

        final authPeer = _FakeJsonRpcPeer()
          ..requestErrors['authenticate'] = StateError('expired fixture');
        final authProvider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: authPeer,
        );
        await authProvider.initialize();
        expect(authProvider.lifecycleState, AgentProviderLifecycleState.ready);
        await authProvider.dispose();
      },
    );

    test(
      'compatibility: default peer forwards dynamic process seams',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'grok-default-peer-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final executable = File(
          '${temp.path}${Platform.pathSeparator}'
          '${Platform.isWindows ? 'grok.cmd' : 'grok'}',
        );
        await executable.writeAsString('fixture');
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok.copyWith(
            command: executable.path,
            selectedModel: 'grok-model',
            selectedReasoningEffort: 'high',
          ),
          processStarter: (
            executable,
            arguments, {
            workingDirectory,
            environment,
          }) async => throw ProcessException(executable, arguments, 'fixture'),
        );

        await expectLater(
          provider.initialize(),
          throwsA(isA<TransportProcessExited>()),
        );
        await provider.dispose();
      },
    );

    test(
      'compatibility: invalid session and unknown decisions fail closed',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);

        await expectLater(
          provider.startSession(context: const AgentContext()),
          throwsStateError,
        );
        peer.requestResults['session/new'] = <String, Object?>{};
        await expectLater(
          provider.startSession(
            context: const AgentContext(projectPath: '/workspace'),
          ),
          throwsStateError,
        );
        peer.requestResults.remove('session/new');
        peer.requestErrors['session/load'] = StateError('load fixture');
        await expectLater(
          provider.resumeSession(
            'missing-session',
            context: const AgentContext(projectPath: '/workspace'),
          ),
          throwsStateError,
        );
        await provider.respondToPermission(
          AgentPermissionDecision(requestId: 'unknown', approved: true),
        );
        await provider.respondToQuestion(
          AgentQuestionResponse(requestId: 'unknown'),
        );
        await provider.respondToPlanApproval(
          const AgentPlanApprovalDecision(
            requestId: 'unknown',
            kind: AgentPlanApprovalDecisionKind.cancelled,
          ),
        );

        expect(
          (await provider.listThreads(
            query: AgentThreadListQuery(
              projectPath: '/workspace',
              limit: 20,
              archived: true,
            ),
          )).threads,
          isEmpty,
        );
        expect((await provider.listConversationModes()).presets, hasLength(2));
        await expectLater(
          provider.renameThread(threadId: 'thread', name: '  '),
          throwsArgumentError,
        );
      },
    );

    test(
      'compatibility: server filesystem requests always receive a response',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.initialize();
        final temp = await Directory.systemTemp.createTemp('grok-fs-requests-');
        addTearDown(() => temp.delete(recursive: true));
        final file = File('${temp.path}${Platform.pathSeparator}fixture.txt');
        await file.writeAsString('one\ntwo\nthree');

        peer.emitServerRequest(
          id: 'read-missing-path',
          method: 'fs/read_text_file',
          params: const <String, Object?>{},
        );
        peer.emitServerRequest(
          id: 'read-missing-file',
          method: 'fs/read_text_file',
          params: <String, Object?>{
            'path': '${temp.path}${Platform.pathSeparator}missing.txt',
          },
        );
        peer.emitServerRequest(
          id: 'read-lines',
          method: 'fs/read_text_file',
          params: <String, Object?>{
            'path': Uri.file(file.path).toString(),
            'line': '2',
            'limit': '1',
          },
        );
        peer.emitServerRequest(
          id: 'read-directory',
          method: 'fs/read_text_file',
          params: <String, Object?>{'path': temp.path},
        );
        peer.emitServerRequest(
          id: 'read-malformed-uri',
          method: 'fs/read_text_file',
          params: const <String, Object?>{'path': 'file:///%ZZ'},
        );
        peer.emitServerRequest(
          id: 'write',
          method: 'fs/write_text_file',
          params: const <String, Object?>{},
        );
        peer.emitServerRequest(
          id: 'unsupported',
          method: 'x.ai/unsupported',
          params: const <String, Object?>{},
        );
        peer.emitServerRequest(
          id: 'permission-empty',
          method: 'session/request_permission',
          params: const <String, Object?>{'sessionId': 'session'},
        );
        peer.emitServerRequest(
          id: 'question-empty',
          method: '_x.ai/ask_user_question',
          params: const <String, Object?>{'sessionId': 'session'},
        );
        peer.emitServerRequest(
          id: 'plan-invalid',
          method: '_x.ai/exit_plan_mode',
          params: const <String, Object?>{'sessionId': 'session'},
        );

        await _waitUntil(() => peer.responses.length >= 10);
        expect(peer.responses, hasLength(10));
        final readResponse = peer.responses.firstWhere(
          (response) => response['id'] == 'read-lines',
        );
        expect(
          (readResponse['result']! as Map<String, Object?>)['content'],
          'two',
        );
        expect(
          peer.responses.firstWhere(
            (response) => response['id'] == 'write',
          )['error'],
          isNotNull,
        );
      },
    );

    test(
      'compatibility: pending interactions resolve on replacement and close',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        final events = <AgentEvent>[];
        provider.events.listen(events.add);
        await provider.initialize();

        Map<String, Object?> questionParams() => <String, Object?>{
          'sessionId': 'session',
          'toolCallId': 'question-tool',
          'questions': <Object?>[
            <String, Object?>{'question': 'Continue?'},
          ],
        };
        peer.emitServerRequest(
          id: 'question-old',
          method: '_x.ai/ask_user_question',
          params: questionParams(),
        );
        await _waitUntil(
          () => events.whereType<AgentQuestionRequestedEvent>().isNotEmpty,
        );
        peer.emitServerRequest(
          id: 'question-new',
          method: '_x.ai/ask_user_question',
          params: questionParams(),
        );

        final planParams = <String, Object?>{
          'sessionId': 'session',
          'toolCallId': 'plan-tool',
          'planContent': 'Plan',
        };
        peer.emitServerRequest(
          id: 'plan-old',
          method: '_x.ai/exit_plan_mode',
          params: planParams,
        );
        await _waitUntil(
          () => events.whereType<AgentPlanApprovalRequestedEvent>().isNotEmpty,
        );
        peer.emitServerRequest(
          id: 'plan-new',
          method: 'x.ai/exit_plan_mode',
          params: planParams,
        );
        peer.emitServerRequest(
          id: 'permission-pending',
          method: 'session/request_permission',
          params: <String, Object?>{
            'sessionId': 'session',
            'options': <Object?>[
              <String, Object?>{
                'optionId': 'allow',
                'name': 'Allow',
                'kind': 'allow_once',
              },
            ],
          },
        );
        await _waitUntil(
          () => events.whereType<AgentPermissionRequestedEvent>().isNotEmpty,
        );
        await peer.closeNotificationStream();
        await Future<void>.delayed(Duration.zero);

        expect(events.whereType<AgentQuestionResolvedEvent>(), isNotEmpty);
        expect(events.whereType<AgentPlanApprovalResolvedEvent>(), isNotEmpty);
        expect(events.whereType<AgentPermissionResolvedEvent>(), isNotEmpty);
        await provider.dispose();
      },
    );

    test(
      'compatibility: unsupported notifications stay diagnostic-only',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);
        final events = <AgentEvent>[];
        final skillSignals = <void>[];
        provider.events.listen(events.add);
        provider.skillsChanged.listen(skillSignals.add);
        await provider.initialize();

        peer.emitNotification('_x.ai/unsupported', const <String, Object?>{});
        peer.emitNotification('unsupported', const <String, Object?>{});
        peer.emitNotification('x.ai/session_notification', <String, Object?>{
          'sessionId': 'session',
          'update': <String, Object?>{'sessionUpdate': 'plugins_changed'},
        });
        peer.emitNotification('x.ai/session_notification', <String, Object?>{
          'update': <String, Object?>{
            'sessionUpdate': 'last_turn_summary',
            'summary': 'Summary',
          },
        });
        peer.emitNotification('x.ai/session_notification', <String, Object?>{
          'sessionId': 'session',
          'update': <String, Object?>{
            'sessionUpdate': 'last_turn_summary',
            'summary': '',
          },
        });
        peer.emitNotification('x.ai/session_notification', <String, Object?>{
          'sessionId': 'session',
          'update': <String, Object?>{
            'sessionUpdate': 'last_turn_summary',
            'summary': 'Visible preview',
          },
        });
        peer.emitNotification(
          '_x.ai/session/prompt_complete',
          const <String, Object?>{},
        );
        peer.emitNotification(
          '_x.ai/session/prompt_complete',
          <String, Object?>{
            'sessionId': 'idle-session',
          },
        );
        peer.emitStderr('');
        peer.emitStderr('diagnostic only');

        await _waitUntil(
          () => events.whereType<AgentThreadPreviewUpdatedEvent>().isNotEmpty,
        );
        expect(skillSignals, hasLength(1));
        expect(
          events.whereType<AgentThreadPreviewUpdatedEvent>().single.preview,
          'Visible preview',
        );
        final ignoredKeys = provider.ignoredNotificationCountsForTesting.keys;
        expect(
          ignoredKeys.any((key) => key.startsWith('_x.ai/unsupported|')),
          isTrue,
        );
        expect(
          ignoredKeys.any((key) => key.startsWith('unsupported|')),
          isTrue,
        );
        expect(
          ignoredKeys.any(
            (key) => key.startsWith('_x.ai/session/prompt_complete|'),
          ),
          isTrue,
        );
      },
    );

    test(
      'compatibility: CLI model refresh covers replace and cached fallback',
      () async {
        final fresh = AgentModelList(
          models: <AgentModelInfo>[
            AgentModelInfo(
              id: 'grok-fresh',
              model: 'grok-fresh',
              displayName: 'Grok Fresh',
              contextWindowTokens: 1234,
            ),
          ],
        );
        final freshPeer = _FakeJsonRpcPeer()..includeModelState = false;
        final freshProvider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: freshPeer,
          modelsCli: _DelayedModelsCli(Future<AgentModelList>.value(fresh)),
        );
        addTearDown(freshProvider.dispose);
        expect(
          (await freshProvider.listModels()).models.single.id,
          'grok-fresh',
        );
        expect(
          (await freshProvider.listModels(forceRefresh: true)).models.single.id,
          'grok-fresh',
        );

        final cachedPeer = _FakeJsonRpcPeer();
        final cachedProvider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: cachedPeer,
          modelsCli: _DelayedModelsCli(
            Future<AgentModelList>.value(
              AgentModelList(models: const <AgentModelInfo>[]),
            ),
          ),
        );
        addTearDown(cachedProvider.dispose);
        await cachedProvider.initialize();
        final cached = await cachedProvider.refreshModels();
        expect(cached.models, hasLength(2));
      },
    );

    test(
      'compatibility: public history paths cache and enrich snapshots',
      () async {
        final history = _FakeSessionHistoryReader(
          snapshot: AgentThreadHistorySnapshot(
            threadId: 'history-session',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(id: 'unknown-model', modelId: 'missing'),
              AgentHistoryTurn(id: 'default-model'),
            ],
            raw: const <String, Object?>{'sessionPath': '/session/path'},
          ),
        );
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
          sessionHistoryReader: history,
        );
        addTearDown(provider.dispose);

        expect(
          (await provider.listThreads(
            query: AgentThreadListQuery(projectPath: '/workspace', limit: 10),
          )).threads,
          isEmpty,
        );
        final first = await provider.readThreadHistory(
          threadId: 'history-session',
          sessionPath: '/session/path',
        );
        final cached = await provider.readThreadHistory(
          threadId: 'history-session',
          sessionPath: '',
        );
        final matchingPath = await provider.readThreadHistory(
          threadId: 'history-session',
          sessionPath: '/session/path',
        );

        expect(history.historyReadCount, 1);
        expect(first.turns.first.modelContextWindow, 500000);
        expect(first.turns.last.modelContextWindow, 500000);
        expect(cached.turns, hasLength(2));
        expect(matchingPath.turns, hasLength(2));
      },
    );

    test(
      'compatibility: history remains available when initialization fails',
      () async {
        final peer = _FakeJsonRpcPeer()..startError = StateError('offline');
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
          sessionHistoryReader: _FakeSessionHistoryReader(
            snapshot: AgentThreadHistorySnapshot(
              threadId: 'offline-history',
              turns: <AgentHistoryTurn>[AgentHistoryTurn(id: 'turn')],
            ),
          ),
        );
        addTearDown(provider.dispose);

        final snapshot = await provider.readThreadHistory(
          threadId: 'offline-history',
        );
        expect(snapshot.turns.single.id, 'turn');
      },
    );

    test(
      'compatibility: prompt aliases, skills, modes, and cleanup branches',
      () async {
        final peer = _FakeJsonRpcPeer()
          ..requestResults['session/prompt'] = <String, Object?>{
            'stop_reason': 'end_turn',
          };
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);
        final session = await provider.startSession(
          context: const AgentContext(projectPath: '/workspace'),
        );

        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: '/workspace'),
          message: r'$review inspect',
          inputs: <AgentUserInput>[
            const AgentUserInput.skill(
              name: 'review',
              path: '/skills/review/SKILL.md',
            ),
          ],
        );
        await expectLater(
          provider.sendMessage(
            session: session,
            context: const AgentContext(projectPath: '/workspace'),
            message: 'unsupported mode',
            configuration: AgentTurnConfiguration(
              conversationMode: AgentConversationModeSelection(
                modeId: AgentConversationModeId.fromRaw('future-mode'),
                effectiveModelId: 'grok-4.5',
              ),
            ),
          ),
          throwsUnsupportedError,
        );

        peer.requestErrors['session/prompt'] = StateError('prompt failure');
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: '/workspace'),
          message: 'fails once',
        );
        peer.requestErrors.remove('session/prompt');
        await provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: '/workspace'),
          message: 'runs again',
        );
        expect(
          peer.requestMethods.where((method) => method == 'session/prompt'),
          hasLength(3),
        );
      },
    );

    test('compatibility: cancellation clears every parked interaction', () async {
      final peer = _FakeJsonRpcPeer()..promptCompleter = Completer<Object?>();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      final events = <AgentEvent>[];
      provider.events.listen(events.add);
      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/workspace'),
      );
      final send = provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: '/workspace'),
        message: 'work',
      );
      await _waitUntil(
        () => events.whereType<AgentTurnStartedEvent>().isNotEmpty,
      );
      peer.emitServerRequest(
        id: 'cancel-permission',
        method: 'session/request_permission',
        params: _permissionParams(session.id, 'cancel-permission-tool'),
      );
      peer.emitServerRequest(
        id: 'cancel-question',
        method: '_x.ai/ask_user_question',
        params: _questionParams(session.id, 'cancel-question-tool'),
      );
      peer.emitServerRequest(
        id: 'cancel-plan',
        method: '_x.ai/exit_plan_mode',
        params: _planParams(session.id, 'cancel-plan-tool'),
      );
      await _waitUntil(
        () =>
            events.whereType<AgentPermissionRequestedEvent>().isNotEmpty &&
            events.whereType<AgentQuestionRequestedEvent>().isNotEmpty &&
            events.whereType<AgentPlanApprovalRequestedEvent>().isNotEmpty,
      );

      await provider.respondToPermission(
        AgentPermissionDecision(
          requestId: events
              .whereType<AgentPermissionRequestedEvent>()
              .single
              .request
              .id,
          approved: false,
          cancelTurn: true,
        ),
      );
      await provider.respondToPlanApproval(
        const AgentPlanApprovalDecision(
          requestId: 'cancel-plan-tool',
          kind: AgentPlanApprovalDecisionKind.cancelled,
        ),
      );
      // Re-park a plan because the explicit cancelled decision above exercises
      // the protocol outcome while cancelTurn exercises provider cleanup.
      peer.emitServerRequest(
        id: 'cancel-plan-2',
        method: 'x.ai/exit_plan_mode',
        params: _planParams(session.id, 'cancel-plan-tool-2'),
      );
      await _waitUntil(
        () => events.whereType<AgentPlanApprovalRequestedEvent>().length == 2,
      );
      final turn = events.whereType<AgentTurnStartedEvent>().single.turn;
      await provider.cancelTurn(turn);
      peer.promptCompleter!.complete(<String, Object?>{
        'stopReason': 'cancelled',
      });
      await send;

      expect(
        peer.responses.any((item) => item['id'] == 'cancel-question'),
        isTrue,
      );
      expect(
        peer.responses.any((item) => item['id'] == 'cancel-plan-2'),
        isTrue,
      );
      expect(events.whereType<AgentQuestionResolvedEvent>(), isNotEmpty);
      await provider.dispose();
    });

    test(
      'compatibility: disposal resolves questions and permissions best effort',
      () async {
        Future<void> run({required bool failResponses}) async {
          final peer = _FakeJsonRpcPeer();
          final provider = GrokAcpAgentProvider(
            config: AgentProviderConfig.defaultGrok,
            peer: peer,
          );
          final events = <AgentEvent>[];
          provider.events.listen(events.add);
          await provider.initialize();
          peer.emitServerRequest(
            id: 'dispose-permission-$failResponses',
            method: 'session/request_permission',
            params: _permissionParams('session', 'permission-$failResponses'),
          );
          peer.emitServerRequest(
            id: 'dispose-question-$failResponses',
            method: '_x.ai/ask_user_question',
            params: _questionParams('session', 'question-$failResponses'),
          );
          await _waitUntil(
            () =>
                events.whereType<AgentPermissionRequestedEvent>().isNotEmpty &&
                events.whereType<AgentQuestionRequestedEvent>().isNotEmpty,
          );
          peer.sendResponseThrows = failResponses;
          await provider.dispose();
          expect(events.whereType<AgentQuestionResolvedEvent>(), isNotEmpty);
        }

        await run(failResponses: false);
        await run(failResponses: true);
      },
    );

    test(
      'compatibility: filesystem failures and response failures are contained',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: peer,
        );
        addTearDown(provider.dispose);
        await provider.initialize();
        final temp = await Directory.systemTemp.createTemp(
          'grok-invalid-utf8-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final invalid = File(
          '${temp.path}${Platform.pathSeparator}invalid.txt',
        );
        await invalid.writeAsBytes(<int>[0xff]);
        peer.emitServerRequest(
          id: 'invalid-utf8',
          method: 'fs/read_text_file',
          params: <String, Object?>{'path': invalid.path},
        );
        await _waitUntil(() => peer.responses.isNotEmpty);
        expect(peer.responses.single['error'], isNotNull);
        final lines = File('${temp.path}${Platform.pathSeparator}lines.txt');
        await lines.writeAsString('one\ntwo');
        peer.emitServerRequest(
          id: 'all-lines',
          method: 'fs/read_text_file',
          params: <String, Object?>{'path': lines.path, 'line': 1},
        );
        peer.emitServerRequest(
          id: 'malformed-file-uri',
          method: 'fs/read_text_file',
          params: const <String, Object?>{'path': 'file:///%ZZ'},
        );
        await _waitUntil(() => peer.responses.length >= 3);

        peer.sendResponseThrows = true;
        peer.emitServerRequest(
          id: 'response-failure',
          method: 'unsupported',
          params: const <String, Object?>{},
        );
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'compatibility: title polling falls back and tolerates no title',
      () async {
        Future<List<AgentEvent>> run(GrokSessionTitleSnapshot? title) async {
          final peer = _FakeJsonRpcPeer();
          final provider = GrokAcpAgentProvider(
            config: AgentProviderConfig.defaultGrok,
            peer: peer,
            sessionHistoryReader: _FakeSessionHistoryReader(title: title),
            generatedTitlePollDelays: const <Duration>[Duration.zero],
          );
          final events = <AgentEvent>[];
          provider.events.listen(events.add);
          final session = await provider.startSession(
            context: const AgentContext(projectPath: '/workspace'),
          );
          await provider.sendMessage(
            session: session,
            context: const AgentContext(projectPath: '/workspace'),
            message: 'title',
          );
          await Future<void>.delayed(Duration.zero);
          await provider.dispose();
          return events;
        }

        final fallback = await run(
          const GrokSessionTitleSnapshot(sessionSummary: 'Fallback title'),
        );
        expect(
          fallback.whereType<AgentThreadNameUpdatedEvent>().single.threadName,
          'Fallback title',
        );
        expect(await run(null), isNotEmpty);
      },
    );

    test('compatibility: set-model failure is best effort', () async {
      final peer = _FakeJsonRpcPeer()
        ..requestErrors['session/set_model'] = StateError('unsupported');
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok.copyWith(
          selectedModel: 'grok-4',
        ),
        peer: peer,
      );
      addTearDown(provider.dispose);
      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/workspace'),
      );
      expect(session.id, 'sess-1');
    });

    test(
      'compatibility: listModels returns initialize model state directly',
      () async {
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: _FakeJsonRpcPeer(),
        );
        addTearDown(provider.dispose);
        expect((await provider.listModels()).models, hasLength(2));
      },
    );

    test(
      'compatibility: model merging keeps rich incoming selectors',
      () async {
        final rich = AgentModelList(
          models: <AgentModelInfo>[
            AgentModelInfo(
              id: 'grok-4.5',
              model: 'grok-4.5',
              displayName: 'Grok rich',
              supportedReasoningEfforts: const <AgentModelReasoningEffort>[
                AgentModelReasoningEffort(effort: 'xhigh'),
              ],
              serviceTiers: const <AgentModelServiceTier>[
                AgentModelServiceTier(id: 'priority', name: 'Fast'),
              ],
            ),
          ],
        );
        final provider = GrokAcpAgentProvider(
          config: AgentProviderConfig.defaultGrok,
          peer: _FakeJsonRpcPeer(),
          modelsCli: _DelayedModelsCli(Future<AgentModelList>.value(rich)),
        );
        addTearDown(provider.dispose);
        await provider.initialize();
        final merged = (await provider.refreshModels()).models.firstWhere(
          (model) => model.id == 'grok-4.5',
        );
        expect(merged.contextWindowTokens, 500000);
        expect(merged.supportedReasoningEfforts.single.effort, 'xhigh');
        expect(merged.serviceTiers.single.id, 'priority');
      },
    );

    test(
      'compatibility: all Grok load replay method prefixes are suppressed',
      () async {
        for (final method in <String>[
          '_x.ai/session/update',
          'x.ai/session/update',
          '_x.ai/custom',
          'x.ai/custom',
        ]) {
          final peer = _FakeJsonRpcPeer()
            ..loadSessionEmitsReplay = true
            ..loadReplayMethod = method;
          final provider = GrokAcpAgentProvider(
            config: AgentProviderConfig.defaultGrok,
            peer: peer,
          );
          final events = <AgentEvent>[];
          provider.events.listen(events.add);
          await provider.resumeSession(
            'sess-replay',
            context: const AgentContext(projectPath: '/workspace'),
          );
          expect(events.whereType<AgentMessageDeltaEvent>(), isEmpty);
          await provider.dispose();
        }
      },
    );

    test('compatibility: prompt terminal aliases and late failure are deduplicated', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = GrokAcpAgentProvider(
        config: AgentProviderConfig.defaultGrok,
        peer: peer,
      );
      addTearDown(provider.dispose);
      final session = await provider.startSession(
        context: const AgentContext(projectPath: '/workspace'),
      );

      Future<void> terminalWith(Map<String, Object?> alias) async {
        peer.promptCompleter = Completer<Object?>();
        final send = provider.sendMessage(
          session: session,
          context: const AgentContext(projectPath: '/workspace'),
          message: 'alias',
        );
        await _waitUntil(() => peer.requestMethods.last == 'session/prompt');
        peer.emitNotification(
          '_x.ai/session/prompt_complete',
          <String, Object?>{
            'sessionId': session.id,
            ...alias,
          },
        );
        await Future<void>.delayed(Duration.zero);
        peer.promptCompleter!.complete(<String, Object?>{
          'stopReason': 'end_turn',
        });
        await send;
      }

      await terminalWith(<String, Object?>{'stop_reason': 'end_turn'});
      await terminalWith(<String, Object?>{'reason': 'end_turn'});

      peer.promptCompleter = Completer<Object?>();
      final lateFailure = provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: '/workspace'),
        message: 'late failure',
      );
      await _waitUntil(() => peer.requestMethods.last == 'session/prompt');
      peer.emitNotification('_x.ai/session/prompt_complete', <String, Object?>{
        'sessionId': session.id,
        'reason': 'end_turn',
      });
      await Future<void>.delayed(Duration.zero);
      peer.promptCompleter!.completeError(StateError('late failure'));
      await lateFailure;
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
      expect(page['updates']! as List<Object?>, hasLength(2));
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

Map<String, Object?> _permissionParams(String sessionId, String toolCallId) =>
    <String, Object?>{
      'sessionId': sessionId,
      'toolCall': <String, Object?>{
        'toolCallId': toolCallId,
        'title': 'Fixture permission',
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
    };

Map<String, Object?> _questionParams(String sessionId, String toolCallId) =>
    <String, Object?>{
      'sessionId': sessionId,
      'toolCallId': toolCallId,
      'questions': <Object?>[
        <String, Object?>{
          'question': 'Continue?',
          'options': <Object?>[
            <String, Object?>{'label': 'Yes'},
          ],
        },
      ],
    };

Map<String, Object?> _planParams(String sessionId, String toolCallId) =>
    <String, Object?>{
      'sessionId': sessionId,
      'toolCallId': toolCallId,
      'planContent': '# Fixture plan',
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
  final _protocolErrors = StreamController<TransportException>.broadcast();

  final requestMethods = <String>[];
  final requestParams = <Object?>[];
  final responses = <Map<String, Object?>>[];
  final notificationsSent = <String>[];
  final notificationParams = <Object?>[];
  final requestResults = <String, Object?>{};
  final requestErrors = <String, Object>{};

  Object? startError;
  bool sendResponseThrows = false;

  /// 模拟 session/load 期间推送 isReplay 更新。
  bool loadSessionEmitsReplay = false;
  String loadReplayMethod = 'session/update';

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
  Stream<TransportException> get protocolErrors => _protocolErrors.stream;

  @override
  Future<void> start() async {
    final error = startError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requestMethods.add(method);
    requestParams.add(params);
    final error = requestErrors[method];
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    if (requestResults.containsKey(method)) {
      return requestResults[method];
    }
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
          emitNotification(loadReplayMethod, <String, Object?>{
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
    if (sendResponseThrows) {
      throw StateError('fixture response failure');
    }
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

  void emitProtocolError(TransportException error) {
    _protocolErrors.add(error);
  }

  void emitStderr(String line) {
    _stderr.add(line);
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

class _FakeSessionHistoryReader extends GrokSessionHistoryReader {
  _FakeSessionHistoryReader({
    AgentThreadHistorySnapshot? snapshot,
    this.title,
  }) : snapshot =
           snapshot ??
           AgentThreadHistorySnapshot(
             threadId: 'empty',
             turns: const <AgentHistoryTurn>[],
           );

  final AgentThreadHistorySnapshot snapshot;
  final GrokSessionTitleSnapshot? title;
  int historyReadCount = 0;

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
    required String providerId,
    Map<String, String>? environment,
  }) async => AgentThreadPage(
    threads: const <AgentThreadSummary>[],
    nextCursor: null,
  );

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    required String providerId,
    String? projectPath,
    String? sessionPath,
    Map<String, String>? environment,
  }) async {
    historyReadCount += 1;
    return snapshot;
  }

  @override
  Future<GrokSessionTitleSnapshot?> readSessionTitleSnapshot({
    required String threadId,
    String? projectPath,
    String? sessionPath,
    Map<String, String>? environment,
  }) async => title;
}
