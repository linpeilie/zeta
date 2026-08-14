import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_turn_context_store.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_context_models.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_history_models.dart';

void main() {
  group('FileAgentTurnContextStore', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('zeta-turn-context-');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('upserts start then complete into one encoded thread file', () async {
      final store = FileAgentTurnContextStore(rootDirectory: tempRoot);
      const started = AgentThreadTurnContext(
        providerId: 'grok',
        threadId: 'sess-1',
        turns: <AgentTurnContextRecord>[
          AgentTurnContextRecord(
            turnId: 'turn-1',
            modelId: 'grok-4',
            reasoningEffort: 'high',
          ),
        ],
      );

      await store.save(started);
      final existing = await store.load(providerId: 'grok', threadId: 'sess-1');
      await store.save(
        existing!.upsertTurn(
          const AgentTurnContextRecord(
            turnId: 'turn-1',
            status: AgentHistoryTurnStatus.completed,
          ),
        ),
      );

      final loaded = await store.load(providerId: 'grok', threadId: 'sess-1');
      expect(loaded, isNotNull);
      expect(loaded!.turns, hasLength(1));
      expect(loaded.turns.single.modelId, 'grok-4');
      expect(loaded.turns.single.reasoningEffort, 'high');
      expect(loaded.turns.single.status, AgentHistoryTurnStatus.completed);

      final file = File(
        '${tempRoot.path}${Platform.pathSeparator}grok'
        '${Platform.pathSeparator}sess-1.json',
      );
      expect(file.existsSync(), isTrue);
      final decoded = jsonDecode(await file.readAsString()) as Map;
      expect(decoded['version'], 1);
      expect(await file.readAsString(), isNot(contains('prompt')));
    });

    test('does not let a later null overwrite an existing effort', () async {
      final store = FileAgentTurnContextStore(rootDirectory: tempRoot);
      await store.save(
        const AgentThreadTurnContext(
          providerId: 'codex',
          threadId: 'thread-1',
          turns: <AgentTurnContextRecord>[
            AgentTurnContextRecord(turnId: 'turn-1', reasoningEffort: 'high'),
          ],
        ),
      );
      final existing = await store.load(
        providerId: 'codex',
        threadId: 'thread-1',
      );
      await store.save(
        existing!.upsertTurn(const AgentTurnContextRecord(turnId: 'turn-1')),
      );

      final loaded = await store.load(
        providerId: 'codex',
        threadId: 'thread-1',
      );
      expect(loaded!.turns.single.reasoningEffort, 'high');
    });

    test('keeps different threads in different files', () async {
      final store = FileAgentTurnContextStore(rootDirectory: tempRoot);
      await store.save(
        const AgentThreadTurnContext(
          providerId: 'grok',
          threadId: 'sess-a',
          turns: <AgentTurnContextRecord>[
            AgentTurnContextRecord(turnId: 'turn-a'),
          ],
        ),
      );
      await store.save(
        const AgentThreadTurnContext(
          providerId: 'grok',
          threadId: 'sess-b',
          turns: <AgentTurnContextRecord>[
            AgentTurnContextRecord(turnId: 'turn-b'),
          ],
        ),
      );

      expect(
        (await store.load(
          providerId: 'grok',
          threadId: 'sess-a',
        ))!.turns.single.turnId,
        'turn-a',
      );
      expect(
        (await store.load(
          providerId: 'grok',
          threadId: 'sess-b',
        ))!.turns.single.turnId,
        'turn-b',
      );
    });

    test(
      'encodes unsafe thread ids and treats corrupt files as missing',
      () async {
        final store = FileAgentTurnContextStore(rootDirectory: tempRoot);
        await store.save(
          const AgentThreadTurnContext(
            providerId: 'claude_code',
            threadId: 'sess/with/slash',
            turns: <AgentTurnContextRecord>[
              AgentTurnContextRecord(turnId: 'turn-1'),
            ],
          ),
        );

        final encoded = encodeAgentTurnContextPathSegment('sess/with/slash');
        expect(encoded, isNotNull);
        expect(encoded, isNot(contains('/')));
        expect(
          File(
            '${tempRoot.path}${Platform.pathSeparator}claude_code'
            '${Platform.pathSeparator}$encoded.json',
          ).existsSync(),
          isTrue,
        );

        final corrupt = File(
          '${tempRoot.path}${Platform.pathSeparator}grok'
          '${Platform.pathSeparator}broken.json',
        );
        await corrupt.parent.create(recursive: true);
        await corrupt.writeAsString('{broken');
        expect(
          await store.load(providerId: 'grok', threadId: 'broken'),
          isNull,
        );
      },
    );
  });
}
