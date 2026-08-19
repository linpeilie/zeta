import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:codex_app_server_client/src/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:test/test.dart';

void main() {
  group('Codex protocol compatibility', () {
    test('maps tolerant ThreadItem and input variants', () {
      final toolItems = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'mcp',
          'type': 'mcpToolCall',
          'server': 'filesystem',
          'tool': 'read_file',
          'result': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'done'},
          ],
          'locations': <Object?>[
            '/repo/a.dart',
            <String, Object?>{'path': '/repo/b.dart'},
            7,
          ],
        },
        <String, Object?>{
          'id': 'dynamic',
          'type': 'dynamicToolCall',
          'namespace': 'demo',
          'tool': 'run',
          'contentItems': <Object?>[
            <String, Object?>{'content': 'dynamic result'},
          ],
        },
        <String, Object?>{
          'id': 'image',
          'type': 'imageGeneration',
          'savedPath': '/tmp/image.png',
        },
        <String, Object?>{
          'id': 'web',
          'type': 'webSearch',
          'action': <String, Object?>{
            'type': 'findInPage',
            'url': 'https://example.test',
            'pattern': 'needle',
          },
        },
        <String, Object?>{
          'id': 'fallback',
          'type': 'futureTool',
          'arguments': <String, Object?>{'answer': 42},
        },
      ];

      final tools = toolItems
          .map(CodexProtocolTestHarness.mapToolItem)
          .toList();
      expect(tools, everyElement(isNotNull));
      expect(tools.first!.title, contains('filesystem'));
      expect(tools.first!.locations, hasLength(3));
      expect(tools[3]!.content, contains('needle'));

      final systemItems = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'review',
          'type': 'exitedReviewMode',
          'review': 'finished',
        },
        <String, Object?>{
          'id': 'sleep-1',
          'type': 'sleep',
          'durationMs': 60000,
        },
        <String, Object?>{
          'id': 'sleep-2',
          'type': 'sleep',
          'durationMs': 61000,
        },
        <String, Object?>{
          'id': 'sub-1',
          'type': 'subAgentActivity',
          'kind': 'interacted',
          'agentPath': 'worker',
        },
        <String, Object?>{
          'id': 'sub-2',
          'type': 'subAgentActivity',
          'kind': 'interrupted',
        },
        <String, Object?>{'id': 'sub-3', 'type': 'subAgentActivity'},
      ];
      final events = systemItems
          .map(CodexProtocolTestHarness.mapSystemItem)
          .toList();
      expect(events, everyElement(isNotNull));
      expect(events[1]!.description, contains('1 minutes'));
      expect(events[2]!.description, contains('1 seconds'));

      expect(
        CodexProtocolTestHarness.userInputText(<Object?>[
          <String, Object?>{'type': 'skill', 'id': 'flutter'},
          <String, Object?>{'type': 'mention', 'name': 'README'},
          <String, Object?>{'type': 'future', 'content': 'fallback'},
        ]),
        r'$flutter'
        '\n@README\nfallback',
      );
      expect(CodexProtocolTestHarness.userInputText('plain'), 'plain');
      expect(
        CodexProtocolTestHarness.userInputLocalImagePaths(<Object?>[
          <String, Object?>{
            'type': 'input_text',
            'text': '<image path="/tmp/a.png">',
          },
          <String, Object?>{'type': 'localImage', 'path': '/tmp/b.png'},
        ]),
        <String>['/tmp/a.png', '/tmp/b.png'],
      );
      expect(
        CodexProtocolTestHarness.commandActionSummaries(<Object?>[
          <String, Object?>{'type': 'read', 'name': 'A'},
          <String, Object?>{'type': 'read', 'path': '/b'},
          <String, Object?>{'type': 'listFiles', 'path': '/repo'},
          <String, Object?>{'type': 'search', 'query': 'x', 'path': '/repo'},
          <String, Object?>{'type': 'search', 'query': 'y'},
          <String, Object?>{'type': 'search', 'path': '/repo'},
          <String, Object?>{'type': 'unknown', 'command': 'custom'},
          <String, Object?>{'type': 'future', 'command': 'future command'},
        ]),
        hasLength(8),
      );
      expect(CodexProtocolTestHarness.usageWindowLabel(10080), '1 week');
      expect(CodexProtocolTestHarness.usageWindowLabel(2880), '2 days');
      expect(CodexProtocolTestHarness.usageWindowLabel(60), '1 hour');
      expect(
        CodexProtocolTestHarness.usageWindowLabel(90),
        '1 hours 30 minutes',
      );
      expect(CodexProtocolTestHarness.usageWindowLabel(1), '1 minute');
    });

    test('maps approval request and response variants', () {
      JsonRpcRequest request(
        String method, [
        Map<String, Object?> params = const {},
      ]) => JsonRpcRequest(
        id: method,
        method: method,
        params: params,
        raw: <String, Object?>{'method': method},
      );

      expect(
        CodexProtocolTestHarness.approvalRejection(
          request('attestation/generate'),
        ),
        isNotNull,
      );
      expect(
        CodexProtocolTestHarness.approvalRejection(
          request('item/fileChange/requestApproval'),
        ),
        isNull,
      );
      expect(
        CodexProtocolTestHarness.mapApproval(request('future/request')).kind,
        AgentPermissionKind.other,
      );

      Object? respond(
        String method, {
        required bool approved,
        bool cancelTurn = false,
        AgentCommandApprovalDecisionKind? commandDecision,
      }) => CodexProtocolTestHarness.approvalResponse(
        request(method, <String, Object?>{
          'permissions': <String, Object?>{'network': true},
        }),
        AgentPermissionDecision(
          requestId: method,
          approved: approved,
          cancelTurn: cancelTurn,
          commandDecision: commandDecision,
        ),
      );

      expect(
        respond('item/fileChange/requestApproval', approved: true),
        <String, Object?>{'decision': 'accept'},
      );
      expect(
        respond('item/fileChange/requestApproval', approved: false),
        <String, Object?>{'decision': 'decline'},
      );
      expect(
        respond('item/permissions/requestApproval', approved: true),
        containsPair('permissions', isNotNull),
      );
      expect(
        respond('item/permissions/requestApproval', approved: false),
        containsPair('scope', 'turn'),
      );
      expect(respond('execCommandApproval', approved: true), <String, Object?>{
        'decision': 'approved',
      });
      expect(respond('execCommandApproval', approved: false), <String, Object?>{
        'decision': 'denied',
      });
      expect(respond('applyPatchApproval', approved: true), <String, Object?>{
        'decision': 'approved',
      });
      expect(
        respond(
          'item/commandExecution/requestApproval',
          approved: false,
          commandDecision: AgentCommandApprovalDecisionKind.cancel,
        ),
        <String, Object?>{'decision': 'cancel'},
      );
      expect(
        respond('item/commandExecution/requestApproval', approved: true),
        <String, Object?>{'decision': 'accept'},
      );
      expect(
        respond('item/commandExecution/requestApproval', approved: false),
        <String, Object?>{'decision': 'decline'},
      );
    });

    test('maps malformed and extended skills responses', () {
      expect(
        () => CodexProtocolTestHarness.mapSkills(null),
        throwsFormatException,
      );
      expect(
        () => CodexProtocolTestHarness.mapSkills(const <String, Object?>{}),
        throwsFormatException,
      );
      final result = CodexProtocolTestHarness.mapSkills(
        <String, Object?>{
          'data': <Object?>[
            1,
            <String, Object?>{'cwd': '/repo', 'skills': 'invalid'},
            <String, Object?>{
              'cwd': ' /repo ',
              'skills': <Object?>[
                null,
                <String, Object?>{'name': '', 'path': '/bad'},
                <String, Object?>{
                  'name': 'disabled',
                  'path': <String, Object?>{'absolutePath': '/skill/disabled'},
                  'enabled': false,
                },
                <String, Object?>{
                  'name': 'valid',
                  'path': <String, Object?>{'value': '/skill/valid'},
                  'interface': <String, Object?>{
                    'displayName': 'Valid',
                    'shortDescription': 'Short',
                    'defaultPrompt': 'Run',
                  },
                },
              ],
              'errors': <Object?>[
                ' plain error ',
                <String, Object?>{'summary': 'summary error'},
                <String, Object?>{'error': 'error field'},
                3,
              ],
            },
          ],
        },
      );
      expect(result.invalidEntryCount, 2);
      expect(result.droppedSkillCount, 3);
      expect(result.catalog.entries.single.skills.single.name, 'valid');
      expect(result.catalog.entries.single.errors, hasLength(3));
    });

    test('maps ignored and alternate notification shapes', () {
      JsonRpcNotification notification(
        String method, [
        Map<String, Object?> params = const <String, Object?>{},
      ]) => JsonRpcNotification(
        method: method,
        params: params,
        raw: <String, Object?>{'method': method, 'params': params},
      );

      final cases = <JsonRpcNotification>[
        notification('thread/started', <String, Object?>{
          'thread': <String, Object?>{'id': 't', 'name': 'Thread'},
        }),
        notification('thread/started'),
        notification('thread/status/changed', <String, Object?>{
          'status': <String, Object?>{'type': 'idle'},
        }),
        notification('thread/status/changed', <String, Object?>{
          'threadId': 't',
        }),
        notification('thread/name/updated'),
        notification('thread/compacted'),
        notification('thread/settings/updated'),
        notification('turn/started'),
        notification('turn/completed'),
        notification('item/agentMessage/delta', <String, Object?>{
          'delta': 'x',
        }),
        notification('item/agentMessage/delta'),
        notification('item/reasoning/textDelta'),
        notification('item/reasoning/textDelta', <String, Object?>{
          'itemId': 'i',
        }),
        notification('item/reasoning/summaryTextDelta'),
        notification('item/plan/delta', <String, Object?>{'delta': 'plan'}),
        notification('item/plan/delta'),
        notification('turn/plan/updated'),
        notification('turn/diff/updated', <String, Object?>{'threadId': 't'}),
        notification('turn/diff/updated', <String, Object?>{
          'threadId': 't',
          'turnId': 'turn',
        }),
        notification('turn/diff/updated', <String, Object?>{
          'threadId': 't',
          'turnId': 'turn',
          'diff': 'not a diff',
        }),
        notification('turn/diff/updated'),
        notification('item/started'),
        notification('item/started', <String, Object?>{
          'item': <String, Object?>{
            'id': 'message',
            'type': 'agentMessage',
            'status': 'inProgress',
          },
        }),
        notification('item/started', <String, Object?>{
          'item': <String, Object?>{'id': 'system', 'type': 'sleep'},
        }),
        notification('item/completed'),
        notification('item/mcpToolCall/progress', <String, Object?>{
          'itemId': 'i',
        }),
        notification('item/commandExecution/outputDelta'),
        notification('thread/tokenUsage/updated', <String, Object?>{
          'threadId': 't',
          'tokenUsage': <String, Object?>{'totalTokens': 1},
        }),
        notification('serverRequest/resolved', <String, Object?>{
          'requestId': 1,
        }),
        notification('serverRequest/resolved'),
        notification('model/rerouted', <String, Object?>{'threadId': 't'}),
        notification('model/rerouted', <String, Object?>{
          'threadId': 't',
          'turnId': 'turn',
        }),
        notification('model/rerouted'),
        notification('deprecationNotice'),
        notification('error'),
        notification('configWarning'),
        notification('item/autoApprovalReview/started'),
        notification('item/autoApprovalReview/started', <String, Object?>{
          'threadId': 't',
        }),
        notification('item/autoApprovalReview/started', <String, Object?>{
          'threadId': 't',
          'turnId': 'turn',
          'reviewId': 'review',
        }),
        notification('thread/archived'),
        notification('future/notification'),
      ];
      final results = cases
          .map(CodexProtocolTestHarness.mapNotification)
          .toList();
      expect(
        results.where((result) => result.ignoredReason != null),
        isNotEmpty,
      );
      expect(results.last.unmatchedMethod, 'future/notification');

      final status = CodexProtocolTestHarness.mapNotification(
        notification('thread/status/changed', <String, Object?>{
          'threadId': 't',
          'status': <String, Object?>{
            'type': 'systemError',
            'activeFlags': <Object?>['waitingOnApproval', 'waitingOnUserInput'],
          },
        }),
      );
      expect(status.events, hasLength(1));

      final stateful = CodexProtocolTestHarness.mapNotificationSequence(
        <JsonRpcNotification>[
          notification('turn/diff/updated', <String, Object?>{
            'threadId': 't',
            'turnId': 'turn',
            'diff':
                'diff --git a/lib/a.dart b/lib/a.dart\n'
                '--- a/lib/a.dart\n'
                '+++ b/lib/a.dart\n'
                '@@ -1 +1 @@\n'
                '-old\n'
                '+new',
          }),
          notification('item/fileChange/patchUpdated', <String, Object?>{
            'threadId': 't',
            'turnId': 'turn',
            'itemId': 'file',
            'changes': <Object?>[
              <String, Object?>{
                'path': 'lib/a.dart',
                'kind': <String, Object?>{'type': 'update'},
                'diff': '[TOOL PATCH]',
              },
            ],
          }),
          notification('thread/tokenUsage/updated', <String, Object?>{
            'threadId': 't',
            'tokenUsage': <String, Object?>{
              'total': <String, Object?>{'totalTokens': 1},
            },
          }),
        ],
      );
      expect(stateful.first, hasLength(1));
      expect(stateful[1], hasLength(2));
      expect(stateful.last, hasLength(1));
    });

    test('parses alternate JSONL and thread/read shapes', () {
      String line(String type, Map<String, Object?> payload) =>
          jsonEncode(<String, Object?>{'type': type, 'payload': payload});

      final snapshot = CodexProtocolTestHarness.parseJsonl(<String>[
        '',
        '{bad json',
        '[]',
        line('session_meta', <String, Object?>{'id': 'session'}),
        line('turn_context', <String, Object?>{
          'turn_id': 'turn',
          'cwd': '/repo',
          'model': 'gpt',
        }),
        line('event_msg', <String, Object?>{
          'type': 'task_started',
          'turn_id': 'turn',
        }),
        line('response_item', <String, Object?>{
          'type': 'message',
          'role': 'user',
          'turn_id': 'turn',
          'content': <Object?>[
            <String, Object?>{'type': 'input_text', 'text': 'hello'},
          ],
        }),
        line('event_msg', <String, Object?>{
          'type': 'task_complete',
          'turn_id': 'turn',
          'duration_ms': 12.5,
        }),
        jsonEncode(<String, Object?>{
          'type': 'event_msg',
          'timestamp': 2.5,
          'payload': <String, Object?>{
            'type': 'task_complete',
            'turn_id': 'turn',
          },
        }),
        line('event_msg', <String, Object?>{
          'type': 'turn_aborted',
          'turn_id': 'turn',
        }),
        line('event_msg', <String, Object?>{
          'type': 'mcp_tool_call_end',
          'turn_id': 'turn',
          'call_id': 'mcp',
          'invocation': <String, Object?>{
            'server': 'demo',
            'tool': 'read_mcp_resource',
            'arguments': <String, Object?>{'uri': 'file:///a'},
          },
          'result': <String, Object?>{
            'Ok': <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'text': 'ok'},
              ],
            },
          },
        }),
        line('event_msg', <String, Object?>{
          'type': 'patch_apply_end',
          'turn_id': 'turn',
          'changes': <String, Object?>{'lib/a.dart': 'updated'},
          'stdout': 'patched',
        }),
        line('event_msg', <String, Object?>{
          'type': 'web_search_end',
          'turn_id': 'turn',
          'query': 'fallback query',
          'action': <String, Object?>{'query': 'search query'},
        }),
        line('event_msg', <String, Object?>{
          'type': 'request_permissions',
          'turn_id': 'turn',
          'reason': 'needed',
        }),
        line('event_msg', <String, Object?>{
          'type': 'guardian_warning',
          'turn_id': 'turn',
          'title': 'Warning',
        }),
        line('event_msg', <String, Object?>{
          'type': 'system_notice',
          'turn_id': 'turn',
          'description': 'Notice',
        }),
        jsonEncode(<String, Object?>{
          'type': 'event_msg',
          'timestamp': 3.5,
          'payload': <String, Object?>{
            'type': 'turn_aborted',
            'turn_id': 'turn',
          },
        }),
        line('response_item', <String, Object?>{
          'type': 'future_warning',
          'turn_id': 'turn',
          'title': 'Future warning',
        }),
        line('event_msg', <String, Object?>{
          'type': 'patch_apply_end',
          'turn_id': 'turn',
          'stdout': 'prefix\nOutput:\npatch output',
        }),
        line('event_msg', <String, Object?>{
          'type': 'mcp_tool_call_end',
          'turn_id': 'turn',
          'invocation': <String, Object?>{
            'tool': 'custom_tool',
            'arguments': <String, Object?>{'value': 1},
          },
          'result': <String, Object?>{},
        }),
        line('event_msg', <String, Object?>{
          'type': 'web_search_begin',
          'turn_id': 'turn',
          'query': 'payload query',
        }),
        line('response_item', <String, Object?>{
          'type': 'function_call',
          'turn_id': 'turn',
          'call_id': 'permission',
          'name': 'request_permissions',
          'arguments': jsonEncode(<String, Object?>{'reason': 'needed'}),
        }),
        line('response_item', <String, Object?>{
          'type': 'web_search_call',
          'turn_id': 'turn',
          'query': 'response payload query',
        }),
      ]);
      expect(snapshot.threadId, 'session');
      expect(snapshot.turns, hasLength(1));

      final read = CodexProtocolTestHarness.mapThreadRead(<String, Object?>{
        'thread': <String, Object?>{
          'id': 'remote',
          'turns': <Object?>[
            <String, Object?>{
              'id': 'running',
              'status': 'active',
              'startedAt': 1.5,
              'items': <Object?>[
                <String, Object?>{
                  'id': 'user',
                  'type': 'userMessage',
                  'content': <Object?>[
                    <String, Object?>{'type': 'skill', 'name': 'testing'},
                  ],
                },
                <String, Object?>{
                  'id': 'review',
                  'type': 'exitedReviewMode',
                  'review': 'done',
                },
              ],
            },
            <String, Object?>{
              'id': 'failed',
              'status': 'failed',
              'completedAtMs': 2000,
              'error': <String, Object?>{
                'message': 'boom',
                'codexErrorInfo': <String, Object?>{'serverOverloaded': true},
              },
              'tokenUsage': <String, Object?>{
                'total': <String, Object?>{
                  'input_tokens': 10,
                  'cached_input_tokens': 2,
                  'output_tokens': 8,
                  'reasoning_output_tokens': 3,
                  'total_tokens': 18,
                },
                'last': <String, Object?>{
                  'input_tokens': 4,
                  'cached_input_tokens': 1,
                  'output_tokens': 3,
                  'reasoning_output_tokens': 1,
                  'total_tokens': 7,
                },
                'model_context_window': 100,
              },
            },
            <String, Object?>{
              'id': 'legacy-usage',
              'total_token_usage': <String, Object?>{
                'input_tokens': 3,
                'output_tokens': 2,
                'reasoning_output_tokens': 1,
                'total_tokens': 5,
              },
              'last_token_usage': <String, Object?>{
                'input_tokens': 2,
                'output_tokens': 1,
                'total_tokens': 3,
              },
              'model_context_window': 50,
            },
          ],
        },
      });
      expect(read.turns, hasLength(3));
      expect(read.turns[1].errorCode, 'serverOverloaded');
      expect(read.turns[1].tokenUsage?.totalTokens, 18);
      expect(read.turns[2].tokenUsage?.totalTokens, 5);
    });

    test('reads missing paths and overlays remote terminal metadata', () async {
      expect(
        await CodexProtocolTestHarness.readSessionFile(
          'missing',
          '${Directory.systemTemp.path}/definitely-missing-zeta.jsonl',
        ),
        isNull,
      );
      final file = File(
        '${Directory.systemTemp.path}/zeta-codex-read-failure.jsonl',
      );
      await file.writeAsString('{}');
      addTearDown(file.delete);
      expect(
        await CodexProtocolTestHarness.readSessionFile(
          'failure',
          file.path,
          failRead: true,
        ),
        isNull,
      );

      final localTurn = AgentHistoryTurn(
        id: 'turn',
        status: AgentHistoryTurnStatus.completed,
      );
      final remoteTurn = AgentHistoryTurn(
        id: 'turn',
        status: AgentHistoryTurnStatus.failed,
        errorMessage: 'remote failure',
      );
      final merged = CodexProtocolTestHarness.mergeHistory(
        local: AgentThreadHistorySnapshot(
          threadId: 'thread',
          turns: <AgentHistoryTurn>[localTurn],
        ),
        remote: AgentThreadHistorySnapshot(
          threadId: 'thread',
          turns: <AgentHistoryTurn>[remoteTurn],
        ),
      );
      expect(merged.turns.single.status, AgentHistoryTurnStatus.failed);
      expect(merged.turns.single.errorMessage, 'remote failure');

      final alreadyFailed = CodexProtocolTestHarness.mergeHistory(
        local: AgentThreadHistorySnapshot(
          threadId: 'thread',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn',
              status: AgentHistoryTurnStatus.failed,
              errorMessage: '',
            ),
          ],
        ),
        remote: AgentThreadHistorySnapshot(
          threadId: 'thread',
          turns: <AgentHistoryTurn>[remoteTurn],
        ),
      );
      expect(alreadyFailed.turns.single.status, AgentHistoryTurnStatus.failed);
      expect(alreadyFailed.turns.single.errorMessage, 'remote failure');
    });

    test('covers runtime fallback and failure classification contracts', () {
      final labels = CodexProtocolTestHarness.fallbackLabels('Codex');
      expect(labels.cancelled, 'User cancelled');
      expect(labels.startFailure, contains('Codex'));
      expect(labels.warning, contains('Codex'));

      final runtime = CodexProtocolTestHarness.runtimeInfo(
        const <String, Object?>{},
        configuredVersion: 'codex-cli 0.144.5',
      );
      expect(runtime.cliVersion, '0.144.5');
      expect(
        CodexProtocolTestHarness.semanticVersionContract().lessOrEqual,
        isTrue,
      );

      expect(
        CodexProtocolTestHarness.classifyConversationModeFailure(
          const JsonRpcException(
            JsonRpcError(
              code: -32000,
              message: 'Experimental API is not enabled',
            ),
          ),
        ),
        'unsupportedRuntime',
      );
      expect(
        CodexProtocolTestHarness.classifyConversationModeFailure(
          TimeoutException('timeout'),
        ),
        'timeout',
      );
      expect(
        const CodexTurnStartEncodingException('invalid').toString(),
        contains('invalid'),
      );
      expect(CodexProtocolTestHarness.helperCompatibilitySamples(), isNotEmpty);
      expect(
        CodexProtocolTestHarness.fileTrackerCompatibilitySamples(),
        hasLength(3),
      );

      final completionNotification = JsonRpcNotification(
        method: 'turn/completed',
        params: <String, Object?>{
          'threadId': 'thread',
          'turn': <String, Object?>{'status': 'completed'},
        },
        raw: <String, Object?>{},
      );
      expect(
        CodexProtocolTestHarness.mapNotification(
          completionNotification,
        ).ignoredReason,
        isNotNull,
      );
      final completed = CodexProtocolTestHarness.mapNotification(
        completionNotification,
        runningTurnIdForSession: (_) => 'active-turn',
      );
      expect(completed.completedSessionId, 'thread');
    });
  });
}
