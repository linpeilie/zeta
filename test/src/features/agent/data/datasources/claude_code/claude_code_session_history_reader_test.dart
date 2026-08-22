import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('ClaudeCodeSessionHistoryReader', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('zeta-claude-history-');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('freezes project path encoding including Windows drive letters', () {
      expect(
        ClaudeCodeSessionHistoryReader.encodeProjectPath(
          r'D:\Development\Workspace\zeta',
        ),
        'D--Development-Workspace-zeta',
      );
      expect(
        ClaudeCodeSessionHistoryReader.encodeProjectPath(r'C:\Users\linpl'),
        'C--Users-linpl',
      );
      expect(
        ClaudeCodeSessionHistoryReader.encodeProjectPath(
          '/Users/example/Workspace/zeta',
        ),
        '-Users-example-Workspace-zeta',
      );
    });

    test(
      'inherits process home when provider overrides omit the home variable',
      () {
        final homeKey = Platform.isWindows ? 'USERPROFILE' : 'HOME';
        final processHome = Platform.environment[homeKey];
        if (processHome == null || processHome.trim().isEmpty) {
          fail('The test process must expose $homeKey');
        }
        final expected =
            '${processHome.trim()}${Platform.pathSeparator}.claude';
        final reader = ClaudeCodeSessionHistoryReader();

        expect(
          reader.resolveClaudeHome(environment: const <String, String>{}),
          expected,
        );
        expect(
          reader.resolveClaudeHome(
            environment: const <String, String>{
              'CLAUDE_CODE_TEST_OVERRIDE': 'enabled',
            },
          ),
          expected,
        );
      },
    );

    test('restores cached history without a persisted session path', () async {
      const projectPath = r'D:\Development\Workspace\zeta';
      const sessionId = 'restored-session';
      final homeKey = Platform.isWindows ? 'USERPROFILE' : 'HOME';
      final userHome = await Directory(
        '${tempRoot.path}${Platform.pathSeparator}user-home',
      ).create(recursive: true);
      final claudeHome = await Directory(
        '${userHome.path}${Platform.pathSeparator}.claude',
      ).create(recursive: true);
      final projectDirectory = await _projectDirectory(
        claudeHome,
        projectPath,
      ).create(recursive: true);
      final sessionFile = File(
        '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
      );
      await sessionFile.writeAsString(
        '${jsonEncode(<String, Object?>{
          'type': 'user',
          'sessionId': sessionId,
          'uuid': 'restored-user',
          'timestamp': '2026-08-12T02:00:00.000Z',
          'cwd': projectPath,
          'message': <String, Object?>{'role': 'user', 'content': 'Restore this history'},
        })}\n'
        '${jsonEncode(<String, Object?>{
          'type': 'assistant',
          'sessionId': sessionId,
          'uuid': 'restored-assistant',
          'parentUuid': 'restored-user',
          'timestamp': '2026-08-12T02:00:01.000Z',
          'cwd': projectPath,
          'message': <String, Object?>{
            'role': 'assistant',
            'model': 'claude-test-model',
            'stop_reason': 'end_turn',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'History restored'},
            ],
          },
        })}\n',
      );
      final reader = ClaudeCodeSessionHistoryReader();

      final snapshot = await reader.readThreadHistory(
        threadId: sessionId,
        providerId: 'claude-code',
        projectPath: projectPath,
        sessionPath: null,
        environment: <String, String>{homeKey: userHome.path},
      );

      expect(snapshot.turns, hasLength(1));
      expect(
        snapshot.turns.single.entries.whereType<AgentHistoryMessageEntry>().map(
          (entry) => entry.text,
        ),
        <String>['Restore this history', 'History restored'],
      );
    });

    test(
      'restores stable turn effort and omits missing or conflicting evidence',
      () async {
        const projectPath = '/workspace/effort-history';
        const sessionId = 'effort-history-session';
        final projectDirectory = await _projectDirectory(
          tempRoot,
          projectPath,
        ).create(recursive: true);
        final sessionFile = File(
          '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
        );
        // Claude Code 2.1.227 / Windows 脱敏本地 JSONL 形状：effort 只出现在
        // assistant 顶层，user/result 不携带；正文与 source id 均为测试占位值。
        final frames = <Map<String, Object?>>[
          _historyUserFrame(
            sessionId: sessionId,
            id: 'user-stable',
            content: '[PROMPT_REDACTED_1]',
          ),
          _historyAssistantFrame(
            sessionId: sessionId,
            id: 'assistant-stable-1',
            effort: 'xhigh',
          ),
          _historyAssistantFrame(
            sessionId: sessionId,
            id: 'assistant-stable-2',
            effort: 'xhigh',
            endTurn: true,
          ),
          _historyUserFrame(
            sessionId: sessionId,
            id: 'user-missing',
            content: '[PROMPT_REDACTED_2]',
          ),
          _historyAssistantFrame(
            sessionId: sessionId,
            id: 'assistant-missing',
            endTurn: true,
          ),
          _historyUserFrame(
            sessionId: sessionId,
            id: 'user-conflict',
            content: '[PROMPT_REDACTED_3]',
          ),
          _historyAssistantFrame(
            sessionId: sessionId,
            id: 'assistant-conflict-1',
            effort: 'medium',
          ),
          _historyAssistantFrame(
            sessionId: sessionId,
            id: 'assistant-conflict-2',
            effort: 'high',
            endTurn: true,
          ),
        ];
        await sessionFile.writeAsString(
          '${frames.map(jsonEncode).join('\n')}\n',
        );
        final reader = ClaudeCodeSessionHistoryReader(
          claudeHome: tempRoot.path,
        );

        final snapshot = await reader.readThreadHistory(
          threadId: sessionId,
          providerId: 'claude-code',
          projectPath: projectPath,
        );

        expect(snapshot.turns, hasLength(3));
        expect(snapshot.turns[0].modelId, 'claude-test-model');
        expect(snapshot.turns[0].reasoningEffort.value, 'xhigh');
        expect(snapshot.turns[0].reasoningEffort.isKnown, isTrue);
        expect(snapshot.turns[0].serviceTierId, isNull);
        expect(snapshot.turns[0].explicitFast, isNull);
        expect(snapshot.turns[1].reasoningEffort.isKnown, isFalse);
        expect(snapshot.turns[2].reasoningEffort.isKnown, isFalse);
      },
    );

    test(
      'keeps split end_turn text and closes on the next user, not the thinking row',
      () async {
        const projectPath = '/workspace/split-end-turn';
        const sessionId = 'split-end-turn-session';
        final projectDirectory = await _projectDirectory(
          tempRoot,
          projectPath,
        ).create(recursive: true);
        final sessionFile = File(
          '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
        );
        const usage = <String, Object?>{
          'input_tokens': 10,
          'output_tokens': 20,
          'cache_read_input_tokens': 4,
        };
        final frames = <Map<String, Object?>>[
          _historyUserFrame(
            sessionId: sessionId,
            id: 'user-1',
            content: '[PROMPT_REDACTED_1]',
            timestamp: '2026-08-17T02:00:00.000Z',
          ),
          _historyAssistantContentFrame(
            sessionId: sessionId,
            uuid: 'assistant-tool',
            messageId: 'msg-tool',
            timestamp: '2026-08-17T02:00:01.000Z',
            stopReason: 'tool_use',
            content: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'tool_use',
                'id': 'tool-1',
                'name': 'Read',
                'input': <String, Object?>{'file_path': '[PATH_REDACTED]'},
              },
            ],
            usage: const <String, Object?>{
              'input_tokens': 3,
              'output_tokens': 2,
            },
          ),
          <String, Object?>{
            'type': 'user',
            'sessionId': sessionId,
            'uuid': 'tool-result-1',
            'timestamp': '2026-08-17T02:00:02.000Z',
            'message': <String, Object?>{
              'role': 'user',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'tool_result',
                  'tool_use_id': 'tool-1',
                  'content': '[TOOL_OUTPUT_REDACTED]',
                },
              ],
            },
          },
          _historyAssistantContentFrame(
            sessionId: sessionId,
            uuid: 'assistant-thinking',
            messageId: 'msg-final',
            timestamp: '2026-08-17T02:00:03.000Z',
            stopReason: 'end_turn',
            content: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'thinking',
                'thinking': '',
                'signature': '[SIGNATURE_REDACTED]',
              },
            ],
            usage: usage,
          ),
          _historyAssistantContentFrame(
            sessionId: sessionId,
            uuid: 'assistant-text',
            messageId: 'msg-final',
            timestamp: '2026-08-17T02:00:04.000Z',
            stopReason: 'end_turn',
            content: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': '[RESPONSE_REDACTED_FINAL]',
              },
            ],
            usage: usage,
          ),
          _historyUserFrame(
            sessionId: sessionId,
            id: 'user-2',
            content: '[PROMPT_REDACTED_2]',
            timestamp: '2026-08-17T04:00:00.000Z',
          ),
          _historyAssistantContentFrame(
            sessionId: sessionId,
            uuid: 'assistant-followup',
            messageId: 'msg-followup',
            timestamp: '2026-08-17T04:00:01.000Z',
            stopReason: 'end_turn',
            content: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': '[RESPONSE_REDACTED_FOLLOWUP]',
              },
            ],
          ),
        ];
        await sessionFile.writeAsString(
          '${frames.map(jsonEncode).join('\n')}\n',
        );
        final reader = ClaudeCodeSessionHistoryReader(
          claudeHome: tempRoot.path,
        );

        final snapshot = await reader.readThreadHistory(
          threadId: sessionId,
          providerId: 'claude-code',
          projectPath: projectPath,
        );

        expect(snapshot.turns, hasLength(2));
        final first = snapshot.turns.first;
        expect(first.status, AgentHistoryTurnStatus.completed);
        expect(first.completedAt, DateTime.utc(2026, 8, 17, 2, 0, 4));
        expect(first.duration, const Duration(seconds: 4));
        expect(first.tokenUsageIsSessionCumulative, isFalse);
        expect(first.tokenUsage?.inputTokens, 13);
        expect(first.tokenUsage?.outputTokens, 22);
        expect(first.tokenUsage?.cachedInputTokens, 4);
        expect(
          first.entries.whereType<AgentHistoryMessageEntry>().map(
            (entry) => entry.text,
          ),
          <String>['[PROMPT_REDACTED_1]', '[RESPONSE_REDACTED_FINAL]'],
        );
        expect(first.entries.whereType<AgentHistoryToolEntry>(), hasLength(2));
        expect(
          snapshot.turns.last.entries.whereType<AgentHistoryMessageEntry>().map(
            (entry) => entry.text,
          ),
          <String>['[PROMPT_REDACTED_2]', '[RESPONSE_REDACTED_FOLLOWUP]'],
        );
      },
    );

    test(
      'keeps split end_turn text when the file ends without another user',
      () async {
        const projectPath = '/workspace/split-end-turn-eof';
        const sessionId = 'split-end-turn-eof-session';
        final projectDirectory = await _projectDirectory(
          tempRoot,
          projectPath,
        ).create(recursive: true);
        final sessionFile = File(
          '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
        );
        final frames = <Map<String, Object?>>[
          _historyUserFrame(
            sessionId: sessionId,
            id: 'user-1',
            content: '[PROMPT_REDACTED]',
            timestamp: '2026-08-17T02:00:00.000Z',
          ),
          _historyAssistantContentFrame(
            sessionId: sessionId,
            uuid: 'assistant-thinking',
            messageId: 'msg-final',
            timestamp: '2026-08-17T02:00:01.000Z',
            stopReason: 'end_turn',
            content: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'thinking',
                'thinking': '',
                'signature': '[SIGNATURE_REDACTED]',
              },
            ],
          ),
          _historyAssistantContentFrame(
            sessionId: sessionId,
            uuid: 'assistant-text',
            messageId: 'msg-final',
            timestamp: '2026-08-17T02:00:02.000Z',
            stopReason: 'end_turn',
            content: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': '[RESPONSE_REDACTED_FINAL]',
              },
            ],
          ),
        ];
        await sessionFile.writeAsString(
          '${frames.map(jsonEncode).join('\n')}\n',
        );
        final reader = ClaudeCodeSessionHistoryReader(
          claudeHome: tempRoot.path,
        );

        final snapshot = await reader.readThreadHistory(
          threadId: sessionId,
          providerId: 'claude-code',
          projectPath: projectPath,
        );

        expect(snapshot.turns, hasLength(1));
        expect(snapshot.turns.single.status, AgentHistoryTurnStatus.completed);
        expect(
          snapshot.turns.single.completedAt,
          DateTime.utc(2026, 8, 17, 2, 0, 2),
        );
        expect(
          snapshot.turns.single.entries
              .whereType<AgentHistoryMessageEntry>()
              .map((entry) => entry.text),
          <String>['[PROMPT_REDACTED]', '[RESPONSE_REDACTED_FINAL]'],
        );
      },
    );

    test(
      'still drops assistant text that arrives after an explicit result frame',
      () async {
        const projectPath = '/workspace/split-end-turn-result';
        const sessionId = 'split-end-turn-result-session';
        final projectDirectory = await _projectDirectory(
          tempRoot,
          projectPath,
        ).create(recursive: true);
        final sessionFile = File(
          '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
        );
        final frames = <Map<String, Object?>>[
          _historyUserFrame(
            sessionId: sessionId,
            id: 'user-1',
            content: '[PROMPT_REDACTED]',
            timestamp: '2026-08-17T02:00:00.000Z',
          ),
          _historyAssistantContentFrame(
            sessionId: sessionId,
            uuid: 'assistant-thinking',
            messageId: 'msg-final',
            timestamp: '2026-08-17T02:00:01.000Z',
            stopReason: 'end_turn',
            content: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'thinking',
                'thinking': '',
                'signature': '[SIGNATURE_REDACTED]',
              },
            ],
          ),
          _historyAssistantContentFrame(
            sessionId: sessionId,
            uuid: 'assistant-text',
            messageId: 'msg-final',
            timestamp: '2026-08-17T02:00:02.000Z',
            stopReason: 'end_turn',
            content: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': '[RESPONSE_REDACTED_FINAL]',
              },
            ],
          ),
          <String, Object?>{
            'type': 'result',
            'subtype': 'success',
            'sessionId': sessionId,
            'uuid': 'result-1',
            'timestamp': '2026-08-17T02:00:03.000Z',
            'usage': <String, Object?>{'input_tokens': 1, 'output_tokens': 1},
          },
          _historyAssistantContentFrame(
            sessionId: sessionId,
            uuid: 'assistant-late',
            messageId: 'msg-late',
            timestamp: '2026-08-17T02:00:04.000Z',
            stopReason: 'end_turn',
            content: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': '[RESPONSE_REDACTED_LATE]',
              },
            ],
          ),
        ];
        await sessionFile.writeAsString(
          '${frames.map(jsonEncode).join('\n')}\n',
        );
        final reader = ClaudeCodeSessionHistoryReader(
          claudeHome: tempRoot.path,
        );

        final snapshot = await reader.readThreadHistory(
          threadId: sessionId,
          providerId: 'claude-code',
          projectPath: projectPath,
        );

        expect(snapshot.turns, hasLength(1));
        expect(
          snapshot.turns.single.entries
              .whereType<AgentHistoryMessageEntry>()
              .map((entry) => entry.text),
          <String>['[PROMPT_REDACTED]', '[RESPONSE_REDACTED_FINAL]'],
        );
        expect(
          snapshot.turns.single.entries
              .whereType<AgentHistoryMessageEntry>()
              .map((entry) => entry.text),
          isNot(contains('[RESPONSE_REDACTED_LATE]')),
        );
      },
    );

    test('lists summaries, skips malformed lines, and stays read-only', () async {
      const projectPath = r'D:\Development\Workspace\zeta';
      const sessionId = 'session-redacted-1';
      final projectDirectory = await _projectDirectory(
        tempRoot,
        projectPath,
      ).create(recursive: true);
      final sessionFile = File(
        '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
      );
      await sessionFile.writeAsString(
        '${jsonEncode(<String, Object?>{
          'type': 'user',
          'sessionId': sessionId,
          'timestamp': '2026-08-10T02:00:00.000Z',
          'message': <String, Object?>{'role': 'user', 'content': '  Review   the history reader contract  '},
        })}\n'
        '{malformed-json}\n'
        '${jsonEncode(<String, Object?>{
          'type': 'assistant',
          'sessionId': sessionId,
          'timestamp': '2026-08-10T02:01:00.000Z',
          'message': <String, Object?>{
            'role': 'assistant',
            'model': 'claude-test-model',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': '[RESPONSE_REDACTED]'},
            ],
          },
        })}\n',
      );
      final beforeDirectoryMtime = (await projectDirectory.stat()).modified;

      final reader = ClaudeCodeSessionHistoryReader(claudeHome: tempRoot.path);
      final page = await reader.listThreads(
        query: const AgentThreadListQuery(projectPath: projectPath, limit: 20),
        providerId: 'claude-code',
      );

      expect(page.threads, hasLength(1));
      final summary = page.threads.single;
      expect(summary.id, sessionId);
      expect(summary.providerId, 'claude-code');
      expect(summary.projectPath, projectPath);
      expect(summary.title, 'Review the history reader contract');
      expect(summary.preview, 'Review the history reader contract');
      expect(summary.sessionPath, sessionFile.path);
      expect(summary.createdAt, DateTime.utc(2026, 8, 10, 2));
      expect(summary.updatedAt, DateTime.utc(2026, 8, 10, 2, 1));
      expect(summary.status, AgentThreadRuntimeStatus.idle);
      expect(reader.malformedLineCount, 1);
      expect((await projectDirectory.stat()).modified, beforeDirectoryMtime);
    });

    test(
      'sorts by recency and paginates without scanning other projects',
      () async {
        const projectPath = '/workspace/zeta';
        final projectDirectory = await _projectDirectory(
          tempRoot,
          projectPath,
        ).create(recursive: true);
        await _writeSession(
          projectDirectory,
          sessionId: 'older-session',
          prompt: 'Older task',
          timestamp: '2026-08-10T01:00:00.000Z',
        );
        await _writeSession(
          projectDirectory,
          sessionId: 'newer-session',
          prompt: 'Newer task',
          timestamp: '2026-08-10T03:00:00.000Z',
        );
        await _writeSession(
          await _projectDirectory(
            tempRoot,
            '/workspace/other',
          ).create(recursive: true),
          sessionId: 'other-project-session',
          prompt: 'Must stay hidden',
          timestamp: '2026-08-10T04:00:00.000Z',
        );

        final reader = ClaudeCodeSessionHistoryReader(
          claudeHome: tempRoot.path,
        );
        final firstPage = await reader.listThreads(
          query: const AgentThreadListQuery(projectPath: projectPath, limit: 1),
          providerId: 'claude-code',
        );
        final secondPage = await reader.listThreads(
          query: AgentThreadListQuery(
            projectPath: projectPath,
            limit: 1,
            cursor: firstPage.nextCursor,
          ),
          providerId: 'claude-code',
        );

        expect(firstPage.threads.single.id, 'newer-session');
        expect(firstPage.nextCursor, '1');
        expect(secondPage.threads.single.id, 'older-session');
        expect(secondPage.nextCursor, isNull);
      },
    );

    test('reads bounded head and tail windows for large history files', () async {
      const projectPath = '/workspace/large';
      const sessionId = 'large-session';
      final projectDirectory = await _projectDirectory(
        tempRoot,
        projectPath,
      ).create(recursive: true);
      final sessionFile = File(
        '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
      );
      final middle = List<String>.filled(
        200,
        jsonEncode(<String, Object?>{
          'type': 'progress',
          'payload': '[MIDDLE_REDACTED]'.padRight(256, '-'),
        }),
      ).join('\n');
      await sessionFile.writeAsString(
        '${jsonEncode(<String, Object?>{
          'type': 'user',
          'sessionId': sessionId,
          'timestamp': '2026-08-10T01:00:00.000Z',
          'message': <String, Object?>{'role': 'user', 'content': 'Large history task'},
        })}\n'
        '$middle\n'
        '${jsonEncode(<String, Object?>{
          'type': 'assistant',
          'sessionId': sessionId,
          'timestamp': '2026-08-10T02:00:00.000Z',
          'message': <String, Object?>{'role': 'assistant', 'model': 'tail-model', 'content': '[RESPONSE_REDACTED]'},
        })}\n',
      );

      final reader = ClaudeCodeSessionHistoryReader(
        claudeHome: tempRoot.path,
        sampleWindowBytes: 2048,
        sampleLineLimit: 8,
      );
      final page = await reader.listThreads(
        query: const AgentThreadListQuery(projectPath: projectPath, limit: 20),
        providerId: 'claude-code',
      );

      expect(page.threads.single.title, 'Large history task');
      expect(page.threads.single.updatedAt, DateTime.utc(2026, 8, 10, 2));
    });

    test(
      'reads one discovered project history without returning its source path',
      () async {
        const projectPath = '/workspace/usage-source';
        const sessionId = 'usage-session';
        final projectDirectory = await _projectDirectory(
          tempRoot,
          projectPath,
        ).create(recursive: true);
        final sessionFile = File(
          '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
        );
        await sessionFile.writeAsString(
          '${jsonEncode(<String, Object?>{
            'type': 'user',
            'sessionId': sessionId,
            'uuid': 'usage-user',
            'timestamp': '2026-08-10T05:00:00.000Z',
            'cwd': projectPath,
            'message': <String, Object?>{'role': 'user', 'content': '[PROMPT_REDACTED]'},
          })}\n'
          '${jsonEncode(<String, Object?>{
            'type': 'assistant',
            'sessionId': sessionId,
            'uuid': 'usage-assistant',
            'timestamp': '2026-08-10T05:00:01.000Z',
            'message': <String, Object?>{
              'role': 'assistant',
              'model': 'claude-test-model',
              'stop_reason': 'end_turn',
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': '[RESPONSE_REDACTED]'},
              ],
              'usage': <String, Object?>{'input_tokens': 3, 'output_tokens': 2, 'cache_creation_input_tokens': 5, 'cache_read_input_tokens': 7},
            },
          })}\n',
        );
        final reader = ClaudeCodeSessionHistoryReader(
          claudeHome: tempRoot.path,
        );

        final result = await reader.readLocalHistoryFile(
          file: sessionFile,
          providerId: 'claude-code',
        );

        expect(result?.threadId, sessionId);
        expect(result?.projectPath, projectPath);
        expect(result?.history.snapshot.turns, hasLength(1));
        final turn = result!.history.snapshot.turns.single;
        expect(turn.tokenUsageIsSessionCumulative, isFalse);
        expect(turn.tokenUsage?.cachedInputTokens, 12);
        expect(result.toString(), isNot(contains(sessionFile.path)));

        final outside = File(
          '${tempRoot.path}${Platform.pathSeparator}outside.jsonl',
        );
        await outside.writeAsString(await sessionFile.readAsString());
        expect(
          await reader.readLocalHistoryFile(
            file: outside,
            providerId: 'claude-code',
          ),
          isNull,
        );
      },
    );

    test('hides a listed thread without modifying Claude history', () async {
      const projectPath = '/workspace/hidden';
      const sessionId = 'hidden-session';
      final projectDirectory = await _projectDirectory(
        tempRoot,
        projectPath,
      ).create(recursive: true);
      await _writeSession(
        projectDirectory,
        sessionId: sessionId,
        prompt: 'Hide this session locally',
        timestamp: '2026-08-10T04:00:00.000Z',
      );
      final sessionFile = File(
        '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
      );
      final beforeBytes = await sessionFile.readAsBytes();
      final beforeModified = (await sessionFile.stat()).modified;
      final beforeDirectoryModified = (await projectDirectory.stat()).modified;
      final zetaState = await Directory.systemTemp.createTemp(
        'zeta-claude-hidden-state-',
      );
      addTearDown(() async {
        if (await zetaState.exists()) {
          await zetaState.delete(recursive: true);
        }
      });
      final hiddenFile = File(
        '${zetaState.path}${Platform.pathSeparator}hidden_threads.json',
      );
      final reader = ClaudeCodeSessionHistoryReader(
        claudeHome: tempRoot.path,
        hiddenThreadStore: FileClaudeCodeHiddenThreadStore(
          storage: AtomicTextFile(hiddenFile),
        ),
      );

      final visible = await reader.listThreads(
        query: const AgentThreadListQuery(projectPath: projectPath, limit: 20),
        providerId: 'claude-code',
      );
      expect(visible.threads.single.id, sessionId);

      await reader.removeThreadFromList(sessionId);
      final hidden = await reader.listThreads(
        query: const AgentThreadListQuery(projectPath: projectPath, limit: 20),
        providerId: 'claude-code',
      );

      expect(hidden.threads, isEmpty);
      expect(await sessionFile.readAsBytes(), beforeBytes);
      expect((await sessionFile.stat()).modified, beforeModified);
      expect((await projectDirectory.stat()).modified, beforeDirectoryModified);
      expect(
        await projectDirectory.list(followLinks: false).toList(),
        hasLength(1),
      );
      final encodedHidden = await hiddenFile.readAsString();
      expect(
        encodedHidden,
        contains(
          ClaudeCodeSessionHistoryReader.hiddenThreadKey(
            projectPath,
            sessionId,
          ),
        ),
      );
    });
  });
}

Directory _projectDirectory(Directory claudeHome, String projectPath) {
  final encoded = ClaudeCodeSessionHistoryReader.encodeProjectPath(projectPath);
  return Directory(
    '${claudeHome.path}${Platform.pathSeparator}projects'
    '${Platform.pathSeparator}$encoded',
  );
}

Future<void> _writeSession(
  Directory projectDirectory, {
  required String sessionId,
  required String prompt,
  required String timestamp,
}) {
  final file = File(
    '${projectDirectory.path}${Platform.pathSeparator}$sessionId.jsonl',
  );
  return file.writeAsString(
    '${jsonEncode(<String, Object?>{
      'type': 'user',
      'sessionId': sessionId,
      'timestamp': timestamp,
      'message': <String, Object?>{'role': 'user', 'content': prompt},
    })}\n',
  );
}

Map<String, Object?> _historyUserFrame({
  required String sessionId,
  required String id,
  required String content,
  String timestamp = '2026-08-12T02:00:00.000Z',
}) {
  return <String, Object?>{
    'type': 'user',
    'sessionId': sessionId,
    'uuid': id,
    'timestamp': timestamp,
    'message': <String, Object?>{'role': 'user', 'content': content},
  };
}

Map<String, Object?> _historyAssistantContentFrame({
  required String sessionId,
  required String uuid,
  required String messageId,
  required String timestamp,
  required List<Map<String, Object?>> content,
  String? stopReason,
  Map<String, Object?>? usage,
}) {
  return <String, Object?>{
    'type': 'assistant',
    'sessionId': sessionId,
    'uuid': uuid,
    'timestamp': timestamp,
    'message': <String, Object?>{
      'id': messageId,
      'role': 'assistant',
      'model': 'claude-test-model',
      'stop_reason': ?stopReason,
      'content': content,
      'usage': ?usage,
    },
  };
}

Map<String, Object?> _historyAssistantFrame({
  required String sessionId,
  required String id,
  String? effort,
  bool endTurn = false,
}) {
  return <String, Object?>{
    'type': 'assistant',
    'sessionId': sessionId,
    'uuid': id,
    'timestamp': '2026-08-12T02:00:01.000Z',
    'effort': ?effort,
    'message': <String, Object?>{
      'role': 'assistant',
      'model': 'claude-test-model',
      'stop_reason': endTurn ? 'end_turn' : null,
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': '[RESPONSE_REDACTED]'},
      ],
    },
  };
}
