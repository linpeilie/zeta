import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_file_change_evidence_views.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'harness/agent_pane_test_harness.dart';

void main() {
  group('AgentPane history content', () {
    testWidgets(
      'renders heavy history markdown fully without collapse toggle',
      (tester) async {
        final viewModel = createAgentPaneViewModel(
          AgentPaneFakeProvider(
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
          initialThread: agentPaneThread(
            id: 'thread-markdown',
            title: 'Heavy markdown',
          ),
        );
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.initialization;
        await pumpAgentPaneUi(tester);

        // 历史长文不再折叠：无预览/展开按钮，正文完整可见。
        expect(
          find.byKey(
            const ValueKey<String>('agent-markdown-preview-history-markdown-1'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey<String>('agent-markdown-toggle-history-markdown-1'),
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
      final viewModel = createAgentPaneViewModel(
        AgentPaneFakeProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-grok-failed': const AgentThreadHistorySnapshot(
              threadId: 'thread-grok-failed',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-grok-failed',
                  status: AgentHistoryTurnStatus.failed,
                  duration: Duration(seconds: 9),
                  modelId: 'grok-4.5',
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
        initialThread: agentPaneThread(
          id: 'thread-grok-failed',
          title: 'Failed Grok turn',
        ),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await viewModel.initialization;
      await pumpAgentPaneUi(tester);

      expect(find.textContaining(errorMessage), findsOneWidget);
      expect(find.textContaining('用量或速率额度已用尽'), findsOneWidget);
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

    testWidgets('restores historical serverOverloaded capacity guidance', (
      tester,
    ) async {
      const errorMessage =
          'Selected model is at capacity. Please try a different model.';
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final viewModel = createAgentPaneViewModel(
        AgentPaneFakeProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-capacity': const AgentThreadHistorySnapshot(
              threadId: 'thread-capacity',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-capacity',
                  status: AgentHistoryTurnStatus.failed,
                  duration: Duration(seconds: 12),
                  modelId: 'gpt-5.6-luna',
                  errorMessage: errorMessage,
                  errorCode: 'serverOverloaded',
                  entries: <AgentHistoryEntry>[
                    AgentHistoryMessageEntry(
                      id: 'history-user-capacity',
                      role: AgentMessageRole.user,
                      text: 'Continue the task',
                    ),
                  ],
                ),
              ],
            ),
          },
        ),
        initialThread: agentPaneThread(
          id: 'thread-capacity',
          title: 'Capacity failure',
        ),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await viewModel.initialization;
      await pumpAgentPaneUi(tester);

      expect(find.textContaining(errorMessage), findsOneWidget);
      expect(find.textContaining('当前模型容量已满'), findsOneWidget);
      expect(find.textContaining('切换其他模型'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('agent-turn-footer-turn-capacity')),
        findsOneWidget,
      );
    });

    testWidgets('renders end-of-turn footer with duration and token usage', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final viewModel = createAgentPaneViewModel(
        AgentPaneFakeProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-footer': AgentThreadHistorySnapshot(
              threadId: 'thread-footer',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-footer-1',
                  status: AgentHistoryTurnStatus.completed,
                  duration: const Duration(seconds: 95),
                  modelId: 'gpt-5.5',
                  reasoningEffort: AgentHistoryReasoningEffort.explicit('high'),
                  serviceTierId: 'priority',
                  explicitFast: true,
                  tokenUsage: const AgentTokenUsage(
                    inputTokens: 1000,
                    outputTokens: 240,
                    totalTokens: 1240,
                  ),
                  raw: const <String, Object?>{
                    'turnContext': <String, Object?>{
                      'model': 'gpt-5.5',
                      'serviceTier': 'ignored',
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
        initialThread: agentPaneThread(
          id: 'thread-footer',
          title: 'Footer turn',
        ),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await viewModel.initialization;
      await pumpAgentPaneUi(tester);

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
        find.descendant(of: footer, matching: find.text('high')),
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
          const ValueKey<String>('agent-turn-footer-separator-turn-footer-1-0'),
        ),
      );
      expect(
        firstSeparator.padding,
        const EdgeInsets.symmetric(horizontal: IdeSpacing.space8),
      );
      expect(
        find.descendant(of: footer, matching: find.byIcon(Icons.bolt_outlined)),
        findsNothing,
      );

      await tester.binding.setSurfaceSize(const Size(480, 800));
      await pumpAgentPaneUi(tester);

      expect(
        find.byKey(
          const ValueKey<String>('agent-turn-footer-stacked-turn-footer-1'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('expands history plan card without replacing history state', (
      tester,
    ) async {
      final viewModel = createAgentPaneViewModel(
        AgentPaneFakeProvider(
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
        initialThread: agentPaneThread(id: 'thread-plan', title: 'Plan card'),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await viewModel.initialization;
      await pumpAgentPaneUi(tester);

      expect(viewModel.isPlanMessageExpanded('history-plan-1'), isFalse);
      expect(
        find.byKey(const ValueKey<String>('agent-plan-preview-history-plan-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('agent-plan-body-history-plan-1')),
        findsNothing,
      );

      final historyState = viewModel.historyState;
      await tester.tap(
        find.byKey(const ValueKey<String>('agent-plan-toggle-history-plan-1')),
      );
      await pumpAgentPaneUi(tester);

      expect(viewModel.historyState, historyState);
      expect(viewModel.isPlanMessageExpanded('history-plan-1'), isTrue);
      expect(
        find.byKey(const ValueKey<String>('agent-plan-body-history-plan-1')),
        findsOneWidget,
      );
    });

    testWidgets(
      'renders live agent markdown through a streaming controller and commits the final update',
      (tester) async {
        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.sendMessage('Stream markdown');
        await pumpLiveAgentUi(tester);

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
        await pumpLiveAgentUi(tester);

        final liveSectionFinder = find.byKey(
          const ValueKey<String>('turn-block-turn-1-message-message-1'),
        );
        final liveMarkdownWidget = markdownWidgetUnder(
          tester,
          liveSectionFinder,
        );
        expectMarkdownWidgetDefaults(liveMarkdownWidget);
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
        await pumpLiveAgentUi(tester);

        final updatedMarkdownWidget = markdownWidgetUnder(
          tester,
          liveSectionFinder,
        );
        expect(identical(updatedMarkdownWidget.controller, controller), isTrue);
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
        await pumpLiveAgentUi(tester);

        final completedMarkdownWidget = markdownWidgetUnder(
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
      'renders typed history unified patch lazily without replacing history',
      (tester) async {
        final viewModel = createAgentPaneViewModel(
          AgentPaneFakeProvider(
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
                          fileChanges: AgentFileChangeSnapshot(
                            revision: 1,
                            replayability:
                                AgentFileChangeReplayability.replayable,
                            changes: <AgentFileChange>[
                              AgentFileChange(
                                id: 'main-change',
                                path: 'lib/main.dart',
                                kind: AgentFileChangeKind.modified,
                                evidence: AgentUnifiedPatchEvidence(
                                  patch: agentPaneLargeUnifiedDiff(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            },
          ),
          initialThread: agentPaneThread(
            id: 'thread-diff',
            title: 'Large diff',
          ),
        );
        addTearDown(viewModel.dispose);

        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.initialization;
        await pumpAgentPaneUi(tester);

        final historyState = viewModel.historyState;
        await tester.tap(
          find.byKey(
            ValueKey<String>(
              'agent-file-edit-group-header-${agentPaneFileEditGroupId('turn-diff-1', 'history-edit-large')}',
            ),
          ),
        );
        await pumpAgentPaneUi(tester);

        expect(viewModel.historyState, historyState);

        await tester.tap(
          find.byKey(
            agentFileChangeEvidenceKey(
              'tool-history-edit-large',
              'main-change',
              'header',
            ),
          ),
        );
        await pumpAgentPaneUi(tester);

        expect(viewModel.historyState, historyState);
        expect(
          viewModel.isFileEditItemExpanded(
            agentPaneFileEditItemId('history-edit-large', 'main-change'),
          ),
          isTrue,
        );
        final viewportFinder = find.byKey(
          agentFileChangeEvidenceKey(
            'tool-history-edit-large',
            'main-change',
            'viewport-patch',
          ),
        );
        expect(viewportFinder, findsOneWidget);
        expect(
          find.textContaining('+line 30', findRichText: true),
          findsNothing,
        );

        final initialViewportElement = tester.element(viewportFinder);
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);
        expect(
          identical(tester.element(viewportFinder), initialViewportElement),
          isTrue,
        );

        await tester.drag(viewportFinder, const Offset(0, -800));
        await pumpAgentPaneUi(tester);

        expect(viewModel.historyState, historyState);
        expect(
          find.textContaining('+line 30', findRichText: true),
          findsOneWidget,
        );
      },
    );

    testWidgets('uses ui font for正文 and code font for code-like content', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(
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
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(
          id: 'thread-fonts',
          title: 'Font thread',
        ),
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          uiFontFamily: 'UiFont',
          codeFontFamily: 'CodeFont',
        ),
      );
      await viewModel.initialization;
      await pumpLiveAgentUi(tester);

      final markdownParagraphFinder = find.textContaining(
        'Paragraph text for font check.',
        findRichText: true,
      );
      expect(markdownParagraphFinder, findsOneWidget);
      expect(
        fontFamilyForRenderedText(
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
        fontFamilyForRenderedText(tester, markdownCodeFinder, 'answer'),
        'CodeFont',
      );

      await viewModel.sendMessage('bind session runtime');
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
      await pumpLiveAgentUi(tester);

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
          turnId: 'turn-1',
        ),
      );
      await tester.pump();
    });
  });
}
