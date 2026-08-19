import 'dart:convert';
import 'dart:io';

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';
import 'package:zeta_storage/zeta_storage.dart';

void main() {
  const codec = AgentTurnContextCodec();
  final context = AgentThreadTurnContext(
    providerId: 'codex/provider',
    threadId: 'thread:1',
    turns: <AgentTurnContextRecord>[
      AgentTurnContextRecord(
        turnId: 'turn-1',
        modelId: 'gpt-5',
        reasoningEffort: 'high',
        serviceTierId: 'priority',
        explicitFast: true,
        startedAt: DateTime.utc(2026, 8, 19, 1),
        completedAt: DateTime.utc(2026, 8, 19, 2),
        status: AgentHistoryTurnStatus.completed,
      ),
      const AgentTurnContextRecord(turnId: 'turn-2'),
    ],
  );

  group('AgentTurnContextCodec', () {
    test('round trips allowlisted metadata and nullable fields', () {
      final decoded = codec.decode(codec.encode(context));
      expect(decoded.providerId, context.providerId);
      expect(decoded.threadId, context.threadId);
      expect(decoded.version, AgentThreadTurnContext.currentVersion);
      final first = decoded.turns.first;
      expect(first.turnId, 'turn-1');
      expect(first.modelId, 'gpt-5');
      expect(first.reasoningEffort, 'high');
      expect(first.serviceTierId, 'priority');
      expect(first.explicitFast, isTrue);
      expect(first.startedAt, DateTime.utc(2026, 8, 19, 1));
      expect(first.completedAt, DateTime.utc(2026, 8, 19, 2));
      expect(first.status, AgentHistoryTurnStatus.completed);
      expect(decoded.turns.last.modelId, isNull);
      expect(decoded.turns.last.status, isNull);
    });

    test('rejects non-current context on encode', () {
      expect(
        () => codec.encode(
          AgentThreadTurnContext(
            providerId: 'codex',
            threadId: 'thread',
            version: 2,
          ),
        ),
        _failure(AgentConfigDecodeReason.unsupportedVersion),
      );
    });

    test('rejects malformed roots, turns, dates, status, and duplicates', () {
      final root = jsonDecode(codec.encode(context)) as Map<String, Object?>;
      final first = Map<String, Object?>.from(
        (root['turns']! as List<Object?>).first! as Map<String, Object?>,
      );
      final corruptions = <Object?>[
        'bad-json-marker',
        <Object?>[],
        <String, Object?>{...root, 'version': 2},
        <String, Object?>{...root, 'turns': true},
        <String, Object?>{...root, 'providerId': ''},
        <String, Object?>{
          ...root,
          'turns': <Object?>[
            <String, Object?>{...first, 'turnId': ''},
          ],
        },
        <String, Object?>{
          ...root,
          'turns': <Object?>[
            <String, Object?>{...first, 'explicitFast': 1},
          ],
        },
        <String, Object?>{
          ...root,
          'turns': <Object?>[
            <String, Object?>{...first, 'startedAt': 'bad'},
          ],
        },
        <String, Object?>{
          ...root,
          'turns': <Object?>[
            <String, Object?>{...first, 'status': 'other'},
          ],
        },
        <String, Object?>{
          ...root,
          'turns': <Object?>[first, first],
        },
      ];
      for (final corruption in corruptions) {
        final source = corruption == 'bad-json-marker'
            ? '{'
            : jsonEncode(corruption);
        expect(
          () => codec.decode(source),
          throwsA(isA<AgentConfigDecodeException>()),
        );
      }
    });
  });

  group('FileAgentTurnContextStore', () {
    late Directory directory;
    late FileAgentTurnContextStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('zeta_turns_');
      store = FileAgentTurnContextStore(rootDirectory: directory);
    });

    tearDown(() => directory.delete(recursive: true));

    test(
      'returns null when missing and atomically overwrites one thread',
      () async {
        expect(
          await store.load(
            providerId: context.providerId,
            threadId: context.threadId,
          ),
          isNull,
        );
        await store.save(context);
        expect(
          (await store.load(
            providerId: context.providerId,
            threadId: context.threadId,
          ))!.turns,
          hasLength(2),
        );
        final replacement = AgentThreadTurnContext(
          providerId: context.providerId,
          threadId: context.threadId,
          turns: const <AgentTurnContextRecord>[
            AgentTurnContextRecord(turnId: 'replacement'),
          ],
        );
        await store.save(replacement);
        expect(
          (await store.load(
            providerId: context.providerId,
            threadId: context.threadId,
          ))!.turns.single.turnId,
          'replacement',
        );
        expect(
          directory.listSync(recursive: true).whereType<File>(),
          hasLength(1),
        );
      },
    );

    test(
      'fails closed when stored identity differs from requested path',
      () async {
        await store.save(context);
        final provider = encodeAgentTurnContextPathSegment(context.providerId)!;
        final thread = encodeAgentTurnContextPathSegment(context.threadId)!;
        final file = File(
          <String>[
            directory.path,
            provider,
            '$thread.json',
          ].join(Platform.pathSeparator),
        );
        final root =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        await file.writeAsString(
          jsonEncode(<String, Object?>{...root, 'threadId': 'other'}),
        );
        await expectLater(
          store.load(
            providerId: context.providerId,
            threadId: context.threadId,
          ),
          _failure(AgentConfigDecodeReason.identityMismatch),
        );
      },
    );

    test('propagates corruption from an existing file', () async {
      final provider = encodeAgentTurnContextPathSegment('codex')!;
      final thread = encodeAgentTurnContextPathSegment('thread')!;
      final file = File(
        <String>[
          directory.path,
          provider,
          '$thread.json',
        ].join(Platform.pathSeparator),
      );
      await file.create(recursive: true);
      await file.writeAsString('');
      await expectLater(
        store.load(providerId: 'codex', threadId: 'thread'),
        _failure(AgentConfigDecodeReason.invalidJson),
      );
    });

    test('rejects unsafe identifiers before filesystem access', () async {
      for (final value in <String>[
        '',
        '.',
        '..',
        'line\nbreak',
        'line\rbreak',
        'null\u0000byte',
        List<String>.filled(129, 'x').join(),
      ]) {
        expect(encodeAgentTurnContextPathSegment(value), isNull);
        await expectLater(
          store.load(providerId: value, threadId: 'thread'),
          throwsA(isA<StoragePathException>()),
        );
      }
      expect(
        encodeAgentTurnContextPathSegment(' codex/provider '),
        'codex%2Fprovider',
      );
    });
  });
}

Matcher _failure(AgentConfigDecodeReason reason) {
  return throwsA(
    isA<AgentConfigDecodeException>().having(
      (error) => error.reason,
      'reason',
      reason,
    ),
  );
}
