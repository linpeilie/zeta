import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('ClaudeCodePermissionPolicyAdapter', () {
    test('normalizes selection and reports provider apply scope', () async {
      ClaudeCodePermissionMode? appliedMode;
      final adapter = ClaudeCodePermissionPolicyAdapter(
        applyPermissionMode: (mode) async {
          appliedMode = mode;
          return AgentPermissionApplyScope.currentSession;
        },
      );

      final catalog = await adapter.listPermissionOptions();
      final result = await adapter.applyPermissionSelection(
        const AgentPermissionSelection(optionId: ':accept-edits'),
      );

      expect(catalog.defaultOptionId, ':ask');
      expect(catalog.options, hasLength(4));
      expect(appliedMode, ClaudeCodePermissionMode.acceptEdits);
      expect(result.normalizedSelection.optionId, ':accept-edits');
      expect(result.scope, AgentPermissionApplyScope.currentSession);
    });

    test('file cache persists only version toolName and decision', () async {
      final directory = await Directory.systemTemp.createTemp(
        'zeta-claude-permission-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}session.json',
      );
      final store = FileClaudeCodeSessionDecisionStore(
        storage: AtomicTextFile(file),
      );
      final adapter = ClaudeCodePermissionPolicyAdapter(
        applyPermissionMode: (_) async => AgentPermissionApplyScope.nextSession,
        sessionDecisionStoreFactory: (_) => store,
      );

      await adapter.bindSession('session-sensitive-id');
      await adapter.rememberToolDecision(
        'Bash',
        ClaudeCodeSessionToolDecision.allow,
      );

      final decoded = jsonDecode(await file.readAsString()) as Map;
      expect(
        decoded['version'],
        FileClaudeCodeSessionDecisionStore.currentVersion,
      );
      expect(decoded.keys, unorderedEquals(<Object?>['version', 'decisions']));
      expect(decoded['decisions'], <Object?>[
        <String, Object?>{'toolName': 'Bash', 'decision': 'allow'},
      ]);
      final source = await file.readAsString();
      expect(source, isNot(contains('input')));
      expect(source, isNot(contains('prompt')));
      expect(source, isNot(contains('session-sensitive-id')));
      expect(source, isNot(contains(directory.path)));

      final reloaded = ClaudeCodePermissionPolicyAdapter(
        applyPermissionMode: (_) async => AgentPermissionApplyScope.nextSession,
        sessionDecisionStoreFactory: (_) =>
            FileClaudeCodeSessionDecisionStore(storage: AtomicTextFile(file)),
      );
      await reloaded.bindSession('session-sensitive-id');
      expect(
        reloaded.decisionForTool('Bash'),
        ClaudeCodeSessionToolDecision.allow,
      );
    });

    test('file cache tolerates damaged and unknown-version JSON', () async {
      final directory = await Directory.systemTemp.createTemp(
        'zeta-claude-permission-corrupt-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}session.json',
      );
      final store = FileClaudeCodeSessionDecisionStore(
        storage: AtomicTextFile(file),
      );

      await file.writeAsString('{damaged');
      expect(await store.load(), isEmpty);

      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 99,
          'decisions': <Object?>[
            <String, Object?>{'toolName': 'Bash', 'decision': 'allow'},
          ],
        }),
      );
      expect(await store.load(), isEmpty);
    });

    test(
      'removes stale AskUserQuestion decisions during session bind',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'zeta-claude-question-decision-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File(
          '${directory.path}${Platform.pathSeparator}session.json',
        );
        await file.writeAsString(
          jsonEncode(<String, Object?>{
            'version': FileClaudeCodeSessionDecisionStore.currentVersion,
            'decisions': <Object?>[
              <String, Object?>{
                'toolName': 'AskUserQuestion',
                'decision': 'deny',
              },
              <String, Object?>{'toolName': 'Bash', 'decision': 'allow'},
            ],
          }),
        );
        final adapter = ClaudeCodePermissionPolicyAdapter(
          applyPermissionMode: (_) async =>
              AgentPermissionApplyScope.nextSession,
          sessionDecisionStoreFactory: (_) =>
              FileClaudeCodeSessionDecisionStore(storage: AtomicTextFile(file)),
        );

        await adapter.bindSession('session-question-cache');
        await adapter.rememberToolDecision(
          'AskUserQuestion',
          ClaudeCodeSessionToolDecision.allow,
        );

        expect(adapter.decisionForTool('AskUserQuestion'), isNull);
        expect(
          adapter.decisionForTool('Bash'),
          ClaudeCodeSessionToolDecision.allow,
        );
        final decoded = jsonDecode(await file.readAsString()) as Map;
        expect(decoded['decisions'], <Object?>[
          <String, Object?>{'toolName': 'Bash', 'decision': 'allow'},
        ]);
      },
    );
  });
}
