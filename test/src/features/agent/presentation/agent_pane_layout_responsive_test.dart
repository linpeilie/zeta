import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';

import 'harness/agent_pane_test_harness.dart';

void main() {
  group('AgentPane layout responsive', () {
    testWidgets(
      'pins composer and shows agent icon loading while history loads',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final historyGate = Completer<void>();
        final provider = AgentPaneFakeProvider(
          historyLoadGate: historyGate.future,
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-loading': const AgentThreadHistorySnapshot(
              threadId: 'thread-loading',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-1',
                  entries: <AgentHistoryEntry>[
                    AgentHistoryMessageEntry(
                      id: 'user-1',
                      role: AgentMessageRole.user,
                      text: 'Loaded after gate',
                    ),
                  ],
                ),
              ],
            ),
          },
        );
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);

        // 未 await：停在 loadingHistory，便于断言加载 UI。
        final openFuture = viewModel.switchThread(
          agentPaneThread(id: 'thread-loading', title: 'Loading thread'),
        );
        // 加载态 pinFooter 应瞬时贴底（无需等动画）。
        await tester.pump();
        await tester.pump();

        expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.loadingHistory);
        expect(
          find.byKey(const ValueKey('agent-thread-history-loading')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('agent-thread-history-loading-label')),
          findsOneWidget,
        );
        expect(find.text('正在加载会话…'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('agent-thread-history-loading-spinner')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            ValueKey<String>(
              'agent-thread-history-loading-icon-$defaultAgentProviderId',
            ),
          ),
          findsOneWidget,
        );

        final layoutRect = tester.getRect(
          find.byKey(const ValueKey('agent-conversation-layout')),
        );
        final footerRect = tester.getRect(
          find.byKey(const ValueKey('agent-conversation-footer')),
        );
        // 加载态输入框贴底，而不是空草稿的垂直居中。
        expect(footerRect.bottom, closeTo(layoutRect.bottom, 1.0));
        expect(
          find.byKey(const ValueKey('agent-composer-section')),
          findsOneWidget,
        );

        historyGate.complete();
        await openFuture;
        await pumpAgentPaneUi(tester);

        expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.idle);
        expect(
          find.byKey(const ValueKey('agent-thread-history-loading')),
          findsNothing,
        );
        expect(find.text('Loaded after gate'), findsOneWidget);
      },
    );

    testWidgets('uses the canvas surface and one responsive content axis', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      final canvas = tester.widget<IdeSurface>(
        find.byKey(const ValueKey('agent-canvas')),
      );
      expect(canvas.level, IdeSurfaceLevel.canvas);
      final emptyLayoutRect = tester.getRect(
        find.byKey(const ValueKey('agent-conversation-layout')),
      );
      final emptyFooterRect = tester.getRect(
        find.byKey(const ValueKey('agent-conversation-footer')),
      );
      expect(
        emptyFooterRect.top,
        closeTo(
          emptyLayoutRect.top +
              ((emptyLayoutRect.height - emptyFooterRect.height) * 0.44),
          0.5,
        ),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('agent-composer-focus-ring')))
            .width,
        IdeMetrics.contentMaxWidth - IdeSpacing.pagePadding.horizontal,
      );

      await tester.binding.setSurfaceSize(const Size(600, 800));
      await pumpAgentPaneUi(tester);

      expect(
        tester
            .getSize(find.byKey(const ValueKey('agent-composer-focus-ring')))
            .width,
        600 - IdeSpacing.pagePaddingCompact.horizontal,
      );
    });

    testWidgets(
      'same width bucket resize keeps AgentPane controllers and draft',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);

        expect(
          find.byKey(const ValueKey('agent-pane-width-bucket')),
          findsOneWidget,
        );

        final input = find.byKey(const ValueKey('agent-message-input'));
        await tester.enterText(input, 'Bucket-stable draft');
        await tester.pump();

        final agentPaneElement = tester.element(find.byType(AgentPane));
        final inputController = tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .controller;
        final composerSectionElement = tester.element(
          find.byKey(const ValueKey('agent-composer-section')),
        );
        final conversationLayoutElement = tester.element(
          find.byKey(const ValueKey('agent-conversation-layout')),
        );
        final transientCallbacksBeforeResize =
            tester.binding.transientCallbackCount;

        // 900 → 700 均在 regular（>=640）档位内，不应卸载 Composer / 对话壳。
        for (var width = 900; width >= 700; width -= 5) {
          await tester.binding.setSurfaceSize(Size(width.toDouble(), 800));
          await tester.pump();
        }

        expect(tester.element(find.byType(AgentPane)), same(agentPaneElement));
        expect(
          tester.element(find.byKey(const ValueKey('agent-composer-section'))),
          same(composerSectionElement),
        );
        expect(
          tester.element(
            find.byKey(const ValueKey('agent-conversation-layout')),
          ),
          same(conversationLayoutElement),
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const ValueKey('agent-message-input')),
                  matching: find.byType(EditableText),
                ),
              )
              .controller,
          same(inputController),
        );
        expect(inputController.text, 'Bucket-stable draft');
        // 700 < contentMaxWidth，仍使用 regular pagePadding。
        expect(
          tester
              .getSize(find.byKey(const ValueKey('agent-composer-focus-ring')))
              .width,
          700 - IdeSpacing.pagePadding.horizontal,
        );
        expect(
          tester.binding.transientCallbackCount,
          lessThanOrEqualTo(transientCallbacksBeforeResize),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'crossing width breakpoint updates padding without losing controllers',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);

        final input = find.byKey(const ValueKey('agent-message-input'));
        await tester.enterText(input, 'Cross-breakpoint draft');
        await tester.pump();
        final inputController = tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .controller;
        final agentPaneElement = tester.element(find.byType(AgentPane));

        expect(
          tester
              .getSize(find.byKey(const ValueKey('agent-composer-focus-ring')))
              .width,
          800 - IdeSpacing.pagePadding.horizontal,
        );

        // 精确覆盖 641 / 640 / 639px；只有 639px 进入 compact。
        for (final width in <double>[641, 640]) {
          await tester.binding.setSurfaceSize(Size(width, 800));
          await pumpAgentPaneUi(tester);
          expect(
            tester.element(find.byType(AgentPane)),
            same(agentPaneElement),
          );
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: find.byKey(const ValueKey('agent-message-input')),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller,
            same(inputController),
          );
        }

        await tester.binding.setSurfaceSize(const Size(639, 800));
        await pumpAgentPaneUi(tester);

        expect(tester.element(find.byType(AgentPane)), same(agentPaneElement));
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const ValueKey('agent-message-input')),
                  matching: find.byType(EditableText),
                ),
              )
              .controller,
          same(inputController),
        );
        expect(inputController.text, 'Cross-breakpoint draft');
        expect(
          tester
              .getSize(find.byKey(const ValueKey('agent-composer-focus-ring')))
              .width,
          639 - IdeSpacing.pagePaddingCompact.horizontal,
        );

        for (final width in <double>[640, 641]) {
          await tester.binding.setSurfaceSize(Size(width, 800));
          await pumpAgentPaneUi(tester);
          expect(
            tester.element(find.byType(AgentPane)),
            same(agentPaneElement),
          );
          expect(inputController.text, 'Cross-breakpoint draft');
        }

        await tester.binding.setSurfaceSize(const Size(800, 800));
        await pumpAgentPaneUi(tester);

        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const ValueKey('agent-message-input')),
                  matching: find.byType(EditableText),
                ),
              )
              .controller,
          same(inputController),
        );
        expect(inputController.text, 'Cross-breakpoint draft');
        expect(
          tester
              .getSize(find.byKey(const ValueKey('agent-composer-focus-ring')))
              .width,
          800 - IdeSpacing.pagePadding.horizontal,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'moves the same focused composer below an active neutral user message',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final provider = AgentPaneFakeProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-design-system': AgentThreadHistorySnapshot(
              threadId: 'thread-design-system',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-design-system',
                  entries: const <AgentHistoryEntry>[
                    AgentHistoryMessageEntry(
                      id: 'history-user-design-system',
                      role: AgentMessageRole.user,
                      text: 'Keep the message surface neutral',
                    ),
                    AgentHistoryEventEntry(
                      id: 'history-system-design-system',
                      kind: AgentHistoryEventKind.system,
                      title: 'Session restored',
                    ),
                  ],
                ),
              ],
            ),
          },
        );
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await tester.enterText(
          find.byKey(const ValueKey('agent-message-input')),
          'Preserve this draft',
        );
        await tester.pump();
        final composerEditable = find.descendant(
          of: find.byKey(const ValueKey('agent-message-input')),
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(composerEditable).focusNode.hasFocus,
          isTrue,
        );

        await viewModel.switchThread(
          agentPaneThread(id: 'thread-design-system', title: 'Design system'),
        );
        await tester.pump();
        await tester.pump(IdeMotion.durationSlow);

        final activeLayoutRect = tester.getRect(
          find.byKey(const ValueKey('agent-conversation-layout')),
        );
        final activeFooterRect = tester.getRect(
          find.byKey(const ValueKey('agent-conversation-footer')),
        );
        expect(activeFooterRect.bottom, closeTo(activeLayoutRect.bottom, 0.5));
        final editableText = tester.widget<EditableText>(composerEditable);
        expect(editableText.controller.text, 'Preserve this draft');
        expect(editableText.focusNode.hasFocus, isTrue);

        final bubbleFinder = find.byKey(
          const ValueKey('agent-message-bubble-history-user-design-system'),
        );
        final bubble = tester.widget<DecoratedBox>(bubbleFinder);
        final decoration = bubble.decoration as BoxDecoration;
        final colors = IdeColors.of(tester.element(bubbleFinder));
        expect(decoration.color, colors.userMessageSurface);
        expect(decoration.border!.top.color, colors.borderSubtle);
        final historyEvent = find.byKey(
          const ValueKey('agent-history-event-history-system-design-system'),
        );
        final historyEventPanel = tester.widget<PanelCard>(
          find.descendant(of: historyEvent, matching: find.byType(PanelCard)),
        );
        expect(historyEventPanel.color, colors.controlSurface);
        expect(historyEventPanel.borderColor, colors.borderSubtle);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('agent-message-list')))
              .width,
          IdeMetrics.contentMaxWidth,
        );
      },
    );

    testWidgets(
      'lays out growing composer, timeline, and active plan in one frame',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(
          AgentPaneTestApp(viewModel: viewModel, disableAnimations: true),
        );
        await viewModel.sendMessage('Start layout verification');
        await tester.pump();

        final layout = find.byKey(const ValueKey('agent-conversation-layout'));
        final footer = find.byKey(const ValueKey('agent-conversation-footer'));
        final timeline = find.byKey(const ValueKey('agent-message-list'));
        final input = find.byKey(const ValueKey('agent-message-input'));
        expect(
          tester.getRect(footer).bottom,
          closeTo(tester.getRect(layout).bottom, 0.5),
        );

        await tester.enterText(input, 'line 1\nline 2\nline 3');
        await tester.pump();
        final threeLineFooter = tester.getRect(footer);
        expect(
          tester.getRect(timeline).bottom,
          closeTo(threeLineFooter.top, 0.5),
        );

        await tester.enterText(
          input,
          List<String>.generate(10, (index) => 'line ${index + 1}').join('\n'),
        );
        await tester.pump();
        final tenLineFooter = tester.getRect(footer);
        expect(tenLineFooter.height, greaterThan(threeLineFooter.height));
        expect(
          tester.getRect(timeline).bottom,
          closeTo(tenLineFooter.top, 0.5),
        );

        final stableCallbacks = tester.binding.transientCallbackCount;
        await tester.pump();
        expect(tester.getRect(footer), tenLineFooter);
        expect(tester.binding.transientCallbackCount, stableCallbacks);

        provider.emitEvent(
          const AgentPlanUpdatedEvent(
            entries: <AgentPlanEntry>[
              AgentPlanEntry(content: 'Inspect layout', status: 'completed'),
              AgentPlanEntry(content: 'Verify layout', status: 'inProgress'),
            ],
            sessionId: 'session-1',
            turnId: 'turn-1',
          ),
        );
        await tester.pump();

        final activePlan = find.byKey(
          const ValueKey<String>('agent-active-plan-card-turn-1'),
        );
        expect(activePlan, findsOneWidget);
        expect(
          tester.getRect(activePlan).bottom,
          lessThanOrEqualTo(tester.getRect(footer).top + 0.5),
        );

        provider.emitEvent(
          const AgentTurnCompletedEvent(
            sessionId: 'session-1',
            turnId: 'turn-1',
          ),
        );
        await tester.pump();
      },
    );

    testWidgets('shows a rotating composer glow only while a turn is running', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      const glowKey = ValueKey('agent-composer-running-glow');
      final glowFinder = find.byKey(glowKey);
      expect(glowFinder, findsNothing);

      await viewModel.sendMessage('Keep working');
      await tester.pump();

      expect(glowFinder, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('agent-composer-running-glow-repaint-boundary'),
        ),
        findsOneWidget,
      );
      final animationBuilder = find.byKey(
        const ValueKey('agent-composer-running-glow-animation'),
      );
      final controller =
          tester.widget<AnimatedBuilder>(animationBuilder).animation
              as AnimationController;
      final initialProgress = controller.value;
      await tester.pump(IdeMotion.durationRunningGlow * 0.25);
      expect(controller.value, isNot(closeTo(initialProgress, 0.001)));

      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();

      expect(glowFinder, findsNothing);
      expect(controller.isAnimating, isFalse);
      expect(controller.value, 0);
    });

    testWidgets('disables layout and composer motion for reduce motion', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        AgentPaneTestApp(viewModel: viewModel, disableAnimations: true),
      );
      await tester.pump();

      final conversationLayout = find.byKey(
        const ValueKey('agent-conversation-layout'),
      );
      final conversationFooter = find.byKey(
        const ValueKey('agent-conversation-footer'),
      );
      final emptyLayoutRect = tester.getRect(conversationLayout);
      final emptyFooterRect = tester.getRect(conversationFooter);
      expect(
        emptyFooterRect.top,
        closeTo(
          emptyLayoutRect.top +
              ((emptyLayoutRect.height - emptyFooterRect.height) * 0.44),
          0.5,
        ),
      );
      expect(
        tester
            .widget<AnimatedContainer>(
              find.byKey(const ValueKey('agent-composer-focus-ring')),
            )
            .duration,
        Duration.zero,
      );

      await viewModel.sendMessage('Keep working');
      await tester.pump();

      expect(
        tester.getRect(conversationFooter).bottom,
        closeTo(tester.getRect(conversationLayout).bottom, 0.5),
      );
      final glowFinder = find.byKey(
        const ValueKey('agent-composer-running-glow'),
      );
      expect(glowFinder, findsOneWidget);
      final animationBuilder = find.byKey(
        const ValueKey('agent-composer-running-glow-animation'),
      );
      final controller =
          tester.widget<AnimatedBuilder>(animationBuilder).animation
              as AnimationController;
      final staticProgress = controller.value;
      expect(controller.isAnimating, isFalse);

      await tester.pump(IdeMotion.durationRunningGlow);

      expect(controller.value, staticProgress);
      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();
    });
  });
}
