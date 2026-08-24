import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('已删除的 legacy owner 与 Conversation fallback 不得复活', () {
    expect(
      File(
        'lib/src/features/desktop_notifications/application/'
        'desktop_attention_controller.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/src/features/agent/application/'
        'agent_thread_workspace_controller.dart',
      ).existsSync(),
      isFalse,
    );

    final production = <File>[
      File('lib/main.dart'),
      ...Directory('lib/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
    for (final legacy in const <String>[
      'conversationSliceEnabled',
      'agentConversationSliceEnabledProvider',
      'legacyListenable',
      'AgentConversationSliceStoreResolverNotifier',
      'agentConversationSliceStoreResolverProvider',
      'AgentThreadWorkspaceController',
    ]) {
      final offenders = <String>[
        for (final file in production)
          if (file.readAsStringSync().contains(legacy)) file.path,
      ];
      expect(offenders, isEmpty, reason: '$legacy: $offenders');
    }
  });

  test(
    'Workspace reducer is pure and Shell owns no duplicate workspace state',
    () {
      for (final path in const <String>[
        'lib/src/app/conversation_workspace_slice/'
            'agent_conversation_workspace_state.dart',
        'lib/src/app/conversation_workspace_slice/'
            'agent_conversation_workspace_intent.dart',
        'lib/src/app/conversation_workspace_slice/'
            'agent_conversation_workspace_reducer.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('package:flutter/')), reason: path);
        expect(source, isNot(contains('riverpod')), reason: path);
        expect(source, isNot(contains('Future<')), reason: path);
        expect(source, isNot(contains('Timer(')), reason: path);
      }

      final shell = File(
        'lib/src/app/shell/ide_shell_controller.dart',
      ).readAsStringSync();
      for (final duplicateOwner in const <String>[
        '_workspaceEntryListeners',
        '_selectedWorkspaceThreadSnapshotBinding',
        '_agentThreadIdsByProject',
        '_projectHomeActive',
        '_refreshWorkspaceEntryBindings',
        '_bindSelectedWorkspaceRuntime',
      ]) {
        expect(shell, isNot(contains(duplicateOwner)), reason: duplicateOwner);
      }
    },
  );

  test('Composer application owners and Desktop Attention store stay pure', () {
    for (final path in const <String>[
      'lib/src/features/agent/application/'
          'agent_conversation_mode_controller.dart',
      'lib/src/features/agent/application/'
          'agent_conversation_model_selection_controller.dart',
      'lib/src/features/agent/application/agent_skills_catalog_controller.dart',
      'lib/src/features/desktop_notifications/application/'
          'desktop_attention_slice_reducer.dart',
      'lib/src/features/desktop_notifications/application/'
          'desktop_attention_slice_store.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: path);
      expect(source, isNot(contains('ChangeNotifier')), reason: path);
      expect(source, isNot(contains('riverpod')), reason: path);
    }

    final attentionStore = File(
      'lib/src/features/desktop_notifications/application/'
      'desktop_attention_slice_store.dart',
    ).readAsStringSync();
    expect(attentionStore, isNot(contains('DesktopNotificationService')));
    expect(attentionStore, isNot(contains('DesktopAttentionIndicator')));

    final viewModel = File(
      'lib/src/features/agent/presentation/agent_conversation_view_model.dart',
    ).readAsStringSync();
    expect(viewModel, contains('required AgentConversationComposerStateOwner'));
    expect(viewModel, isNot(contains('_ownsModelSelectionController')));
    expect(viewModel, isNot(contains('_ownsConversationModeController')));
    expect(viewModel, isNot(contains('_ownsSkillsCatalogController')));
  });
}
