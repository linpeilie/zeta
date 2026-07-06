import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

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
        'model/list',
        'thread/start',
        'turn/start',
      ]);
      expect(peer.notificationsSent, contains('initialized'));
      await provider.dispose();
    });

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

      expect(events.whereType<AgentMessageDeltaEvent>().single.delta, 'Hello');
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
        expect(delta.phase, AgentMessagePhase.commentary);

        final update = events.whereType<AgentMessageUpdatedEvent>().single;
        expect(update.messageId, 'message-1');
        expect(update.phase, AgentMessagePhase.commentary);
        expect(update.status, AgentMessageStatus.completed);
        expect(update.duration, const Duration(seconds: 102));
        expect(events.whereType<AgentToolCallEvent>(), isEmpty);

        await subscription.cancel();
        await provider.dispose();
      },
    );

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
          },
        );

        final approval = await approvalFuture;
        expect(approval.request.kind, AgentPermissionKind.commandExecution);
        expect(approval.request.command, 'dart format .');
        expect(approval.request.sessionId, 'thread-1');
        expect(approval.request.turnId, 'turn-1');

        await provider.respondToPermission(
          AgentPermissionDecision(
            requestId: approval.request.id,
            approved: true,
          ),
        );

        expect(peer.responses['approval-1'], <String, Object?>{
          'decision': 'accept',
        });
        await provider.dispose();
      },
    );

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

      expect(peer.requestMethods, <String>[
        'initialize',
        'model/list',
        'thread/list',
      ]);
      expect(peer.requestParams.last, <String, Object?>{
        'cwd': '/repo',
        'limit': 5,
        'cursor': 'cursor-1',
        'sortKey': 'recency_at',
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

    test('reads thread history with turns and maps items', () async {
      final peer = _FakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );

      final history = await provider.readThreadHistory(threadId: 'thread-1');

      expect(peer.requestMethods, <String>[
        'initialize',
        'model/list',
        'thread/read',
      ]);
      expect(peer.requestParams.last, <String, Object?>{
        'threadId': 'thread-1',
        'includeTurns': true,
        'itemsView': 'full',
      });
      expect(history.threadId, 'thread-1');
      expect(_historyEntries(history), hasLength(5));
      expect(history.turns.map((turn) => turn.id), <String>['turn-1']);
      expect(history.currentTurn?.id, 'turn-1');

      final turn = _historyTurn(history, 'turn-1');
      expect(turn.entries, hasLength(5));
      expect(turn.status, AgentHistoryTurnStatus.completed);
      expect(turn.startedAt, DateTime.parse('2026-07-04T06:00:00.000Z'));
      expect(turn.completedAt, DateTime.parse('2026-07-04T06:00:03.000Z'));
      expect(turn.duration, const Duration(seconds: 3));
      expect(turn.cwd, '/repo');
      expect(turn.model, 'gpt-5');
      expect(turn.modelContextWindow, 258400);
      expect(turn.collaborationMode, 'Default');

      final userMessage =
          _historyEntries(history)[0] as AgentHistoryMessageEntry;
      expect(userMessage.role, AgentMessageRole.user);
      expect(userMessage.text, 'Hello Agent');

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
      await provider.dispose();
    });

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
            'started_at': '2026-07-04T06:00:00.000Z',
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
            'completed_at': '2026-07-04T06:00:06.000Z',
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

      expect(peer.requestMethods, <String>['initialize', 'model/list']);
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
      expect(turn.collaborationMode, 'Default');

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

        expect(peer.requestMethods, <String>['initialize', 'model/list']);
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
                    'header': '日志去向',
                    'question': '主要要做到哪一级？',
                    'options': <Object?>[
                      <String, Object?>{'label': '开发日志 (Recommended)'},
                      <String, Object?>{'label': '本地日志文件'},
                    ],
                  },
                  <String, Object?>{
                    'id': 'logging_api',
                    'header': '实现方式',
                    'question': '日志 API 想偏向哪种实现？',
                    'options': <Object?>[
                      <String, Object?>{'label': '内置封装 (Recommended)'},
                      <String, Object?>{'label': 'logging 包'},
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
                    'answers': <String>['开发日志 (Recommended)'],
                  },
                  'logging_api': <String, Object?>{
                    'answers': <String>['logging 包'],
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
        expect(first.question, '主要要做到哪一级？');
        expect(first.header, '日志去向');
        expect(first.options, <String>['开发日志 (Recommended)', '本地日志文件']);
        expect(first.answers, <String>['开发日志 (Recommended)']);

        final second = entry.qaPairs![1];
        expect(second.questionId, 'logging_api');
        expect(second.question, '日志 API 想偏向哪种实现？');
        expect(second.answers, <String>['logging 包']);

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

      expect(peer.requestMethods, <String>['initialize', 'model/list']);
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
      'falls back to thread/read when local session path is missing',
      () async {
        final peer = _FakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );

        final history = await provider.readThreadHistory(threadId: 'thread-1');

        expect(peer.requestMethods, <String>[
          'initialize',
          'model/list',
          'thread/read',
        ]);
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

      expect(peer.requestMethods, <String>[
        'initialize',
        'model/list',
        'thread/read',
      ]);
      expect(_historyEntries(history), hasLength(5));
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
      expect(turn.tokenUsage!.outputTokens, 1552);
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
        expect(usageEvent.tokenUsage.outputTokens, 300);
        expect(usageEvent.tokenUsage.reasoningOutputTokens, 50);
        expect(usageEvent.tokenUsage.lastTotalTokens, 1300);
      },
    );

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

    test('fetches model list after initialize and emits event', () async {
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
        await Future<void>.delayed(Duration.zero);

        expect(events.whereType<AgentErrorEvent>(), isEmpty);
      },
    );

    test('keeps non-MCP stderr visible as AgentErrorEvent', () async {
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
      peer.emitStderr('Codex fatal: failed to initialize model provider');
      await Future<void>.delayed(Duration.zero);

      final error = events.whereType<AgentErrorEvent>().single;
      expect(error.message, 'Codex stderr');
      expect(error.details, 'Codex fatal: failed to initialize model provider');
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
      expect(params['reasoningEffort'], 'high');
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
      expect(params.containsKey('reasoningEffort'), isFalse);
      expect(params.containsKey('serviceTier'), isFalse);
    });
  });
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
  _FakeJsonRpcPeer({this._startCompleter});

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
  final Completer<void>? _startCompleter;
  int startCalls = 0;

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
    return switch (method) {
      'initialize' => <String, Object?>{'ok': true},
      'thread/start' => <String, Object?>{
        'thread': <String, Object?>{'id': 'thread-1'},
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
              'startedAt': '2026-07-04T06:00:00.000Z',
              'completedAt': '2026-07-04T06:00:03.000Z',
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
              ],
            },
          ],
        },
      },
      'turn/start' => <String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      },
      'model/list' => <String, Object?>{
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
    responses[id] = result;
  }

  @override
  Future<void> close() async {
    await _notifications.close();
    await _serverRequests.close();
    await _stderrLines.close();
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

List<AgentHistoryEntry> _historyEntries(AgentThreadHistorySnapshot history) {
  return <AgentHistoryEntry>[for (final turn in history.turns) ...turn.entries];
}

AgentHistoryTurn _historyTurn(
  AgentThreadHistorySnapshot history,
  String turnId,
) {
  return history.turns.singleWhere((turn) => turn.id == turnId);
}
