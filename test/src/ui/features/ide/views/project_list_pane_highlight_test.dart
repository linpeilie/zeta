import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/features/ide/views/project_list_pane.dart';

import '../../../core/ide_component_test_harness.dart';
import '../../../../testing/ide_test_harness.dart';

void main() {
  testWidgets('会话高亮只认 highlightedThreadId，不回退 slice selectedThreadId', (
    tester,
  ) async {
    const projectPath = '/repo';
    final threadA = agentThread(
      id: 'thread-a',
      projectPath: projectPath,
      title: 'A',
    );
    final threadB = agentThread(
      id: 'thread-b',
      projectPath: projectPath,
      title: 'B',
    );

    await pumpIdeComponent(
      tester,
      child: ProjectListPane(
        projects: const <String>[projectPath],
        activeProject: projectPath,
        highlightedThreadId: 'thread-b',
        threadStateFor: (_) => ProjectThreadListState(
          isExpanded: true,
          hasLoaded: true,
          threads: <AgentThreadSummary>[threadA, threadB],
          selectedThreadId: 'thread-a',
        ),
        onSelectProject: (_) {},
        onSelectThread: (_, _) {},
        onLoadMoreThreads: (_) {},
        onRetryThreads: (_) {},
        loadAvailableProviders: () async => const <AgentProviderConfig>[],
        capabilitiesForProvider: (_) => const AgentProviderCapabilities(),
        onNewThread: (_, _) {},
        onOpenProjectLocation: (_) {},
        onRemoveProject: (_) {},
        onRenameThread: (_, _, _) {},
        onArchiveThread: (_, _) {},
        onUnarchiveThread: (_, _) {},
        onDeleteThread: (_, _) {},
        onForkThread: (_, _) {},
        onDismissCompletedThread: (_, _) {},
      ),
    );

    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PaneInteractiveSurface>(
            find.byKey(const ValueKey<String>('project-thread-/repo-thread-a')),
          )
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<PaneInteractiveSurface>(
            find.byKey(const ValueKey<String>('project-thread-/repo-thread-b')),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('没有路由 threadId 时即使 slice 仍有 selectedThreadId 也不高亮', (
    tester,
  ) async {
    const projectPath = '/repo';
    final thread = agentThread(
      id: 'thread-a',
      projectPath: projectPath,
      title: 'A',
    );

    await pumpIdeComponent(
      tester,
      child: ProjectListPane(
        projects: const <String>[projectPath],
        activeProject: projectPath,
        threadStateFor: (_) => ProjectThreadListState(
          isExpanded: true,
          hasLoaded: true,
          threads: <AgentThreadSummary>[thread],
          selectedThreadId: 'thread-a',
        ),
        onSelectProject: (_) {},
        onSelectThread: (_, _) {},
        onLoadMoreThreads: (_) {},
        onRetryThreads: (_) {},
        loadAvailableProviders: () async => const <AgentProviderConfig>[],
        capabilitiesForProvider: (_) => const AgentProviderCapabilities(),
        onNewThread: (_, _) {},
        onOpenProjectLocation: (_) {},
        onRemoveProject: (_) {},
        onRenameThread: (_, _, _) {},
        onArchiveThread: (_, _) {},
        onUnarchiveThread: (_, _) {},
        onDeleteThread: (_, _) {},
        onForkThread: (_, _) {},
        onDismissCompletedThread: (_, _) {},
      ),
    );

    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PaneInteractiveSurface>(
            find.byKey(const ValueKey<String>('project-thread-/repo-thread-a')),
          )
          .selected,
      isFalse,
    );
  });
}
