import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final schemaDirectory = Directory(
    '../../third_party/codex_app_server_schema',
  );

  group('pinned Codex app-server schema', () {
    test('keeps the complete stable 0.144.5 snapshot', () {
      expect(schemaDirectory.existsSync(), isTrue);
      expect(
        File('${schemaDirectory.path}/PINNED_VERSION')
            .readAsStringSync()
            .trim(),
        '0.144.5',
      );
      final generated = _readJson(
        File('${schemaDirectory.path}/GENERATED.json'),
      );
      expect(generated['codexCliVersion'], '0.144.5');
      expect(generated['experimental'], isFalse);
      expect(
        schemaDirectory.listSync(recursive: true).whereType<File>(),
        hasLength(269),
      );
    });

    test('contains every stable request adapted by the client', () {
      final methods = _methodNames(
        _readJson(File('${schemaDirectory.path}/ClientRequest.json')),
      );
      expect(
        methods,
        containsAll(<String>[
          'initialize',
          'thread/start',
          'thread/resume',
          'thread/read',
          'thread/list',
          'thread/unsubscribe',
          'thread/name/set',
          'thread/archive',
          'thread/unarchive',
          'thread/delete',
          'thread/compact/start',
          'thread/fork',
          'turn/start',
          'turn/interrupt',
          'turn/steer',
          'model/list',
          'permissionProfile/list',
          'account/rateLimits/read',
        ]),
      );
    });

    test('pins message chunks and terminal notification methods', () {
      final methods = _methodNames(
        _readJson(File('${schemaDirectory.path}/ServerNotification.json')),
      );
      expect(
        methods,
        containsAll(<String>[
          'thread/started',
          'thread/status/changed',
          'turn/started',
          'turn/completed',
          'turn/diff/updated',
          'item/started',
          'item/completed',
          'item/agentMessage/delta',
          'item/reasoning/summaryTextDelta',
          'item/reasoning/textDelta',
          'item/commandExecution/outputDelta',
          'item/fileChange/outputDelta',
          'thread/tokenUsage/updated',
          'account/rateLimits/updated',
        ]),
      );
    });

    test('pins every approval and user-input server request', () {
      final methods = _methodNames(
        _readJson(File('${schemaDirectory.path}/ServerRequest.json')),
      );
      expect(
        methods,
        containsAll(<String>[
          'item/commandExecution/requestApproval',
          'item/fileChange/requestApproval',
          'item/permissions/requestApproval',
          'item/tool/requestUserInput',
          'mcpServer/elicitation/request',
        ]),
      );
    });
  });
}

Map<String, Object?> _readJson(File file) {
  return jsonDecode(file.readAsStringSync())! as Map<String, Object?>;
}

Set<String> _methodNames(Object? value) {
  final methods = <String>{};

  void visit(Object? node) {
    if (node is Map<String, Object?>) {
      final methodSchema = node['method'];
      if (methodSchema is Map<String, Object?>) {
        final values = methodSchema['enum'];
        if (values is List<Object?>) {
          methods.addAll(values.whereType<String>());
        }
      }
      node.values.forEach(visit);
      return;
    }
    if (node is List<Object?>) {
      node.forEach(visit);
    }
  }

  visit(value);
  return methods;
}
