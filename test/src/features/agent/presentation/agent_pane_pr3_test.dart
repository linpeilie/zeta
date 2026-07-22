import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';

import '../../../testing/agent_provider_stub_base.dart';

void main() {
  group('AgentPane PR3', () {
    testWidgets('uses the canvas surface and one responsive content axis', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(_TestApp(viewModel: viewModel));
      await _pumpAgentPaneUi(tester);

      final canvas = tester.widget<IdeSurface>(
        find.byKey(const ValueKey('agent-canvas')),
      );
      expect(canvas.level, IdeSurfaceLevel.canvas);
      final emptyAlignment = tester.widget<AnimatedAlign>(
        find.byKey(const ValueKey('agent-composer-alignment')),
      );
      expect(emptyAlignment.alignment, const Alignment(0, -0.12));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('agent-composer-focus-ring')))
            .width,
        IdeMetrics.contentMaxWidth - IdeSpacing.pagePadding.horizontal,
      );

      await tester.binding.setSurfaceSize(const Size(600, 800));
      await _pumpAgentPaneUi(tester);

      expect(
        tester
            .getSize(find.byKey(const ValueKey('agent-composer-focus-ring')))
            .width,
        600 - IdeSpacing.pagePaddingCompact.horizontal,
      );
    });

    testWidgets(
      'moves the same focused composer below an active neutral user message',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final provider = _FakeAgentProvider(
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
        final viewModel = _createViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(_TestApp(viewModel: viewModel));
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
          _thread(id: 'thread-design-system', title: 'Design system'),
        );
        await tester.pump();
        await tester.pump(IdeMotion.durationSlow);

        final activeAlignment = tester.widget<AnimatedAlign>(
          find.byKey(const ValueKey('agent-composer-alignment')),
        );
        expect(activeAlignment.alignment, Alignment.bottomCenter);
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

    testWidgets('shows a rotating composer glow only while a turn is running', (
      tester,
    ) async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(_TestApp(viewModel: viewModel));
      const glowKey = ValueKey('agent-composer-running-glow');
      final glowFinder = find.byKey(glowKey);
      expect(glowFinder, findsNothing);

      await viewModel.sendMessage('Keep working');
      await tester.pump();

      expect(glowFinder, findsOneWidget);
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
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        _TestApp(viewModel: viewModel, disableAnimations: true),
      );
      await tester.pump();

      expect(
        tester
            .widget<AnimatedAlign>(
              find.byKey(const ValueKey('agent-composer-alignment')),
            )
            .duration,
        Duration.zero,
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

    group('advanced', () {
      testWidgets(
        'renders heavy history markdown fully without collapse toggle',
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
          await _pumpAgentPaneUi(tester);

          // 历史长文不再折叠：无预览/展开按钮，正文完整可见。
          expect(
            find.byKey(
              const ValueKey<String>(
                'agent-markdown-preview-history-markdown-1',
              ),
            ),
            findsNothing,
          );
          expect(
            find.byKey(
              const ValueKey<String>(
                'agent-markdown-toggle-history-markdown-1',
              ),
            ),
            findsNothing,
          );
          expect(
            find.textContaining('Markdown line 16', findRichText: true),
            findsOneWidget,
          );
          expect(find.text('展开正文'), findsNothing);
        },
      );

      testWidgets('restores a historical Grok failure reason and footer', (
        tester,
      ) async {
        const errorMessage = 'Grok rate limit reached. Please try again later.';
        await tester.binding.setSurfaceSize(const Size(800, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final viewModel = _createViewModel(
          _FakeAgentProvider(
            historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
              'thread-grok-failed': const AgentThreadHistorySnapshot(
                threadId: 'thread-grok-failed',
                turns: <AgentHistoryTurn>[
                  AgentHistoryTurn(
                    id: 'turn-grok-failed',
                    status: AgentHistoryTurnStatus.failed,
                    duration: Duration(seconds: 9),
                    model: 'grok-4.5',
                    errorMessage: errorMessage,
                    entries: <AgentHistoryEntry>[
                      AgentHistoryMessageEntry(
                        id: 'history-user-grok-failed',
                        role: AgentMessageRole.user,
                        text: 'Trigger rate limit',
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
          _thread(id: 'thread-grok-failed', title: 'Failed Grok turn'),
        );
        await _pumpAgentPaneUi(tester);

        expect(find.text(errorMessage), findsOneWidget);
        final footer = find.byKey(
          const ValueKey<String>('agent-turn-footer-turn-grok-failed'),
        );
        expect(footer, findsOneWidget);
        expect(
          find.descendant(of: footer, matching: find.text('失败 · 9s')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: footer, matching: find.text('grok-4.5')),
          findsOneWidget,
        );
      });

      testWidgets('renders end-of-turn footer with duration and token usage', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(800, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final viewModel = _createViewModel(
          _FakeAgentProvider(
            historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
              'thread-footer': AgentThreadHistorySnapshot(
                threadId: 'thread-footer',
                turns: <AgentHistoryTurn>[
                  AgentHistoryTurn(
                    id: 'turn-footer-1',
                    status: AgentHistoryTurnStatus.completed,
                    duration: const Duration(seconds: 95),
                    model: 'gpt-5.5',
                    tokenUsage: const AgentTokenUsage(
                      inputTokens: 1000,
                      outputTokens: 240,
                      totalTokens: 1240,
                    ),
                    raw: const <String, Object?>{
                      'turnContext': <String, Object?>{
                        'model': 'gpt-5.5',
                        'effort': 'high',
                        'serviceTier': 'priority',
                      },
                    },
                    entries: const <AgentHistoryEntry>[
                      AgentHistoryMessageEntry(
                        id: 'history-user-footer-1',
                        role: AgentMessageRole.user,
                        text: 'Do the work',
                      ),
                      AgentHistoryMessageEntry(
                        id: 'history-agent-footer-1',
                        role: AgentMessageRole.agent,
                        text: 'Done.',
                        phase: AgentMessagePhase.response,
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
          _thread(id: 'thread-footer', title: 'Footer turn'),
        );
        await _pumpAgentPaneUi(tester);

        final footer = find.byKey(
          const ValueKey<String>('agent-turn-footer-turn-footer-1'),
        );
        expect(footer, findsOneWidget);
        expect(
          find.descendant(of: footer, matching: find.text('1m 35s')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: footer, matching: find.text('gpt-5.5')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: footer, matching: find.text('高')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: footer, matching: find.text('Fast')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: footer, matching: find.text('1.2k tokens')),
          findsOneWidget,
        );
        // 宽布局给元数据留出足够空间，各项以带留白的 • 分隔。
        expect(
          find.descendant(
            of: footer,
            matching: find.byKey(
              const ValueKey<String>('agent-turn-footer-inline-turn-footer-1'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: footer, matching: find.text('•')),
          findsNWidgets(4),
        );
        final firstSeparator = tester.widget<Padding>(
          find.byKey(
            const ValueKey<String>(
              'agent-turn-footer-separator-turn-footer-1-0',
            ),
          ),
        );
        expect(
          firstSeparator.padding,
          const EdgeInsets.symmetric(horizontal: IdeSpacing.space8),
        );
        expect(
          find.descendant(
            of: footer,
            matching: find.byIcon(Icons.bolt_outlined),
          ),
          findsNothing,
        );

        await tester.binding.setSurfaceSize(const Size(480, 800));
        await _pumpAgentPaneUi(tester);

        expect(
          find.byKey(
            const ValueKey<String>('agent-turn-footer-stacked-turn-footer-1'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'expands history plan card through view model state without bumping history version',
        (tester) async {
          final viewModel = _createViewModel(
            _FakeAgentProvider(
              historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
                'thread-plan': AgentThreadHistorySnapshot(
                  threadId: 'thread-plan',
                  turns: <AgentHistoryTurn>[
                    AgentHistoryTurn(
                      id: 'turn-plan-1',
                      entries: <AgentHistoryEntry>[
                        const AgentHistoryMessageEntry(
                          id: 'history-user-plan-1',
                          role: AgentMessageRole.user,
                          text: 'Show the plan',
                        ),
                        AgentHistoryMessageEntry(
                          id: 'history-plan-1',
                          role: AgentMessageRole.agent,
                          text: '- [x] Inspect timeline\n- [ ] Split cards',
                          kind: AgentMessageKind.plan,
                          raw: const <String, Object?>{'type': 'plan'},
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
            _thread(id: 'thread-plan', title: 'Plan card'),
          );
          await _pumpAgentPaneUi(tester);

          expect(viewModel.isPlanMessageExpanded('history-plan-1'), isFalse);
          expect(
            find.byKey(
              const ValueKey<String>('agent-plan-preview-history-plan-1'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(
              const ValueKey<String>('agent-plan-body-history-plan-1'),
            ),
            findsNothing,
          );

          final historyVersion = viewModel.historyVersion;
          await tester.tap(
            find.byKey(
              const ValueKey<String>('agent-plan-toggle-history-plan-1'),
            ),
          );
          await _pumpAgentPaneUi(tester);

          expect(viewModel.historyVersion, historyVersion);
          expect(viewModel.isPlanMessageExpanded('history-plan-1'), isTrue);
          expect(
            find.byKey(
              const ValueKey<String>('agent-plan-body-history-plan-1'),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'renders live agent markdown through a streaming controller and commits the final update',
        (tester) async {
          final provider = _FakeAgentProvider();
          final viewModel = _createViewModel(provider);
          addTearDown(provider.dispose);
          addTearDown(viewModel.dispose);

          await tester.pumpWidget(_TestApp(viewModel: viewModel));
          await viewModel.sendMessage('Stream markdown');
          await _pumpLiveAgentUi(tester);

          provider.emitEvent(
            const AgentMessageDeltaEvent(
              messageId: 'message-1',
              delta: '# Title\n\nDraft paragraph\n\n```dart\nfinal ',
              role: AgentMessageRole.agent,
              phase: AgentMessagePhase.response,
              status: AgentMessageStatus.streaming,
              sessionId: 'session-1',
              turnId: 'turn-1',
            ),
          );
          await _pumpLiveAgentUi(tester);

          final liveSectionFinder = find.byKey(
            const ValueKey<String>('agent-live-turn-section'),
          );
          final liveMarkdownWidget = _markdownWidgetUnder(
            tester,
            liveSectionFinder,
          );
          _expectMarkdownWidgetDefaults(liveMarkdownWidget);
          expect(liveMarkdownWidget.data, isNull);
          final controller = liveMarkdownWidget.controller;
          expect(controller, isNotNull);
          expect(
            controller!.data,
            '# Title\n\nDraft paragraph\n\n```dart\nfinal ',
          );
          expect(controller.streamingState.hasDraft, isTrue);
          expect(
            find.textContaining('Draft paragraph', findRichText: true),
            findsOneWidget,
          );

          provider.emitEvent(
            const AgentMessageDeltaEvent(
              messageId: 'message-1',
              delta: 'answer = true;',
              role: AgentMessageRole.agent,
              phase: AgentMessagePhase.response,
              status: AgentMessageStatus.streaming,
              sessionId: 'session-1',
              turnId: 'turn-1',
            ),
          );
          await _pumpLiveAgentUi(tester);

          final updatedMarkdownWidget = _markdownWidgetUnder(
            tester,
            liveSectionFinder,
          );
          expect(
            identical(updatedMarkdownWidget.controller, controller),
            isTrue,
          );
          expect(
            controller.data,
            '# Title\n\nDraft paragraph\n\n```dart\nfinal answer = true;',
          );

          provider.emitEvent(
            const AgentMessageUpdatedEvent(
              messageId: 'message-1',
              text:
                  '# Title\n\nDraft paragraph\n\n```dart\nfinal answer = true;\n```',
              role: AgentMessageRole.agent,
              phase: AgentMessagePhase.response,
              status: AgentMessageStatus.completed,
              sessionId: 'session-1',
              turnId: 'turn-1',
            ),
          );
          await _pumpLiveAgentUi(tester);

          final completedMarkdownWidget = _markdownWidgetUnder(
            tester,
            liveSectionFinder,
          );
          expect(
            identical(completedMarkdownWidget.controller, controller),
            isTrue,
          );
          expect(
            controller.data,
            '# Title\n\nDraft paragraph\n\n```dart\nfinal answer = true;\n```',
          );
          expect(controller.streamingState.hasDraft, isFalse);
          expect(
            find.textContaining('answer', findRichText: true),
            findsOneWidget,
          );

          // 收尾 turn，避免 elapsed ticker 在测试销毁后仍保留周期定时器。
          provider.emitEvent(
            const AgentTurnCompletedEvent(
              sessionId: 'session-1',
              turnId: 'turn-1',
            ),
          );
          await tester.pump();
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
          await _pumpAgentPaneUi(tester);

          final historyVersion = viewModel.historyVersion;
          await tester.tap(
            find.byKey(
              ValueKey<String>(
                'agent-file-edit-group-header-${_fileEditGroupId('turn-diff-1', 'history-edit-large')}',
              ),
            ),
          );
          await _pumpAgentPaneUi(tester);

          expect(viewModel.historyVersion, historyVersion);

          await tester.tap(
            find.byKey(
              const ValueKey<String>(
                'agent-file-edit-item-row-file-edit-history-edit-large-lib/main.dart',
              ),
            ),
          );
          await _pumpAgentPaneUi(tester);

          expect(viewModel.historyVersion, historyVersion);
          expect(
            viewModel.isFileEditItemExpanded(
              _fileEditItemId('history-edit-large', 'lib/main.dart'),
            ),
            isTrue,
          );
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
          final expandAllButton = tester.widget<sf.GhostButton>(
            expandAllFinder,
          );
          expandAllButton.onPressed?.call();
          await _pumpAgentPaneUi(tester);

          expect(viewModel.historyVersion, historyVersion);
          expect(
            find.textContaining('+line 30', findRichText: true),
            findsOneWidget,
          );
        },
      );

      testWidgets('uses ui font for正文 and code font for code-like content', (
        tester,
      ) async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-fonts': AgentThreadHistorySnapshot(
              threadId: 'thread-fonts',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-fonts-1',
                  status: AgentHistoryTurnStatus.running,
                  entries: <AgentHistoryEntry>[
                    const AgentHistoryMessageEntry(
                      id: 'history-user-fonts-1',
                      role: AgentMessageRole.user,
                      text: 'Check fonts',
                    ),
                    const AgentHistoryMessageEntry(
                      id: 'history-markdown-fonts-1',
                      role: AgentMessageRole.agent,
                      text:
                          'Paragraph text for font check.\n\n```dart\nconst answer = 42;\n```',
                    ),
                    const AgentHistoryEventEntry(
                      id: 'history-event-fonts-1',
                      kind: AgentHistoryEventKind.system,
                      title: 'Search query',
                      content: 'site:zeta.dev fonts',
                    ),
                  ],
                ),
              ],
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(
          _TestApp(
            viewModel: viewModel,
            uiFontFamily: 'UiFont',
            codeFontFamily: 'CodeFont',
          ),
        );
        await viewModel.switchThread(
          _thread(id: 'thread-fonts', title: 'Font thread'),
        );
        await _pumpLiveAgentUi(tester);

        final markdownParagraphFinder = find.textContaining(
          'Paragraph text for font check.',
          findRichText: true,
        );
        expect(markdownParagraphFinder, findsOneWidget);
        expect(
          _fontFamilyForRenderedText(
            tester,
            markdownParagraphFinder,
            'Paragraph text for font check.',
          ),
          'UiFont',
        );

        final markdownCodeFinder = find.textContaining(
          'answer',
          findRichText: true,
        );
        expect(markdownCodeFinder, findsOneWidget);
        expect(
          _fontFamilyForRenderedText(tester, markdownCodeFinder, 'answer'),
          'CodeFont',
        );

        provider.emitEvent(
          const AgentPermissionRequestedEvent(
            AgentPermissionRequest(
              id: 'permission-fonts-1',
              title: 'Run command',
              kind: AgentPermissionKind.commandExecution,
              command: 'tool output line',
            ),
          ),
        );
        await _pumpLiveAgentUi(tester);

        final permissionCommandFinder = find.text('tool output line');
        expect(permissionCommandFinder, findsOneWidget);
        expect(
          tester.widget<Text>(permissionCommandFinder).style?.fontFamily,
          'CodeFont',
        );

        final historyEventContentFinder = find.text('site:zeta.dev fonts');
        expect(historyEventContentFinder, findsOneWidget);
        expect(
          tester.widget<Text>(historyEventContentFinder).style?.fontFamily,
          'CodeFont',
        );

        provider.emitEvent(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-fonts',
            turnId: 'turn-fonts-1',
          ),
        );
        await tester.pump();
      });

      testWidgets('model config expands inline and keeps popover open', (
        tester,
      ) async {
        final provider = _FakeAgentProvider(models: _modelConfigList);
        final viewModel = _createViewModel(provider);
        await viewModel.loadModels();
        await tester.pumpWidget(_TestApp(viewModel: viewModel));
        await _pumpAgentPaneUi(tester);

        expect(
          find.byKey(const ValueKey('agent-model-selector')),
          findsOneWidget,
        );
        final modelSelector = find.byKey(
          const ValueKey('agent-model-selector'),
        );
        final selectorSurface = tester.widget<PaneInteractiveSurface>(
          modelSelector,
        );
        expect(tester.getSize(modelSelector).width, lessThan(180));
        expect(tester.getSize(modelSelector).height, 28);
        expect(selectorSurface.backgroundColor, Colors.transparent);
        expect(selectorSurface.borderColor, isNull);
        expect(selectorSurface.borderRadius, IdeRadius.allSmall);
        expect(find.text('GPT-5.5'), findsOneWidget);
        final closedTriggerTooltip = find.ancestor(
          of: modelSelector,
          matching: find.byType(IdeTooltip),
        );
        expect(
          tester.widget<IdeTooltip>(closedTriggerTooltip).message,
          contains('Fast：已关闭'),
        );

        await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final popover = find.byKey(
          const ValueKey('agent-model-config-popover'),
        );
        expect(tester.getSize(popover).width, 288);
        expect(tester.getSize(popover).height, lessThan(160));
        final popoverPanel = find.descendant(
          of: popover,
          matching: find.byType(PanelCard),
        );
        final modelPopoverPanel = tester.widget<PanelCard>(popoverPanel.first);
        final colors = IdeColors.of(tester.element(modelSelector));
        expect(modelPopoverPanel.color, colors.panel);
        expect(modelPopoverPanel.borderRadius, IdeRadius.allSmall);
        expect(modelPopoverPanel.boxShadow, isEmpty);
        final selectedModelSurface = tester.widget<PaneInteractiveSurface>(
          find.byKey(const ValueKey('agent-model-option-gpt-5.5')),
        );
        expect(selectedModelSurface.height, 32);
        expect(selectedModelSurface.borderRadius, IdeRadius.allSmall);
        expect(selectedModelSurface.selected, isTrue);
        expect(
          selectedModelSurface.selectedBackgroundColor?.a,
          closeTo(0.2, 0.001),
        );
        expect(selectedModelSurface.focusBorderColor, colors.focusRing);
        final openTriggerTooltip = find.ancestor(
          of: modelSelector,
          matching: find.byType(IdeTooltip),
        );
        expect(tester.widget<IdeTooltip>(openTriggerTooltip).enabled, isFalse);

        expect(
          find.byKey(const ValueKey('agent-model-option-gpt-5.4-mini')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('agent-model-inline-config-gpt-5.5')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('agent-reasoning-segment-control')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('agent-model-option-gpt-5.4-mini')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(viewModel.selectedModelId, 'gpt-5.4-mini');
        expect(
          find.byKey(const ValueKey('agent-model-option-gpt-5.4-mini')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('agent-model-inline-config-gpt-5.4-mini')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('agent-reasoning-segment-control')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('agent-reasoning-option-high')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(viewModel.selectedReasoningEffort, 'high');
        expect(
          find.byKey(const ValueKey('agent-model-config-popover')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('agent-fast-switch-gpt-5.4-mini')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(viewModel.selectedServiceTierId, 'priority');
        expect(
          find.byKey(const ValueKey('agent-model-fast-enabled')),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey('agent-model-config-popover')),
          findsNothing,
        );
        final tooltipAfterEscape = find.ancestor(
          of: modelSelector,
          matching: find.byType(IdeTooltip),
        );
        expect(tester.widget<IdeTooltip>(tooltipAfterEscape).enabled, isTrue);

        await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(viewModel.selectedModelId, 'gpt-5.4-mini');
        expect(
          find.byKey(const ValueKey('agent-model-config-popover')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('agent-model-inline-config-gpt-5.4-mini')),
          findsNothing,
        );
      });

      testWidgets(
        'permission policy matches model selector style and updates selection',
        (tester) async {
          final provider = _FakeAgentProvider(models: _modelConfigList);
          final viewModel = _createViewModel(provider);
          addTearDown(provider.dispose);
          addTearDown(viewModel.dispose);
          await viewModel.loadModels();
          await tester.pumpWidget(_TestApp(viewModel: viewModel));
          await _pumpAgentPaneUi(tester);

          final modelSelector = find.byKey(
            const ValueKey('agent-model-selector'),
          );
          final permissionSelector = find.byKey(
            const ValueKey('agent-permission-policy-selector'),
          );
          final modelSurface = tester.widget<PaneInteractiveSurface>(
            modelSelector,
          );
          final permissionSurface = tester.widget<PaneInteractiveSurface>(
            permissionSelector,
          );
          expect(permissionSurface.height, modelSurface.height);
          expect(permissionSurface.borderRadius, modelSurface.borderRadius);
          expect(
            permissionSurface.backgroundColor,
            modelSurface.backgroundColor,
          );
          expect(permissionSurface.borderColor, modelSurface.borderColor);
          expect(find.text('Workspace write · Ask first'), findsOneWidget);

          await tester.tap(permissionSelector);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          final popover = find.byKey(
            const ValueKey('agent-permission-policy-popover'),
          );
          expect(popover, findsOneWidget);
          expect(tester.getSize(popover).width, 288);
          expect(find.text('审批与沙箱'), findsOneWidget);
          final popoverPanel = find.descendant(
            of: popover,
            matching: find.byType(PanelCard),
          );
          final permissionPopoverPanel = tester.widget<PanelCard>(popoverPanel);
          final colors = IdeColors.of(tester.element(permissionSelector));
          expect(permissionPopoverPanel.color, colors.panel);
          expect(permissionPopoverPanel.borderRadius, IdeRadius.allSmall);
          expect(permissionPopoverPanel.boxShadow, isEmpty);
          final selectedOption = tester.widget<PaneInteractiveSurface>(
            find.byKey(const ValueKey('agent-permission-preset-workspace')),
          );
          expect(selectedOption.height, 32);
          expect(selectedOption.borderRadius, IdeRadius.allSmall);
          expect(selectedOption.selected, isTrue);
          expect(
            selectedOption.selectedBackgroundColor?.a,
            closeTo(0.2, 0.001),
          );
          expect(selectedOption.focusBorderColor, colors.focusRing);

          await tester.tap(
            find.byKey(const ValueKey('agent-permission-preset-fullAccess')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(viewModel.permissionSelection.matchedPresetId, 'fullAccess');
          expect(popover, findsNothing);
          expect(find.text('Full access · Never ask'), findsOneWidget);
        },
      );

      testWidgets(
        'model config stays bounded and scrollable in a narrow window',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(280, 400);
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final models = AgentModelList(
            models: <AgentModelInfo>[
              _modelConfigList.models.first,
              for (var index = 1; index <= 14; index++)
                AgentModelInfo(
                  id: 'model-$index',
                  model: 'model-$index',
                  displayName: 'Model $index',
                ),
            ],
          );
          final provider = _FakeAgentProvider(models: models);
          final viewModel = _createViewModel(provider);
          addTearDown(viewModel.dispose);
          await viewModel.loadModels();
          await tester.pumpWidget(_TestApp(viewModel: viewModel));
          await _pumpAgentPaneUi(tester);
          expect(
            MediaQuery.sizeOf(
              tester.element(
                find.byKey(const ValueKey('agent-model-selector')),
              ),
            ).width,
            280,
          );

          await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          final popover = find.byKey(
            const ValueKey('agent-model-config-popover'),
          );
          final popoverRect = tester.getRect(popover);
          expect(popoverRect.width, 256);
          expect(popoverRect.height, lessThanOrEqualTo(360));
          expect(popoverRect.left, greaterThanOrEqualTo(12 - 1e-9));
          expect(popoverRect.top, greaterThanOrEqualTo(12 - 1e-9));
          expect(popoverRect.right, lessThanOrEqualTo(268 + 1e-9));
          expect(popoverRect.bottom, lessThanOrEqualTo(388 + 1e-9));

          await tester.tap(
            find.byKey(const ValueKey('agent-model-option-gpt-5.5')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.byKey(const ValueKey('agent-model-inline-config-gpt-5.5')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          final expandedPopoverRect = tester.getRect(popover);
          expect(expandedPopoverRect.height, lessThanOrEqualTo(360));
          expect(expandedPopoverRect.top, greaterThanOrEqualTo(12 - 1e-9));
          expect(expandedPopoverRect.bottom, lessThanOrEqualTo(388 + 1e-9));

          final lastModel = find.byKey(
            const ValueKey('agent-model-option-model-14'),
          );
          await tester.scrollUntilVisible(
            lastModel,
            160,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('agent-model-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(lastModel, findsOneWidget);
        },
      );

      testWidgets('opening model config dismisses the trigger tooltip', (
        tester,
      ) async {
        final provider = _FakeAgentProvider(models: _modelConfigList);
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(_TestApp(viewModel: viewModel));
        await _pumpAgentPaneUi(tester);

        final selector = find.byKey(const ValueKey('agent-model-selector'));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(selector));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.textContaining('Fast：已关闭'), findsNothing);

        await tester.tap(selector);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(
          find.byKey(const ValueKey('agent-model-config-popover')),
          findsOneWidget,
        );
        expect(find.textContaining('Fast：已关闭'), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey('agent-model-config-popover')),
          findsNothing,
        );
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await mouse.moveTo(tester.getCenter(selector));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.textContaining('Fast：已关闭'), findsOneWidget);

        await tester.tap(selector);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey('agent-model-config-popover')),
          findsOneWidget,
        );
        expect(find.textContaining('Fast：已关闭'), findsNothing);
        await mouse.removePointer();
      });

      testWidgets('model config resolves Fast and xhigh conflict explicitly', (
        tester,
      ) async {
        final provider = _FakeAgentProvider(models: _modelConfigList);
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(_TestApp(viewModel: viewModel));
        await _pumpAgentPaneUi(tester);

        await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find.byKey(const ValueKey('agent-model-option-gpt-5.5')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final xhighOption = find.byKey(
          const ValueKey('agent-reasoning-option-xhigh'),
        );
        await tester.ensureVisible(xhighOption);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(xhighOption);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find.byKey(const ValueKey('agent-fast-switch-gpt-5.5')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(viewModel.selectedReasoningEffort, 'xhigh');
        expect(viewModel.selectedServiceTierId, isNull);
        expect(viewModel.modelConfigUiState.compatibilityConflict, isNotNull);
        expect(
          find.byKey(const ValueKey('agent-model-compatibility-alert')),
          findsOneWidget,
        );

        final resolveAction = find.byKey(
          const ValueKey('agent-model-alert-切换到高并开启 Fast'),
        );
        await tester.ensureVisible(resolveAction);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(resolveAction);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(viewModel.selectedReasoningEffort, 'high');
        expect(viewModel.selectedServiceTierId, 'priority');
        expect(
          find.byKey(const ValueKey('agent-model-compatibility-alert')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('agent-model-config-popover')),
          findsOneWidget,
        );
      });

      testWidgets(
        'model config supports keyboard model and effort navigation',
        (tester) async {
          final provider = _FakeAgentProvider(models: _modelConfigList);
          final viewModel = _createViewModel(provider);
          addTearDown(viewModel.dispose);
          await viewModel.loadModels();
          await tester.pumpWidget(_TestApp(viewModel: viewModel));
          await _pumpAgentPaneUi(tester);

          await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump(const Duration(milliseconds: 300));

          expect(viewModel.selectedModelId, 'gpt-5.4-mini');
          expect(
            find.byKey(
              const ValueKey('agent-model-inline-config-gpt-5.4-mini'),
            ),
            findsOneWidget,
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump(const Duration(milliseconds: 300));
          expect(viewModel.selectedReasoningEffort, 'high');
        },
      );

      testWidgets('model config rolls back failed save and retries inline', (
        tester,
      ) async {
        final provider = _FakeAgentProvider(models: _modelConfigList);
        final initialPreference = AgentModelPreference(
          modelId: 'gpt-5.5',
          reasoningEffort: 'medium',
          fastEnabled: false,
          serviceTierId: null,
          updatedAt: DateTime.utc(2026, 7, 15),
        );
        final store = _ToggleFailAgentProviderConfigStore(
          AgentProviderSettings(
            providers: <AgentProviderConfig>[
              AgentProviderConfig.defaultCodex.copyWith(
                selectedModel: 'gpt-5.5',
                selectedReasoningEffort: 'medium',
                modelPreferences: <String, AgentModelPreference>{
                  'gpt-5.5': initialPreference,
                },
              ),
              AgentProviderConfig.defaultGrok,
              AgentProviderConfig.defaultCursor,
            ],
          ),
        );
        final viewModel = _createViewModelWithStore(provider, store);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(_TestApp(viewModel: viewModel));
        await _pumpAgentPaneUi(tester);

        await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find.byKey(const ValueKey('agent-model-option-gpt-5.4-mini')),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        await tester.pump();

        expect(viewModel.selectedModelId, 'gpt-5.5');
        expect(viewModel.modelConfigUiState.saveError, isNotNull);
        expect(
          find.byKey(const ValueKey('agent-model-save-error')),
          findsOneWidget,
        );

        store.failSaves = false;
        final retry = find.byKey(const ValueKey('agent-model-alert-重试'));
        await tester.ensureVisible(retry);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(retry);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        await tester.pump();
        // 异步保存完成后，给旧配置卡的退出动画一帧完整时长。
        await tester.pump(const Duration(milliseconds: 200));

        expect(viewModel.selectedModelId, 'gpt-5.4-mini');
        expect(viewModel.modelConfigUiState.saveError, isNull);
        expect(
          find.byKey(const ValueKey('agent-model-inline-config-gpt-5.4-mini')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('agent-model-save-error')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('agent-model-config-popover')),
          findsOneWidget,
        );
      });

      testWidgets(
        'model config shows next-turn banner while a turn is running',
        (tester) async {
          final provider = _FakeAgentProvider(models: _modelConfigList);
          final viewModel = _createViewModel(provider);
          addTearDown(viewModel.dispose);
          await viewModel.loadModels();
          await tester.pumpWidget(_TestApp(viewModel: viewModel));
          await viewModel.sendMessage('Keep working');
          await _pumpLiveAgentUi(tester);

          await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
          await tester.pump(const Duration(milliseconds: 300));

          expect(
            find.byKey(const ValueKey('agent-model-next-turn-banner')),
            findsOneWidget,
          );
          expect(find.text('配置将在下一回合生效'), findsOneWidget);
          provider.emitEvent(
            const AgentTurnCompletedEvent(
              sessionId: 'session-1',
              turnId: 'turn-1',
            ),
          );
          await tester.pump();
        },
      );

      testWidgets('model config reports an automatic fallback once', (
        tester,
      ) async {
        final provider = _FakeAgentProvider(models: _modelConfigList);
        final store = MemoryAgentProviderConfigStore(
          AgentProviderSettings(
            providers: <AgentProviderConfig>[
              AgentProviderConfig.defaultCodex.copyWith(
                selectedModel: 'retired-model',
                selectedReasoningEffort: 'medium',
              ),
              AgentProviderConfig.defaultGrok,
              AgentProviderConfig.defaultCursor,
            ],
          ),
        );
        final viewModel = _createViewModelWithStore(provider, store);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(_TestApp(viewModel: viewModel));
        await _pumpAgentPaneUi(tester);

        expect(viewModel.selectedModelId, 'gpt-5.5');
        await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey('agent-model-auto-switch-notice')),
          findsOneWidget,
        );
        expect(find.textContaining('retired-model'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey('agent-model-auto-switch-notice')),
          findsNothing,
        );
      });

      testWidgets('user input supports stable option ids and multi-select', (
        tester,
      ) async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await tester.pumpWidget(_TestApp(viewModel: viewModel));
        await viewModel.loadModels();
        await viewModel.switchThread(
          _thread(id: 'thread-question', title: 'Question thread'),
        );

        provider.emitEvent(
          const AgentPermissionRequestedEvent(
            AgentPermissionRequest(
              id: 'question-1',
              title: 'Choose scope',
              kind: AgentPermissionKind.userInput,
              sessionId: 'thread-question',
              questions: <AgentUserInputQaPair>[
                AgentUserInputQaPair(
                  questionId: 'scope',
                  question: 'Select scopes',
                  allowMultiple: true,
                  optionItems: <AgentUserInputOption>[
                    AgentUserInputOption(id: 'source', label: 'Source code'),
                    AgentUserInputOption(id: 'tests', label: 'Tests'),
                  ],
                ),
              ],
            ),
          ),
        );
        await tester.pump();

        final dock = find.byKey(
          const ValueKey('agent-pending-interaction-dock'),
        );
        final messageList = find.byKey(const ValueKey('agent-message-list'));
        final submitButton = find.byKey(
          const ValueKey('agent-permission-approve-question-1'),
        );
        expect(dock, findsOneWidget);
        expect(
          find.descendant(of: dock, matching: submitButton),
          findsOneWidget,
        );
        expect(
          find.descendant(of: messageList, matching: submitButton),
          findsNothing,
        );

        await tester.tap(
          find.byKey(
            const ValueKey('agent-user-input-question-1-scope-source'),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('agent-user-input-question-1-scope-tests')),
        );
        await tester.tap(
          find.byKey(const ValueKey('agent-permission-approve-question-1')),
        );
        await tester.pump();

        expect(provider.permissionDecisions, hasLength(1));
        expect(provider.permissionDecisions.single.answers['scope'], <String>[
          'source',
          'tests',
        ]);
        expect(dock, findsNothing);
      });

      testWidgets(
        'renders dynamic session config options and sends stable values',
        (tester) async {
          final provider = _FakeAgentProvider();
          final viewModel = _createViewModel(provider);
          addTearDown(provider.dispose);
          addTearDown(viewModel.dispose);
          await tester.pumpWidget(_TestApp(viewModel: viewModel));
          await viewModel.loadModels();
          await viewModel.switchThread(
            _thread(id: 'thread-config', title: 'Config thread'),
          );
          provider.emitEvent(
            const AgentSessionConfigUpdatedEvent(
              sessionId: 'thread-config',
              options: <AgentSessionConfigOption>[
                AgentSessionConfigOption(
                  id: 'cursor-model',
                  name: 'Model',
                  category: 'model',
                  kind: AgentSessionConfigOptionKind.select,
                  currentValue: 'fast',
                  values: <AgentSessionConfigValue>[
                    AgentSessionConfigValue(id: 'fast', label: 'Fast'),
                    AgentSessionConfigValue(id: 'smart', label: 'Smart'),
                  ],
                ),
              ],
            ),
          );
          await tester.pump();

          expect(
            find.byKey(const ValueKey('agent-session-config-cursor-model')),
            findsOneWidget,
          );
          expect(find.text('Fast'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('agent-session-config-cursor-model')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(
            find.byKey(
              const ValueKey('agent-session-config-cursor-model-option-smart'),
            ),
          );
          await tester.pump();

          expect(provider.sessionConfigSelections, <(String, String, Object)>[
            ('thread-config', 'cursor-model', 'smart'),
          ]);
        },
      );

      testWidgets('renders and accepts an independent plan approval card', (
        tester,
      ) async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await tester.pumpWidget(_TestApp(viewModel: viewModel));
        await viewModel.loadModels();
        await viewModel.switchThread(
          _thread(id: 'thread-plan', title: 'Plan thread'),
        );
        provider.emitEvent(
          const AgentPlanApprovalRequestedEvent(
            AgentPlanApprovalRequest(
              id: 'plan-1',
              title: 'Refactor tabs',
              overview: 'Preserve behavior',
              markdown: '1. Inspect\n2. Update',
              todos: <AgentPlanEntry>[
                AgentPlanEntry(
                  id: 'todo-1',
                  content: 'Inspect current layout',
                  status: 'completed',
                ),
              ],
              sessionId: 'thread-plan',
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Refactor tabs'), findsOneWidget);
        expect(find.text('Inspect current layout'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('agent-plan-accept-plan-1')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('agent-message-list')),
            matching: find.byKey(const ValueKey('agent-plan-accept-plan-1')),
          ),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('agent-plan-accept-plan-1')),
        );
        await tester.pump();

        expect(
          provider.planDecisions.single.kind,
          AgentPlanApprovalDecisionKind.accepted,
        );
        expect(
          find.byKey(const ValueKey('agent-plan-accept-plan-1')),
          findsNothing,
        );
      });

      testWidgets(
        'stacks permissions before plans and keeps composer visible in a short window',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(480, 400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final provider = _FakeAgentProvider();
          final viewModel = _createViewModel(provider);
          addTearDown(provider.dispose);
          addTearDown(viewModel.dispose);
          await tester.pumpWidget(_TestApp(viewModel: viewModel));
          await viewModel.loadModels();
          await viewModel.switchThread(
            _thread(id: 'thread-pending', title: 'Pending thread'),
          );

          provider.emitEvent(
            const AgentPermissionRequestedEvent(
              AgentPermissionRequest(
                id: 'permission-1',
                title: 'Approve command',
                kind: AgentPermissionKind.commandExecution,
                command: 'flutter test',
                sessionId: 'thread-pending',
              ),
            ),
          );
          provider.emitEvent(
            AgentPlanApprovalRequestedEvent(
              AgentPlanApprovalRequest(
                id: 'plan-long',
                title: 'Approve long plan',
                markdown: List<String>.generate(
                  24,
                  (index) => '${index + 1}. Update component ${index + 1}',
                ).join('\n'),
                sessionId: 'thread-pending',
              ),
            ),
          );
          await tester.pump();

          final dock = find.byKey(
            const ValueKey('agent-pending-interaction-dock'),
          );
          final permission = find.byKey(
            const ValueKey('agent-pending-permission-permission-1'),
          );
          final plan = find.byKey(
            const ValueKey('agent-pending-plan-plan-long'),
          );
          final composer = find.byKey(const ValueKey('agent-message-input'));
          expect(dock, findsOneWidget);
          expect(permission, findsOneWidget);
          expect(plan, findsOneWidget);
          expect(
            tester.getTopLeft(permission).dy,
            lessThan(tester.getTopLeft(plan).dy),
          );
          expect(tester.getSize(dock).height, lessThanOrEqualTo(140));
          expect(tester.getBottomLeft(composer).dy, lessThanOrEqualTo(400));
        },
      );
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.viewModel,
    this.uiFontFamily,
    this.codeFontFamily = 'CodeFont',
    this.disableAnimations = false,
  });

  final AgentConversationViewModel viewModel;
  final String? uiFontFamily;
  final String codeFontFamily;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final lightIdeTheme = buildIdeThemeData(
      brightness: Brightness.light,
      uiFontFamily: uiFontFamily,
      codeFontFamily: codeFontFamily,
    );
    final darkIdeTheme = buildIdeThemeData(
      brightness: Brightness.dark,
      uiFontFamily: uiFontFamily,
      codeFontFamily: codeFontFamily,
    );
    return IdeThemeScope(
      themeMode: ThemeMode.dark,
      lightTheme: lightIdeTheme,
      darkTheme: darkIdeTheme,
      child: sf.ShadcnApp(
        theme: buildShadcnTheme(lightIdeTheme),
        darkTheme: buildShadcnTheme(darkIdeTheme),
        materialTheme: buildMaterialTheme(darkIdeTheme),
        themeMode: sf.ThemeMode.dark,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: sf.Scaffold(child: AgentPane(viewModel: viewModel)),
          ),
        ),
      ),
    );
  }
}

const AgentModelList _modelConfigList = AgentModelList(
  models: <AgentModelInfo>[
    AgentModelInfo(
      id: 'gpt-5.5',
      model: 'gpt-5.5',
      displayName: 'GPT-5.5',
      isDefault: true,
      supportedReasoningEfforts: <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'low'),
        AgentModelReasoningEffort(effort: 'medium'),
        AgentModelReasoningEffort(effort: 'high'),
        AgentModelReasoningEffort(effort: 'xhigh'),
      ],
      defaultReasoningEffort: 'medium',
      serviceTiers: <AgentModelServiceTier>[
        AgentModelServiceTier(id: 'priority', name: 'Fast'),
      ],
    ),
    AgentModelInfo(
      id: 'gpt-5.4-mini',
      model: 'gpt-5.4-mini',
      displayName: 'GPT-5.4-Mini',
      supportedReasoningEfforts: <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'low'),
        AgentModelReasoningEffort(effort: 'high'),
        AgentModelReasoningEffort(effort: 'xhigh'),
      ],
      defaultReasoningEffort: 'low',
      serviceTiers: <AgentModelServiceTier>[
        AgentModelServiceTier(id: 'priority', name: 'Fast'),
      ],
    ),
    AgentModelInfo(
      id: 'gpt-legacy',
      model: 'gpt-legacy',
      displayName: 'GPT-Legacy',
      enabled: false,
      unavailableReason: '当前账号没有访问权限',
    ),
  ],
);

AgentConversationViewModel _createViewModel(_FakeAgentProvider provider) {
  return _createViewModelWithStore(provider, MemoryAgentProviderConfigStore());
}

AgentConversationViewModel _createViewModelWithStore(
  _FakeAgentProvider provider,
  AgentProviderConfigStore configStore,
) {
  final controller = ActiveAgentProviderController(
    providerFactory: _FakeAgentProviderFactory(provider),
    configStore: configStore,
  );
  addTearDown(controller.dispose);
  final viewModel = AgentConversationViewModel(providerController: controller);
  viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
  return viewModel;
}

class _ToggleFailAgentProviderConfigStore implements AgentProviderConfigStore {
  _ToggleFailAgentProviderConfigStore(this.settings);

  AgentProviderSettings settings;
  bool failSaves = true;

  @override
  Future<AgentProviderSettings> load() async => settings;

  @override
  Future<void> save(AgentProviderSettings next) async {
    if (failSaves) {
      throw const FileSystemException('simulated model config save failure');
    }
    settings = next;
  }
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

String _fileEditItemId(String toolCallId, String filePath) {
  return 'file-edit-$toolCallId-$filePath';
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

String? _fontFamilyForRenderedText(
  WidgetTester tester,
  Finder finder,
  String textFragment,
) {
  final widget = tester.widget(finder);
  if (widget is Text) {
    return widget.style?.fontFamily;
  }
  if (widget is RichText) {
    return _fontFamilyForInlineSpan(widget.text, textFragment);
  }
  return null;
}

String? _fontFamilyForInlineSpan(
  InlineSpan span,
  String textFragment, [
  TextStyle? inheritedStyle,
]) {
  if (span is TextSpan) {
    final effectiveStyle = inheritedStyle?.merge(span.style) ?? span.style;
    if ((span.text ?? '').contains(textFragment)) {
      return effectiveStyle?.fontFamily;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final fontFamily = _fontFamilyForInlineSpan(
        child,
        textFragment,
        effectiveStyle,
      );
      if (fontFamily != null) {
        return fontFamily;
      }
    }
  }
  if (span is WidgetSpan) {
    return inheritedStyle?.fontFamily;
  }
  return null;
}

MarkdownWidget _markdownWidgetUnder(WidgetTester tester, Finder ancestor) {
  final finder = find.descendant(
    of: ancestor,
    matching: find.byType(MarkdownWidget),
  );
  expect(finder, findsOneWidget);
  return tester.widget<MarkdownWidget>(finder);
}

void _expectMarkdownWidgetDefaults(MarkdownWidget widget) {
  expect(widget.useColumn, isTrue);
  expect(widget.selectable, isTrue);
  expect(widget.padding, EdgeInsets.zero);
  expect(widget.enableCopyFullDocumentShortcut, isFalse);
  expect(widget.showCopyAllInContextMenu, isFalse);
}

class _FakeAgentProviderFactory implements AgentProviderFactory {
  const _FakeAgentProviderFactory(this.provider);

  final _FakeAgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

class _FakeAgentProvider
    with AgentProviderThreadLifecycleStub
    implements
        AgentProvider,
        AgentSessionConfigProvider,
        AgentPlanApprovalProvider {
  _FakeAgentProvider({
    Map<String, AgentThreadHistorySnapshot> historySnapshotsByThread =
        const <String, AgentThreadHistorySnapshot>{},
    this.models = const AgentModelList(models: <AgentModelInfo>[]),
  }) : _historySnapshotsByThread = Map<String, AgentThreadHistorySnapshot>.from(
         historySnapshotsByThread,
       );

  final Map<String, AgentThreadHistorySnapshot> _historySnapshotsByThread;
  final AgentModelList models;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final List<AgentPermissionDecision> permissionDecisions =
      <AgentPermissionDecision>[];
  final List<(String, String, Object)> sessionConfigSelections =
      <(String, String, Object)>[];
  final List<AgentPlanApprovalDecision> planDecisions =
      <AgentPlanApprovalDecision>[];

  void emitEvent(AgentEvent event) {
    _events.add(event);
  }

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
    return models;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  @override
  void updatePermissionSelection(AgentPermissionSelection selection) {}

  @override
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles() async {
    return const <AgentPermissionProfileSummary>[];
  }

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {}

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    return _historySnapshotsByThread[threadId] ??
        AgentThreadHistorySnapshot(
          threadId: threadId,
          turns: const <AgentHistoryTurn>[],
        );
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {}

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {}

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    permissionDecisions.add(decision);
  }

  @override
  List<AgentSessionConfigOption> sessionConfigOptions(String sessionId) {
    return const <AgentSessionConfigOption>[];
  }

  @override
  Future<void> setSessionConfigOption({
    required String sessionId,
    required String configId,
    required Object value,
  }) async {
    sessionConfigSelections.add((sessionId, configId, value));
  }

  @override
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision) async {
    planDecisions.add(decision);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

/// AgentPane 含有输入光标、浮层和 footer 测量等持续 frame 源，`pumpAndSettle()`
/// 在该文件里容易永久等待；测试统一用有限帧推进到稳定视觉状态。
Future<void> _pumpAgentPaneUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(IdeMotion.durationSlow);
  await tester.pump();
}

/// 运行中 turn 的 spinner 不会 settle，只推进流式内容渲染所需的有限帧。
Future<void> _pumpLiveAgentUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
