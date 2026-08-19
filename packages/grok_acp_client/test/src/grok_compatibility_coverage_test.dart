// Compatibility matrices intentionally mirror sequential reducer operations.
// ignore_for_file: cascade_invocations

import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/src/acp/acp_content_codec.dart';
import 'package:grok_acp_client/src/acp/acp_permission_mapper.dart';
import 'package:grok_acp_client/src/acp/acp_session_config_mapper.dart';
import 'package:grok_acp_client/src/acp/acp_session_update_decoder.dart';
import 'package:grok_acp_client/src/datasources/acp/grok_models_cli.dart';
import 'package:grok_acp_client/src/datasources/acp/grok_permission_policy_adapter.dart';
import 'package:grok_acp_client/src/datasources/acp/grok_process_starter.dart';
import 'package:grok_acp_client/src/grok_cli_locator.dart';
import 'package:grok_acp_client/src/grok_text_catalog.dart';
import 'package:grok_acp_client/src/grok_usage_window_labels.dart';
import 'package:grok_acp_client/src/history/grok_chat_history_parser.dart';
import 'package:grok_acp_client/src/history/grok_session_history_reader.dart';
import 'package:grok_acp_client/src/history/grok_updates_history_parser.dart';
import 'package:grok_acp_client/src/mappers/grok_acp_notification_mapper.dart';
import 'package:grok_acp_client/src/mappers/grok_billing_quota_mapper.dart';
import 'package:grok_acp_client/src/mappers/grok_error_normalizer.dart';
import 'package:grok_acp_client/src/mappers/grok_file_change_tracker.dart';
import 'package:grok_acp_client/src/mappers/grok_permission_mode_codec.dart';
import 'package:grok_acp_client/src/mappers/grok_question_mapper.dart';
import 'package:grok_acp_client/src/mappers/grok_stream_identity.dart';
import 'package:test/test.dart';

void main() {
  group('Grok process compatibility branches', () {
    test('resolves protocol arguments and delegates host values', () async {
      const cli = '/tools/grok';
      final locator = GrokCliLocator(
        environment: const <String, String>{},
        isWindows: false,
        fileExists: (path) async => path == cli,
      );
      final config = AgentProviderConfig.defaultGrok.copyWith(
        command: cli,
        arguments: const <String>['agent', '--configured', 'stdio'],
        selectedModel: ' configured-model ',
        selectedReasoningEffort: ' high ',
      );

      final resolved = await resolveGrokProcessCommand(
        config,
        locator: locator,
      );
      expect(resolved.executable, cli);
      expect(
        resolved.arguments,
        const <String>[
          'agent',
          '--configured',
          '-m',
          'configured-model',
          '--effort',
          'high',
          'stdio',
        ],
      );

      final starter = grokProcessStarter(
        config.copyWith(arguments: const <String>[]),
        locator: locator,
        modelIdResolver: () => ' runtime-model ',
        reasoningEffortResolver: () => ' low ',
        delegate:
            (
              executable,
              arguments, {
              workingDirectory,
              environment,
            }) async {
              expect(executable, cli);
              expect(
                arguments,
                const <String>[
                  'agent',
                  '-m',
                  'runtime-model',
                  '--effort',
                  'low',
                  'stdio',
                ],
              );
              expect(workingDirectory, '/workspace');
              expect(environment, containsPair('SAFE', 'true'));
              throw const ProcessException(cli, <String>[]);
            },
      );

      await expectLater(
        starter(
          'ignored',
          const <String>[],
          workingDirectory: '/workspace',
          environment: const <String, String>{'SAFE': 'true'},
        ),
        throwsA(isA<ProcessException>()),
      );
    });

    test('preserves custom args and rejects a missing executable', () async {
      final locator = GrokCliLocator(
        environment: const <String, String>{},
        isWindows: false,
        fileExists: (_) async => false,
      );
      final missing = AgentProviderConfig.defaultGrok.copyWith(
        command: '/missing/grok',
        arguments: const <String>['custom', '--flag'],
      );

      await expectLater(
        resolveGrokProcessCommand(missing, locator: locator),
        throwsA(isA<ProcessException>()),
      );

      final existing = GrokCliLocator(
        environment: const <String, String>{},
        isWindows: false,
        fileExists: (path) async => path == '/tools/grok',
      );
      final custom = await resolveGrokProcessCommand(
        missing.copyWith(command: '/tools/grok'),
        locator: existing,
        modelId: 'ignored',
        reasoningEffort: 'ignored',
      );
      expect(custom.arguments, const <String>['custom', '--flag']);
    });

    test('default process delegate launches a disposable fake CLI', () async {
      final fake = await _createFakeGrokCli('process-started');
      addTearDown(() => fake.parent.delete(recursive: true));
      final locator = GrokCliLocator(
        environment: const <String, String>{'SystemRoot': r'C:\Windows'},
        isWindows: Platform.isWindows,
        fileExists: (path) async => path == fake.path,
      );
      final config = AgentProviderConfig.defaultGrok.copyWith(
        command: fake.path,
        arguments: const <String>[],
      );

      final process = await grokProcessStarter(config, locator: locator)(
        'ignored',
        const <String>[],
      );

      expect(await process.exitCode, 0);
    });

    test('default locator merges provider environment before lookup', () async {
      final fake = await _createFakeGrokCli('resolved');
      addTearDown(() => fake.parent.delete(recursive: true));
      final config = AgentProviderConfig.defaultGrok.copyWith(
        environment: <String, String>{'PATH': fake.parent.path},
        arguments: const <String>[],
      );

      final resolved = await resolveGrokProcessCommand(config);

      expect(resolved.displayPath, fake.path);
    });
  });

  group('ACP content compatibility branches', () {
    test('decodes scalar, nested, diff, malformed, and fallback content', () {
      expect(AcpContentCodec.textFromContent('plain'), 'plain');
      expect(
        AcpContentCodec.textFromContent(<Object?, Object?>{'text': 42}),
        '42',
      );
      expect(
        AcpContentCodec.textFromContent(<String, Object?>{
          'type': 'image',
          'text': 'hidden',
        }),
        isNull,
      );
      expect(AcpContentCodec.textFromContent(7), isNull);
      expect(AcpContentCodec.toolContentText(null), isNull);
      expect(AcpContentCodec.toolContentText('text'), 'text');
      expect(
        AcpContentCodec.toolContentText(<Object?>[
          'skip',
          <String, Object?>{
            'type': 'content',
            'content': <String, Object?>{'type': 'text', 'text': 'one'},
          },
          <String, Object?>{
            'type': 'content',
            'content': <String, Object?>{'type': 'image'},
          },
          <String, Object?>{
            'type': 'content',
            'content': <String, Object?>{'type': 'text', 'text': 'two'},
          },
          <String, Object?>{'type': 'diff'},
          <String, Object?>{'type': 'diff', 'path': 'two.dart'},
          <String, Object?>{'type': 'unknown'},
        ]),
        'one\ntwo\ndiff: file\ndiff: two.dart',
      );
      expect(AcpContentCodec.toolContentText(<Object?>[]), isNull);
      expect(AcpContentCodec.toolContentText(7), '7');
    });

    test('encodes every neutral input and fail-closes unsupported input', () {
      const context = AgentContext(
        projectPath: '/workspace',
        filePath: '/workspace/lib/main.dart',
      );
      expect(
        AcpContentCodec.buildPromptBlocks(
          context: context,
          message: ' message ',
        ),
        <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': 'message'},
          <String, Object?>{
            'type': 'resource_link',
            'uri': 'file:////workspace/lib/main.dart',
            'name': 'main.dart',
          },
        ],
      );
      expect(
        AcpContentCodec.buildPromptBlocks(
          context: const AgentContext(projectPath: '/workspace'),
          inputs: <AgentUserInput>[
            AgentTextUserInput('text'),
            const AgentMentionUserInput(
              name: 'source',
              path: 'file:///source.dart',
            ),
            const AgentLocalImageUserInput(path: '/image.png'),
          ],
          encodeLocalImagesAsPathText: true,
        ),
        hasLength(3),
      );
      expect(
        () => AcpContentCodec.buildPromptBlocks(
          context: const AgentContext(projectPath: '/workspace'),
        ),
        throwsArgumentError,
      );
      expect(
        () => AcpContentCodec.buildPromptBlocks(
          context: const AgentContext(projectPath: '/workspace'),
          inputs: const <AgentUserInput>[
            AgentLocalImageUserInput(path: '/image.png'),
          ],
        ),
        throwsUnsupportedError,
      );
      expect(
        () => AcpContentCodec.buildPromptBlocks(
          context: const AgentContext(projectPath: '/workspace'),
          inputs: const <AgentUserInput>[
            AgentSkillUserInput(name: 'skill', path: '/skill/SKILL.md'),
          ],
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('Grok model CLI compatibility branches', () {
    test('handles missing CLI, failures, exceptions, and success', () async {
      final missing = GrokModelsCli(
        locator: GrokCliLocator(
          environment: const <String, String>{},
          isWindows: false,
          fileExists: (_) async => false,
        ),
      );
      expect(
        (await missing.listModels(AgentProviderConfig.defaultGrok)).models,
        isEmpty,
      );

      Future<AgentModelList> runWith(
        Future<ProcessResult> Function(
          String,
          List<String>, {
          Map<String, String>? environment,
        })
        runner,
      ) {
        const cli = '/tools/grok';
        return GrokModelsCli(
          locator: GrokCliLocator(
            environment: const <String, String>{},
            isWindows: false,
            fileExists: (path) async => path == cli,
          ),
          processRunner: runner,
        ).listModels(
          AgentProviderConfig.defaultGrok.copyWith(command: cli),
        );
      }

      expect(
        (await runWith(
          (_, _, {environment}) async => ProcessResult(1, 2, '', 'bad'),
        )).models,
        isEmpty,
      );
      expect(
        (await runWith(
          (_, _, {environment}) async => throw StateError('fixture'),
        )).models,
        isEmpty,
      );
      final success = await runWith(
        (executable, arguments, {environment}) async {
          expect(arguments, const <String>['models']);
          expect(environment, isNotNull);
          return ProcessResult(1, 0, '* grok-test (default)', '');
        },
      );
      expect(success.models.single.id, 'grok-test');
    });

    test('default runner executes a disposable fake CLI', () async {
      final fake = await _createFakeGrokCli('Default model: grok-script');
      addTearDown(() => fake.parent.delete(recursive: true));
      final models =
          await GrokModelsCli(
            locator: GrokCliLocator(
              environment: const <String, String>{'SystemRoot': r'C:\Windows'},
              isWindows: Platform.isWindows,
              fileExists: (path) async => path == fake.path,
            ),
          ).listModels(
            AgentProviderConfig.defaultGrok.copyWith(command: fake.path),
          );

      expect(models.models.single.id, 'grok-script');
    });

    test('parsers keep malformed and fallback branches explicit', () {
      expect(
        GrokModelsCli.parseModelsOutput(
          '\nheading\nDefault model: only-default\nignored line\n',
        ).models.single.id,
        'only-default',
      );
      expect(parseAcpModelsPayload(null), isNull);
      expect(parseAcpModelsPayload(<String, Object?>{}), isNull);
      expect(
        parseAcpModelsPayload(<String, Object?>{
          'availableModels': <Object?>[
            'skip',
            <String, Object?>{},
            <String, Object?>{
              'id': 'reasoning',
              'contextWindow': -1,
              '_meta': <String, Object?>{
                'supportsReasoningEffort': true,
                'reasoningEffort': 'medium',
                'contextWindowTokens': 8192,
              },
            },
            <String, Object?>{
              'modelId': 'list',
              '_meta': <String, Object?>{
                'reasoningEfforts': <Object?>[
                  'skip',
                  <String, Object?>{},
                  <String, Object?>{'id': 'high'},
                ],
              },
            },
          ],
        })?.models,
        hasLength(2),
      );
      expect(
        parseAcpModelsPayload(<String, Object?>{
          'availableModels': <Object?>['invalid'],
        }),
        isNull,
      );
    });
  });

  test('usage labels and provider text expose all stable branches', () {
    const text = GrokTextCatalog();
    for (final kind in AgentToolKind.values) {
      expect(text.toolKindLabel(kind), isNotEmpty);
    }
    expect(text.providerReady('Grok'), 'Grok ready');
    expect(text.agentIsWorking, isNotEmpty);
    expect(text.startingProvider('Grok'), contains('Grok'));
    expect(text.couldNotStart('Grok'), contains('Grok'));
    expect(text.protocolWarning('Grok'), contains('Grok'));
    expect(text.requestTimedOut('Grok'), contains('Grok'));
    expect(text.connectionClosedRetry('Grok'), contains('Grok'));
    expect(text.waitingApprovalFor('Edit'), contains('Edit'));
    expect(text.waitingAnswersFor('Question'), contains('Question'));
    expect(text.waitingPlanApproval, isNotEmpty);
    expect(text.planApprovalTitle, isNotEmpty);
    expect(text.planQuotaLabel, isNotEmpty);
    expect(text.onDemandQuotaLabel, isNotEmpty);

    expect(formatGrokUsageWindowLabelFromMinutes(null), isNull);
    expect(formatGrokUsageWindowLabelFromMinutes(0), isNull);
    expect(formatGrokUsageWindowLabelFromMinutes(7 * 24 * 60), '1 week');
    expect(formatGrokUsageWindowLabelFromMinutes(2 * 7 * 24 * 60), '2 weeks');
    expect(formatGrokUsageWindowLabelFromMinutes(24 * 60), '1 day');
    expect(formatGrokUsageWindowLabelFromMinutes(2 * 24 * 60), '2 days');
    expect(formatGrokUsageWindowLabelFromMinutes(60), '1 hour');
    expect(formatGrokUsageWindowLabelFromMinutes(120), '2 hours');
    expect(formatGrokUsageWindowLabelFromMinutes(90), '1 h 30 min');
    expect(formatGrokUsageWindowLabelFromMinutes(15), '15 min');
    expect(
      formatGrokUsageWindowLabelFromPeriodType('USAGE_PERIOD_TYPE_WEEKLY'),
      '1 week',
    );
    expect(
      formatGrokUsageWindowLabelFromPeriodType('USAGE_PERIOD_TYPE_DAILY'),
      '1 day',
    );
    expect(formatGrokUsageWindowLabelFromPeriodType('unknown'), isNull);
  });

  test('permission mapper chooses every allow and reject fallback', () {
    AcpPermissionMapping mapping(List<Map<String, Object?>> options) {
      return AcpPermissionMapper.mapRequest(
        requestId: 7,
        params: <String, Object?>{
          'sessionId': 'session',
          'toolCall': <String, Object?>{'title': 'Edit', 'kind': 'edit'},
          'options': <Object?>[
            'skip',
            <String, Object?>{},
            ...options,
          ],
        },
        runningTurnId: 'turn',
      );
    }

    expect(
      mapping(<Map<String, Object?>>[
        <String, Object?>{
          'optionId': 'once',
          'name': 'Once',
          'kind': 'allow_once',
        },
      ]).preferredOptionId(approved: true),
      'once',
    );
    expect(
      mapping(<Map<String, Object?>>[
        <String, Object?>{'optionId': 'always', 'kind': 'allow_always'},
      ]).preferredOptionId(approved: true),
      'always',
    );
    expect(
      mapping(<Map<String, Object?>>[
        <String, Object?>{'optionId': 'fallback'},
      ]).preferredOptionId(approved: true),
      'fallback',
    );
    expect(
      mapping(<Map<String, Object?>>[
        <String, Object?>{'optionId': 'reject', 'kind': 'reject_once'},
      ]).preferredOptionId(approved: false),
      'reject',
    );
    expect(
      mapping(<Map<String, Object?>>[
        <String, Object?>{'optionId': 'fallback'},
      ]).preferredOptionId(approved: false),
      'fallback',
    );
    final empty = AcpPermissionMapper.mapRequest(
      requestId: 'empty',
      params: const <String, Object?>{},
      runningTurnId: null,
    );
    expect(empty.preferredOptionId(approved: true), isNull);
    expect(empty.preferredOptionId(approved: false), isNull);
    expect(empty.request.title, 'Approve tool execution');
  });

  test('remaining decoder and session config fallbacks stay typed', () {
    const decoder = AcpSessionUpdateDecoder();
    AcpSessionUpdate decode(String kind, Map<String, Object?> update) {
      return decoder.decode(<String, Object?>{
        'sessionId': 'session',
        'update': <String, Object?>{'sessionUpdate': kind, ...update},
      });
    }

    expect(
      decode('user_message_chunk', const <String, Object?>{}),
      isA<AcpUnknownUpdate>(),
    );
    expect(
      decode('agent_thought_chunk', const <String, Object?>{}),
      isA<AcpUnknownUpdate>(),
    );
    expect(
      decode('tool_call', const <String, Object?>{}),
      isA<AcpUnknownUpdate>(),
    );
    expect(
      decode('usage_update', const <String, Object?>{}),
      isA<AcpUnknownUpdate>(),
    );
    expect(
      decode('session_summary_generated', const <String, Object?>{
        'sessionSummary': 'summary',
      }),
      isA<AcpSessionSummaryGenerated>(),
    );

    const mapper = AcpSessionConfigMapper();
    final untouched = <AgentSessionConfigOption>[
      AgentSessionConfigOption(
        id: 'model',
        name: 'Model',
        kind: AgentSessionConfigOptionKind.select,
        category: 'model',
        currentValue: 'one',
      ),
    ];
    expect(mapper.applyCurrentMode(untouched, 'plan'), same(untouched));
  });

  test(
    'permission live notification failure is fail-closed and typed',
    () async {
      var mode = GrokPermissionMode.ask;
      final adapter = GrokPermissionPolicyAdapter(
        isInitialized: () => true,
        isDisposed: () => false,
        currentMode: () => mode,
        onModeApplied: (next) => mode = next,
        notifyLive: (_, _) => throw StateError('fixture'),
      );

      final result = await adapter.applyPermissionSelection(
        const AgentPermissionSelection(optionId: 'auto'),
      );

      expect(result.scope, AgentPermissionApplyScope.runtime);
      expect(
        result.warningCode,
        AgentPermissionWarningCode.downgradedByRuntime,
      );
    },
  );

  test('small mapper fallbacks preserve safe neutral values', () {
    expect(
      grokTransportRetryingMessage(attempt: 2),
      contains('retry 2'),
    );
    final billing = mapGrokBillingQuota(
      <String, Object?>{
        'config': <String, Object?>{
          'currentPeriod': <String, Object?>{
            'type': 'USAGE_PERIOD_TYPE_MONTHLY',
          },
          'creditUsagePercent': '27.6',
          'onDemandCap': 10,
          'onDemandUsed': <String, Object?>{'val': '2.5'},
          'prepaidBalance': <String, Object?>{'val': '3.25'},
        },
      },
      providerId: 'grok',
      providerName: 'Grok',
    );
    expect(billing?.windows.first.label, 'Plan quota');
    expect(billing?.windows.first.usedPercent, 28);
    expect(billing?.credits?.balance, '3.25');
    expect(billing?.windows.last.usedPercent, 25);

    final scalarBilling = mapGrokBillingQuota(
      <String, Object?>{
        'config': <String, Object?>{
          'prepaidBalance': 2,
          'onDemandCap': <String, Object?>{'val': 5},
        },
      },
      providerId: 'grok',
      providerName: 'Grok',
    );
    expect(scalarBilling?.credits?.balance, '2');
  });

  test('question and file mappers tolerate scalar legacy values', () {
    final mapped = const GrokQuestionMapper().mapRequest(
      requestId: 9,
      params: <String, Object?>{
        'questions': <Object?>[
          <String, Object?>{
            'header': 'Header fallback',
            'id': 'question-id',
            'multi_select': true,
            'options': <Object?>[
              null,
              '',
              'Plain',
              <String, Object?>{},
              <String, Object?>{'label': 'Mapped', 'value': 'mapped'},
            ],
          },
        ],
      },
    );
    expect(mapped.pending.id, '9');
    expect(mapped.pending.questions.single.questionId, 'question-id');
    expect(mapped.pending.questions.single.allowMultiple, isTrue);
    expect(
      mapped.pending.copyWith().runtimeScope,
      isNull,
    );

    final projection = GrokToolContentProjection.parse(42);
    expect(projection.content, '42');
    final tracker = GrokFileChangeTracker();
    final malformed = tracker.project(
      update: const AcpToolCallUpdate(
        sessionId: 'session',
        kind: 'tool_call_update',
        toolCallId: 'tool',
        toolKind: 'edit',
        content: <String, Object?>{'type': 'diff', 'path': ''},
        rawInput: <String, Object?>{'replace_all': true},
      ),
      toolKind: AgentToolKind.edit,
      runtimeScope: const AgentRuntimeScope(
        runtimeId: 'grok',
        connectionEpoch: 1,
      ),
      sessionId: 'session',
      turnId: 'turn',
    );
    expect(malformed.fileChanges, isNull);

    final idFallback = const GrokQuestionMapper().mapRequest(
      requestId: 'request',
      params: <String, Object?>{
        'questions': <Object?>[
          <String, Object?>{'id': 'id-only'},
        ],
      },
    );
    expect(idFallback.pending.questions.single.question, 'id-only');
  });

  test('chat history parser covers legacy scalar and unknown records', () {
    final content = <Object?>[
      <String, Object?>{
        'type': 'user',
        'content': '<user_query>Question</user_query>',
      },
      <String, Object?>{
        'type': 'tool_result',
        'tool_name': 'First tool',
        'content': <Object?>[
          'scalar ',
          <String, Object?>{'type': 'text', 'text': 'result'},
        ],
      },
      <String, Object?>{
        'type': 'tool',
        'content': <String, Object?>{'text': 'mapped result'},
      },
      <String, Object?>{
        'type': 'function_call_output',
        'name': 'Function',
        'content': 'function result',
      },
      <String, Object?>{'type': 'other', 'content': 'narration'},
      <String, Object?>{'type': 'other', 'content': '<system-reminder>x'},
      <String, Object?>{'type': 'user', 'content': 'You are Grok fixture'},
      <String, Object?>{
        'type': 'assistant',
        'content': <String, Object?>{'content': 'fallback content'},
      },
    ].map(jsonEncode).join('\n');

    final snapshot = const GrokChatHistoryParser().parse(
      threadId: 'chat-compat',
      content: content,
    );

    expect(snapshot.turns.single.entries, hasLength(6));
  });

  test('updates history parser covers merge and legacy terminal branches', () {
    Map<String, Object?> line(
      String kind,
      Map<String, Object?> update, {
      String sessionId = 'session',
      String method = 'session/update',
      Map<String, Object?> meta = const <String, Object?>{},
      Object? timestamp,
    }) {
      return <String, Object?>{
        'timestamp': timestamp,
        'method': method,
        'params': <String, Object?>{
          'sessionId': sessionId,
          'update': <String, Object?>{'sessionUpdate': kind, ...update},
          '_meta': meta,
        },
      };
    }

    final records = <Map<String, Object?>>[
      line(
        'user_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'first'},
          'messageId': 'user-1',
          '_meta': <String, Object?>{'promptIndex': 1},
        },
        timestamp: 2.5,
      ),
      line(
        'user_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'first expanded'},
          'messageId': 'user-1',
          '_meta': <String, Object?>{'promptIndex': 1},
        },
      ),
      line(
        'agent_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'hello'},
          'messageId': 'agent-1',
          'modelId': 'grok-compat',
          '_meta': <String, Object?>{
            'promptId': 'prompt-1',
            'turnStartMs': 1,
          },
        },
      ),
      line(
        'agent_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': ' world'},
          'messageId': 'agent-1',
          '_meta': <String, Object?>{'promptId': 'prompt-1'},
        },
      ),
      line(
        'plan',
        <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{'content': 'First'},
          ],
          '_meta': <String, Object?>{'promptId': 'prompt-1'},
        },
      ),
      line(
        'plan',
        <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{'content': 'Replacement', 'status': 'pending'},
          ],
          '_meta': <String, Object?>{'promptId': 'prompt-1'},
        },
      ),
      <String, Object?>{
        'method': '_x.ai/turn_completed',
        'params': <String, Object?>{
          'sessionId': 'session',
          'update': <String, Object?>{
            'prompt_id': 'prompt-1',
            'stop_reason': 'end_turn',
            'usage': <String, Object?>{
              'inputTokens': 2.2,
              'outputTokens': '3',
            },
          },
        },
      },
      line(
        'agent_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'next'},
          '_meta': <String, Object?>{'promptId': 'prompt-2'},
        },
        sessionId: 'other-session',
      ),
    ];

    final snapshot = const GrokUpdatesHistoryParser().parse(
      threadId: 'updates-compat',
      content: records.map(jsonEncode).join('\n'),
    );

    expect(snapshot.turns, hasLength(2));
    expect(snapshot.turns.first.modelId, 'grok-compat');
    expect(
      snapshot.turns.first.entries.whereType<AgentHistoryMessageEntry>().any(
        (entry) => entry.text.contains('hello world'),
      ),
      isTrue,
    );
    expect(
      snapshot.turns.first.entries
          .whereType<AgentHistoryMessageEntry>()
          .singleWhere((entry) => entry.kind == AgentMessageKind.plan)
          .text,
      contains('Replacement'),
    );

    final edgeRecords = <Map<String, Object?>>[
      line(
        'user_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'alpha'},
          'messageId': 'user-message',
          '_meta': <String, Object?>{'promptId': 'user-prompt'},
        },
        timestamp: '3',
      ),
      line(
        'agent_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'first'},
          '_meta': <String, Object?>{'promptId': 'user-prompt'},
        },
      ),
      line(
        'user_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'beta'},
          'messageId': 'user-message',
          '_meta': <String, Object?>{'promptId': 'user-prompt'},
        },
      ),
      line(
        'agent_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'second'},
          '_meta': <String, Object?>{'promptId': 'user-prompt'},
        },
      ),
      line(
        'agent_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'new turn'},
          '_meta': <String, Object?>{'promptId': 'different-prompt'},
        },
      ),
      line(
        'user_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': 'message-key'},
          'messageId': 'standalone-message',
        },
      ),
    ];
    final edgeSnapshot = const GrokUpdatesHistoryParser().parse(
      threadId: 'updates-edge',
      content: edgeRecords.map(jsonEncode).join('\n'),
    );
    expect(edgeSnapshot.turns.length, greaterThanOrEqualTo(2));
  });

  test('notification facade forwards session invalidation', () {
    final mapper = GrokAcpNotificationMapper();
    const scope = AgentRuntimeScope(runtimeId: 'compat', connectionEpoch: 1);
    mapper
      ..beginTurn(runtimeScope: scope, sessionId: 'session', turnId: 'turn')
      ..invalidateSession(
        runtimeScope: scope,
        sessionId: 'session',
        reason: GrokIdentityInvalidationReason.sessionSwitched,
      )
      ..dispose();

    expect(
      mapper.snapshot(
        runtimeScope: scope,
        sessionId: 'session',
        turnId: 'turn',
      ),
      isNull,
    );
  });

  test(
    'session history reader covers filesystem and parser failures',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'grok-history-compat-',
      );
      addTearDown(() => root.delete(recursive: true));
      final reader = GrokSessionHistoryReader(grokHome: root.path);
      expect(
        reader.resolveGrokHome(
          environment: const <String, String>{'GROK_HOME': '/env/grok'},
        ),
        '/env/grok',
      );
      expect(
        (await reader.listThreads(
          query: AgentThreadListQuery(projectPath: null, limit: 20),
          providerId: 'grok',
        )).threads,
        isEmpty,
      );
      expect(
        (await reader.listThreads(
          query: AgentThreadListQuery(projectPath: '/missing', limit: 20),
          providerId: 'grok',
        )).threads,
        isEmpty,
      );

      final sessions = Directory(
        '${root.path}${Platform.pathSeparator}sessions',
      );
      await sessions.create(recursive: true);
      await File('${sessions.path}${Platform.pathSeparator}not-a-directory')
          .writeAsString('x');
      const projectPath = '/Work/Project';
      final encoded = Uri.encodeComponent('$projectPath/');
      final project = Directory(
        '${sessions.path}${Platform.pathSeparator}$encoded',
      );
      await project.create();
      await File('${project.path}${Platform.pathSeparator}not-a-session')
          .writeAsString('x');
      const firstId = '11111111-1111-1111-1111-111111111111';
      const secondId = '22222222-2222-2222-2222-222222222222';
      final first = Directory(
        '${project.path}${Platform.pathSeparator}$firstId',
      );
      final second = Directory(
        '${project.path}${Platform.pathSeparator}$secondId',
      );
      await first.create();
      await second.create();
      await File('${first.path}${Platform.pathSeparator}summary.json')
          .writeAsString('{bad');
      await File('${second.path}${Platform.pathSeparator}summary.json')
          .writeAsString(
            jsonEncode(<String, Object?>{
              'session_summary': 'Preview',
              'updated_at': '2026-08-20T10:00:00Z',
              'info': <String, Object?>{'cwd': projectPath.toLowerCase()},
            }),
          );

      final page = await reader.listThreads(
        query: AgentThreadListQuery(
          projectPath: projectPath,
          limit: 1,
          cursor: 'invalid',
        ),
        providerId: 'grok',
      );
      expect(page.threads, hasLength(1));
      expect(page.nextCursor, '1');

      final malformedProject = Directory(
        '${sessions.path}${Platform.pathSeparator}%ZZ',
      );
      await malformedProject.create();
      final malformedSession = Directory(
        '${malformedProject.path}${Platform.pathSeparator}'
        '33333333-3333-3333-3333-333333333333',
      );
      await malformedSession.create();
      expect(
        (await reader.listThreads(
          query: AgentThreadListQuery(projectPath: '%ZZ', limit: 20),
          providerId: 'grok',
        )).threads,
        hasLength(1),
      );

      final empty = await reader.readThreadHistory(
        threadId: firstId,
        providerId: 'grok',
        sessionPath: '${first.path}${Platform.pathSeparator}missing-file',
        projectPath: projectPath,
      );
      expect(empty.turns, isEmpty);

      final summaryFile = File(
        '${first.path}${Platform.pathSeparator}summary.json',
      );
      await summaryFile.writeAsString('[]');
      expect(
        (await reader.readSessionTitleSnapshot(
          threadId: firstId,
          sessionPath: first.path,
        ))?.generatedTitle,
        isNull,
      );
      await summaryFile.writeAsString('{bad');
      expect(
        await reader.readSessionDisplayTitle(
          threadId: firstId,
          sessionPath: first.path,
        ),
        isNull,
      );

      await File('${first.path}${Platform.pathSeparator}updates.jsonl')
          .writeAsString('fixture');
      final throwingUpdates = GrokSessionHistoryReader(
        grokHome: root.path,
        updatesParser: const _ThrowingUpdatesParser(),
      );
      expect(
        (await throwingUpdates.readThreadHistory(
          threadId: firstId,
          providerId: 'grok',
          sessionPath: first.path,
        )).turns,
        isEmpty,
      );
      await File('${first.path}${Platform.pathSeparator}updates.jsonl')
          .delete();
      await File('${first.path}${Platform.pathSeparator}chat_history.jsonl')
          .writeAsString('fixture');
      final throwingChat = GrokSessionHistoryReader(
        grokHome: root.path,
        chatHistoryParser: const _ThrowingChatParser(),
      );
      expect(
        (await throwingChat.readThreadHistory(
          threadId: firstId,
          providerId: 'grok',
          sessionPath: first.path,
        )).turns,
        isEmpty,
      );
    },
  );

  test('identity reducer covers late, duplicate, collision, and disposal', () {
    const scope = AgentRuntimeScope(runtimeId: 'identity', connectionEpoch: 1);
    final identity = GrokStreamIdentity();
    identity.beginTurn(
      runtimeScope: scope,
      sessionId: 'session',
      turnId: 'turn-1',
    );
    identity.resolveMessage(
      runtimeScope: scope,
      sessionId: 'session',
      runningTurnId: 'turn-1',
      promptId: 'prompt-1',
      sourceMessageId: 'source',
      eventId: 'message',
      eventKind: 'agent_message_chunk',
    );
    final accepted = identity.completeTurn(
      runtimeScope: scope,
      sessionId: 'session',
      runningTurnId: 'turn-1',
      promptId: 'prompt-1',
      status: AgentHistoryTurnStatus.completed,
      source: GrokTerminalSource.standardNotification,
      eventId: 'done',
    );
    final duplicate = identity.completeTurn(
      runtimeScope: scope,
      sessionId: 'session',
      runningTurnId: 'turn-1',
      promptId: 'prompt-1',
      status: AgentHistoryTurnStatus.completed,
      source: GrokTerminalSource.standardNotification,
      eventId: 'done',
    );
    expect(accepted.disposition, GrokTerminalDisposition.accepted);
    expect(duplicate.disposition, GrokTerminalDisposition.duplicate);
    expect(
      identity.resolveReasoning(
        runtimeScope: scope,
        sessionId: 'session',
        runningTurnId: 'turn-1',
        promptId: 'prompt-1',
        sourceItemId: null,
        eventId: 'late-reasoning',
        eventKind: 'agent_thought_chunk',
      ),
      isNull,
    );
    expect(
      identity.resolveVisibleBoundaryUpdate(
        runtimeScope: scope,
        sessionId: 'session',
        runningTurnId: 'turn-1',
        promptId: 'prompt-1',
        eventId: 'late-interaction',
        eventKind: 'permission',
      ),
      isNull,
    );
    expect(
      identity.noteBoundary(
        runtimeScope: scope,
        sessionId: 'session',
        runningTurnId: 'turn-1',
        promptId: 'prompt-1',
        kind: GrokNarrativeBoundaryKind.permission,
      ),
      isFalse,
    );
    expect(
      identity
          .completeTurn(
            runtimeScope: scope,
            sessionId: 'missing',
            runningTurnId: 'missing',
            promptId: null,
            status: AgentHistoryTurnStatus.failed,
            source: GrokTerminalSource.promptError,
          )
          .disposition,
      GrokTerminalDisposition.missingScope,
    );

    identity.beginTurn(
      runtimeScope: scope,
      sessionId: 'collision',
      turnId: 'old-turn',
    );
    identity.resolveMetadata(
      runtimeScope: scope,
      sessionId: 'collision',
      runningTurnId: 'old-turn',
      promptId: 'old-prompt',
      eventId: null,
      eventKind: 'usage_update',
    );
    identity.beginTurn(
      runtimeScope: scope,
      sessionId: 'collision',
      turnId: 'new-turn',
    );
    identity.resolveMetadata(
      runtimeScope: scope,
      sessionId: 'collision',
      runningTurnId: 'new-turn',
      promptId: 'new-prompt',
      eventId: null,
      eventKind: 'usage_update',
    );
    expect(
      identity.resolveMessage(
        runtimeScope: scope,
        sessionId: 'collision',
        runningTurnId: 'old-turn',
        promptId: 'new-prompt',
        sourceMessageId: null,
        eventId: null,
        eventKind: 'agent_message_chunk',
      ),
      isNull,
    );
    identity.invalidateSession(
      runtimeScope: scope,
      sessionId: 'collision',
      reason: GrokIdentityInvalidationReason.sessionSwitched,
    );
    identity.dispose();
    expect(
      () => identity.beginTurn(
        runtimeScope: scope,
        sessionId: 'session',
        turnId: 'disposed',
      ),
      throwsStateError,
    );
  });

  test('session mapper covers empty, usage, context, and status aliases', () {
    const scope = AgentRuntimeScope(runtimeId: 'mapper', connectionEpoch: 1);
    final mapper = GrokSessionUpdateMapper();
    addTearDown(mapper.dispose);
    mapper.beginTurn(
      runtimeScope: scope,
      sessionId: 'session',
      turnId: 'turn',
    );
    GrokAcpMappedUpdate map(
      String kind,
      Map<String, Object?> update, {
      String? eventId,
    }) {
      return mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': 'session',
          'update': <String, Object?>{'sessionUpdate': kind, ...update},
          '_meta': <String, Object?>{'eventId': eventId},
        },
        runningTurnId: 'turn',
        runtimeScope: scope,
      );
    }

    expect(
      map(
        'agent_message_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': ''},
        },
      ).events,
      isEmpty,
    );
    expect(
      map(
        'agent_thought_chunk',
        <String, Object?>{
          'content': <String, Object?>{'text': ''},
        },
      ).events,
      isEmpty,
    );
    expect(
      map('usage_update', <String, Object?>{'used': 0}, eventId: 'usage-0')
          .events
          .whereType<AgentTokenUsageEvent>()
          .single
          .tokenUsage
          .lastTotalTokens,
      isNull,
    );
    expect(
      map('usage_update', <String, Object?>{
        'used': 5,
      }, eventId: 'usage-5').events,
      isNotEmpty,
    );
    for (final (index, status) in <String>[
      'complete',
      'success',
      'succeeded',
      'cancelled',
      'canceled',
    ].indexed) {
      expect(
        map(
          'tool_call',
          <String, Object?>{
            'toolCallId': 'tool-$index',
            'status': status,
          },
          eventId: 'tool-event-$index',
        ).events,
        isNotEmpty,
      );
    }
    final terminal = mapper.mapSessionUpdate(
      params: <String, Object?>{
        'sessionId': 'session',
        'update': <String, Object?>{
          'sessionUpdate': 'turn_completed',
          'stop_reason': 'end_turn',
        },
        '_meta': <String, Object?>{
          'eventId': 'terminal',
          'totalTokens': 9,
        },
      },
      runningTurnId: 'turn',
      runtimeScope: scope,
    );
    expect(
      terminal.events.whereType<AgentTokenUsageEvent>().single.tokenUsage,
      isNotNull,
    );

    mapper.invalidateTurn(
      runtimeScope: scope,
      sessionId: 'session',
      runningTurnId: null,
      promptId: null,
      reason: GrokIdentityInvalidationReason.cancel,
    );
  });
}

Future<File> _createFakeGrokCli(String output) async {
  final temp = await Directory.systemTemp.createTemp('grok-fixture-');
  if (Platform.isWindows) {
    final script = File('${temp.path}${Platform.pathSeparator}grok.cmd');
    await script.writeAsString('@echo off\r\necho $output\r\n');
    return script;
  }
  final script = File('${temp.path}${Platform.pathSeparator}grok');
  await script.writeAsString('#!/bin/sh\nprintf "%s\\n" "$output"\n');
  final chmod = await Process.run('chmod', <String>['+x', script.path]);
  if (chmod.exitCode != 0) {
    throw StateError('Could not prepare the fake Grok CLI');
  }
  return script;
}

final class _ThrowingUpdatesParser extends GrokUpdatesHistoryParser {
  const _ThrowingUpdatesParser();

  @override
  AgentThreadHistorySnapshot parse({
    required String threadId,
    required String content,
    Map<String, Object?> raw = const <String, Object?>{},
  }) => throw const FormatException('fixture');
}

final class _ThrowingChatParser extends GrokChatHistoryParser {
  const _ThrowingChatParser();

  @override
  AgentThreadHistorySnapshot parse({
    required String threadId,
    required String content,
    Map<String, Object?> raw = const <String, Object?>{},
  }) => throw const FormatException('fixture');
}
