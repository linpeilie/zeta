import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/data/agent/agent_provider_config_store.dart';
import 'package:zeta/src/domain/agent/agent_models.dart';
import 'package:zeta/src/domain/agent/agent_provider.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/ui/features/ide/view_models/agent_conversation_view_model.dart';
import 'package:zeta/src/ui/features/ide/views/agent_pane.dart';

void main() {
  group('AgentPane PR3', () {
    testWidgets(
      'collapses heavy history markdown and expanding it keeps history version stable',
      (tester) async {
        final viewModel = _createViewModel(
          _FakeAgentProvider(
            historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
              'thread-markdown': AgentThreadHistorySnapshot(
                threadId: 'thread-markdown',
                turns: <AgentHistoryTurn>[
                  AgentHistoryTurn(
                    id: 'turn-markdown-1',
                    entries: <AgentHistoryEntry>[
                      const AgentHistoryMessageEntry(
                        id: 'history-user-markdown-1',
                        role: AgentMessageRole.user,
                        text: 'Show heavy markdown',
                      ),
                      AgentHistoryMessageEntry(
                        id: 'history-markdown-1',
                        role: AgentMessageRole.agent,
                        text: List<String>.generate(
                          18,
                          (index) => 'Markdown line ${index + 1}',
                        ).join('\n\n'),
                      ),
                    ],
                  ),
                ],
              ),
            },
          ),
        );
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(_TestApp(viewModel: viewModel));
        await viewModel.switchThread(
          _thread(id: 'thread-markdown', title: 'Heavy markdown'),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const ValueKey<String>('agent-markdown-preview-history-markdown-1'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey<String>('agent-markdown-body-history-markdown-1'),
          ),
          findsNothing,
        );
        expect(
          find.textContaining('Markdown line 16', findRichText: true),
          findsNothing,
        );

        final historyVersion = viewModel.historyVersion;
        await tester.tap(
          find.byKey(
            const ValueKey<String>('agent-markdown-toggle-history-markdown-1'),
          ),
        );
        await tester.pumpAndSettle();

        expect(viewModel.historyVersion, historyVersion);
        expect(
          find.byKey(
            const ValueKey<String>('agent-markdown-body-history-markdown-1'),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('Markdown line 16', findRichText: true),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'keeps large diffs lazy and expanding all does not change history version',
      (tester) async {
        final viewModel = _createViewModel(
          _FakeAgentProvider(
            historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
              'thread-diff': AgentThreadHistorySnapshot(
                threadId: 'thread-diff',
                turns: <AgentHistoryTurn>[
                  AgentHistoryTurn(
                    id: 'turn-diff-1',
                    entries: <AgentHistoryEntry>[
                      const AgentHistoryMessageEntry(
                        id: 'history-user-diff-1',
                        role: AgentMessageRole.user,
                        text: 'Show large diff',
                      ),
                      AgentHistoryToolEntry(
                        toolCall: AgentToolCall(
                          id: 'history-edit-large',
                          title: 'Apply patch',
                          kind: AgentToolKind.edit,
                          status: AgentToolStatus.completed,
                          locations: const <String>['lib/main.dart'],
                          rawOutput: _patchApplyChanges(<String, String?>{
                            'lib/main.dart': _largeUnifiedDiff(),
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            },
          ),
        );
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(_TestApp(viewModel: viewModel));
        await viewModel.switchThread(
          _thread(id: 'thread-diff', title: 'Large diff'),
        );
        await tester.pumpAndSettle();

        final historyVersion = viewModel.historyVersion;
        await tester.tap(
          find.byKey(
            ValueKey<String>(
              'agent-file-edit-group-header-${_fileEditGroupId('turn-diff-1', 'history-edit-large')}',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(viewModel.historyVersion, historyVersion);

        await tester.tap(
          find.byKey(
            const ValueKey<String>(
              'agent-file-edit-item-row-file-edit-history-edit-large-lib/main.dart',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(viewModel.historyVersion, historyVersion);
        expect(
          find.byKey(
            const ValueKey<String>(
              'agent-file-edit-item-expand-all-file-edit-history-edit-large-lib/main.dart',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('+line 30', findRichText: true),
          findsNothing,
        );

        final expandAllFinder = find.byKey(
          const ValueKey<String>(
            'agent-file-edit-item-expand-all-file-edit-history-edit-large-lib/main.dart',
          ),
        );
        await tester.ensureVisible(expandAllFinder);
        await tester.tap(expandAllFinder);
        await tester.pumpAndSettle();

        expect(viewModel.historyVersion, historyVersion);
        expect(
          find.textContaining('+line 30', findRichText: true),
          findsOneWidget,
        );
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.viewModel});

  final AgentConversationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildCompactTheme(),
      home: Scaffold(body: AgentPane(viewModel: viewModel)),
    );
  }
}

AgentConversationViewModel _createViewModel(_FakeAgentProvider provider) {
  final controller = ActiveAgentProviderController(
    providerFactory: _FakeAgentProviderFactory(provider),
    configStore: MemoryAgentProviderConfigStore(),
  );
  addTearDown(controller.dispose);
  final viewModel = AgentConversationViewModel(providerController: controller);
  viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
  return viewModel;
}

AgentThreadSummary _thread({required String id, required String title}) {
  return AgentThreadSummary(
    id: id,
    providerId: defaultAgentProviderId,
    projectPath: '/repo',
    title: title,
    sessionPath: '/repo/$id.jsonl',
    preview: title,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    status: AgentThreadRuntimeStatus.idle,
  );
}

String _fileEditGroupId(String turnId, String toolCallId) {
  return 'file-edit-group-$turnId-$toolCallId';
}

Map<String, Object?> _patchApplyChanges(Map<String, String?> diffsByPath) {
  return <String, Object?>{
    'changes': <String, Object?>{
      for (final entry in diffsByPath.entries)
        entry.key: <String, Object?>{
          'type': 'update',
          if (entry.value != null) 'unified_diff': entry.value,
        },
    },
  };
}

String _largeUnifiedDiff() {
  return [
    '@@ -0,0 +1,32 @@',
    ...List<String>.generate(32, (index) => '+line ${index + 1}'),
  ].join('\n');
}

class _FakeAgentProviderFactory implements AgentProviderFactory {
  const _FakeAgentProviderFactory(this.provider);

  final _FakeAgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

class _FakeAgentProvider implements AgentProvider {
  _FakeAgentProvider({
    Map<String, AgentThreadHistorySnapshot> historySnapshotsByThread =
        const <String, AgentThreadHistorySnapshot>{},
  }) : _historySnapshotsByThread = Map<String, AgentThreadHistorySnapshot>.from(
         historySnapshotsByThread,
       );

  final Map<String, AgentThreadHistorySnapshot> _historySnapshotsByThread;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
    return const AgentSession(
      id: 'session-1',
      providerId: defaultAgentProviderId,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    return AgentSession(id: sessionId, providerId: defaultAgentProviderId);
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    return const AgentThreadPage(
      threads: <AgentThreadSummary>[],
      nextCursor: null,
    );
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    return const AgentModelList(models: <AgentModelInfo>[]);
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    return _historySnapshotsByThread[threadId] ??
        AgentThreadHistorySnapshot(
          threadId: threadId,
          turns: const <AgentHistoryTurn>[],
        );
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {}

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}
