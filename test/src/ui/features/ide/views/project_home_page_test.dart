import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/features/ide/views/project_home_page.dart';

import '../../../core/ide_component_test_harness.dart';

void main() {
  testWidgets('shows project metadata and at most five recent threads', (
    tester,
  ) async {
    final threads = <AgentThreadSummary>[
      for (var index = 0; index < 6; index += 1)
        _thread(index: index, providerId: defaultAgentProviderId),
    ];
    AgentThreadSummary? selectedThread;

    await pumpIdeComponent(
      tester,
      size: const Size(520, 720),
      child: ProjectHomePage(
        projectPath: r'C:\workspace\zeta',
        threadState: ProjectThreadListState(hasLoaded: true, threads: threads),
        loadAvailableProviders: () async => const <AgentProviderConfig>[],
        onNewThread: (_) {},
        onSelectThread: (thread) {
          selectedThread = thread;
        },
        onRetryThreads: () {},
      ),
    );

    expect(find.text('zeta'), findsOneWidget);
    expect(find.text(r'C:\workspace\zeta'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
    expect(find.text('近期会话'), findsOneWidget);
    for (var index = 0; index < 5; index += 1) {
      expect(
        find.byKey(ValueKey<String>('project-home-thread-thread-$index')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('project-home-thread-thread-5')),
      findsNothing,
    );
    final firstThread = find.byKey(
      const ValueKey<String>('project-home-thread-thread-0'),
    );
    expect(
      find.descendant(
        of: firstThread,
        matching: find.byKey(
          const ValueKey<String>('agent-provider-icon-svg-codex'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstThread, matching: find.text('Codex')),
      findsNothing,
    );

    final threadSurface = find.descendant(
      of: firstThread,
      matching: find.byType(PaneInteractiveSurface),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(firstThread));
    await tester.pumpAndSettle();

    final hoverDecoration =
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: threadSurface,
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(hoverDecoration.borderRadius, IdeRadius.allSmall);
    expect(
      hoverDecoration.color,
      IdeColors.of(tester.element(threadSurface)).hoverSurface,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('project-home-thread-thread-0')),
    );
    await tester.pump();

    expect(selectedThread?.id, 'thread-0');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'centers the flat module and keeps the new thread action at the header end',
    (tester) async {
      await pumpIdeComponent(
        tester,
        size: const Size(900, 900),
        child: ProjectHomePage(
          projectPath: '/workspace/zeta',
          threadState: ProjectThreadListState(
            hasLoaded: true,
            threads: <AgentThreadSummary>[
              _thread(index: 0, providerId: defaultAgentProviderId),
            ],
          ),
          loadAvailableProviders: () async => const <AgentProviderConfig>[],
          onNewThread: (_) {},
          onSelectThread: (_) {},
          onRetryThreads: () {},
        ),
      );

      final pageCenter = tester.getCenter(find.byType(ProjectHomePage));
      final contentCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('project-home-centered-content')),
      );
      expect(contentCenter.dx, closeTo(pageCenter.dx, 0.5));
      expect(contentCenter.dy, closeTo(pageCenter.dy, 0.5));

      final contentLeft = tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('project-home-centered-content')),
          )
          .dx;
      final contentRight = tester
          .getTopRight(
            find.byKey(const ValueKey<String>('project-home-centered-content')),
          )
          .dx;
      for (final key in <String>[
        'project-home-name',
        'project-home-path',
        'project-home-recent-title',
      ]) {
        expect(
          tester.getTopLeft(find.byKey(ValueKey<String>(key))).dx,
          closeTo(contentLeft, 0.5),
        );
      }
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('project-home-name')),
            )
            .textAlign,
        TextAlign.start,
      );
      expect(
        tester.widget<Text>(find.text('Thread 0')).textAlign,
        TextAlign.start,
      );

      final nameRect = tester.getRect(
        find.byKey(const ValueKey<String>('project-home-name')),
      );
      final pathRect = tester.getRect(
        find.byKey(const ValueKey<String>('project-home-path')),
      );
      final newThreadButtonRect = tester.getRect(
        find.byKey(const ValueKey<String>('project-home-new-thread-button')),
      );
      expect(newThreadButtonRect.right, closeTo(contentRight, 0.5));
      expect(newThreadButtonRect.bottom, greaterThan(nameRect.top));
      expect(newThreadButtonRect.top, lessThan(pathRect.bottom));
      expect(
        find.descendant(
          of: find.byType(ProjectHomePage),
          matching: find.byType(PanelCard),
        ),
        findsNothing,
      );

      final interactiveSurfaces = tester.widgetList<PaneInteractiveSurface>(
        find.descendant(
          of: find.byType(ProjectHomePage),
          matching: find.byType(PaneInteractiveSurface),
        ),
      );
      expect(interactiveSurfaces, isNotEmpty);
      expect(
        interactiveSurfaces.every(
          (surface) => surface.borderRadius == IdeRadius.allSmall,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provider selection opens a draft entry callback', (
    tester,
  ) async {
    String? selectedProviderId;

    await pumpIdeComponent(
      tester,
      child: ProjectHomePage(
        projectPath: '/workspace/zeta',
        threadState: const ProjectThreadListState(hasLoaded: true),
        loadAvailableProviders: () async => const <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex,
        ],
        onNewThread: (providerId) {
          selectedProviderId = providerId;
        },
        onSelectThread: (_) {},
        onRetryThreads: () {},
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('project-home-new-thread-button')),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('new-thread-provider-popover')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('new-thread-provider-option-codex')),
    );
    await tester.pump();
    await tester.tap(find.text('创建 Thread'));
    await tester.pumpAndSettle();

    expect(selectedProviderId, defaultAgentProviderId);
  });

  testWidgets('shows loading, error and retry states without overflow', (
    tester,
  ) async {
    var retried = false;
    var state = const ProjectThreadListState(isLoadingInitial: true);

    Future<void> pumpState() {
      return pumpIdeComponent(
        tester,
        size: const Size(360, 520),
        child: ProjectHomePage(
          projectPath: '/workspace/a-very-long-project-name',
          threadState: state,
          loadAvailableProviders: () async => const <AgentProviderConfig>[],
          onNewThread: (_) {},
          onSelectThread: (_) {},
          onRetryThreads: () {
            retried = true;
          },
        ),
      );
    }

    await pumpState();
    expect(
      find.byKey(const ValueKey<String>('project-home-loading-state')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    state = const ProjectThreadListState(
      hasLoaded: true,
      errorMessage: 'network unavailable',
    );
    await pumpState();
    expect(
      find.byKey(const ValueKey<String>('project-home-error-state')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('project-home-retry-button')),
    );
    await tester.pump();
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });
}

AgentThreadSummary _thread({required int index, required String providerId}) {
  final activeAt = DateTime.utc(2026, 7, 21).subtract(Duration(hours: index));
  return AgentThreadSummary(
    id: 'thread-$index',
    providerId: providerId,
    projectPath: '/workspace/zeta',
    title: 'Thread $index',
    preview: 'Preview $index',
    createdAt: activeAt.subtract(const Duration(hours: 1)),
    updatedAt: activeAt,
    recencyAt: activeAt,
    status: AgentThreadRuntimeStatus.idle,
  );
}
