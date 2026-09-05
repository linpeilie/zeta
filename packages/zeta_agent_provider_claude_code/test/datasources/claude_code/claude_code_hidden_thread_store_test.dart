import 'dart:convert';
import 'dart:io';

import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart';
import 'package:test/test.dart';
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code_testing.dart';

void main() {
  group('FileClaudeCodeHiddenThreadStore', () {
    late Directory tempRoot;
    late File storeFile;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('zeta-claude-hidden-');
      storeFile = File(
        '${tempRoot.path}${Platform.pathSeparator}state'
        '${Platform.pathSeparator}hidden_threads.json',
      );
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('missing fields and corrupt JSON decode as empty', () async {
      final store = FileClaudeCodeHiddenThreadStore(
        storage: FileTestStorageService(storeFile),
      );

      await storeFile.parent.create(recursive: true);
      await storeFile.writeAsString('{broken-json');
      expect(await store.load(), isEmpty);

      await storeFile.writeAsString(
        jsonEncode(<String, Object?>{'version': 1, 'unknown': true}),
      );
      expect(await store.load(), isEmpty);
    });

    test('unsupported versions decode as empty', () async {
      final store = FileClaudeCodeHiddenThreadStore(
        storage: FileTestStorageService(storeFile),
      );
      await storeFile.parent.create(recursive: true);
      await storeFile.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 0,
          'hiddenThreads': <Object?>['-workspace-zeta/session-2', '', 42],
          'unknown': 'ignored',
        }),
      );

      expect(await store.load(), isEmpty);
    });

    test('writes only the versioned key whitelist', () async {
      final store = FileClaudeCodeHiddenThreadStore(
        storage: FileTestStorageService(storeFile),
      );

      await store.save(<String>{
        '-workspace-zeta/session-2',
        '-workspace-zeta/session-1',
      });

      final decoded = jsonDecode(await storeFile.readAsString()) as Map;
      expect(decoded.keys, <Object?>['version', 'hiddenThreadKeys']);
      expect(decoded['version'], 1);
      expect(decoded['hiddenThreadKeys'], <Object?>[
        '-workspace-zeta/session-1',
        '-workspace-zeta/session-2',
      ]);
      final encoded = await storeFile.readAsString();
      expect(encoded, isNot(contains('prompt')));
      expect(encoded, isNot(contains('response')));
      expect(encoded, isNot(contains('raw')));
    });
  });
}
