import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';

import '../../../testing/agent_provider_stub_base.dart';

void main() {
  group('AgentPane PR3', () {
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
        await tester.pumpAndSettle();

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

    testWidgets('renders end-of-turn footer with duration and token usage', (
      tester,
    ) async {
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
                  tokenUsage: const AgentTokenUsage(
                    inputTokens: 1000,
                    outputTokens: 240,
                    totalTokens: 1240,
                  ),
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
      await tester.pumpAndSettle();

      final footer = find.byKey(
        const ValueKey<String>('agent-turn-footer-turn-footer-1'),
      );
      expect(footer, findsOneWidget);
      expect(
        find.descendant(of: footer, matching: find.text('1m 35s')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: footer, matching: find.text('1.2k tokens')),
        findsOneWidget,
      );
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
        await tester.pumpAndSettle();

        expect(viewModel.isPlanMessageExpanded('history-plan-1'), isFalse);
        expect(
          find.byKey(
            const ValueKey<String>('agent-plan-preview-history-plan-1'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('agent-plan-body-history-plan-1')),
          findsNothing,
        );

        final historyVersion = viewModel.historyVersion;
        await tester.tap(
          find.byKey(
            const ValueKey<String>('agent-plan-toggle-history-plan-1'),
          ),
        );
        await tester.pumpAndSettle();

        expect(viewModel.historyVersion, historyVersion);
        expect(viewModel.isPlanMessageExpanded('history-plan-1'), isTrue);
        expect(
          find.byKey(const ValueKey<String>('agent-plan-body-history-plan-1')),
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
        await tester.pumpAndSettle();

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
        await tester.pumpAndSettle();

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
        await tester.pumpAndSettle();

        final updatedMarkdownWidget = _markdownWidgetUnder(
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
        await tester.pumpAndSettle();

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
        await tester.tap(expandAllFinder);
        await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
    });

    testWidgets('model selector opens options and updates selection', (
      tester,
    ) async {
      final provider = _FakeAgentProvider(
        models: const AgentModelList(
          models: <AgentModelInfo>[
            AgentModelInfo(
              id: 'gpt-5.5',
              model: 'gpt-5.5',
              displayName: 'GPT-5.5',
              isDefault: true,
              supportedReasoningEfforts: <AgentModelReasoningEffort>[
                AgentModelReasoningEffort(effort: 'medium'),
              ],
              defaultReasoningEffort: 'medium',
            ),
            AgentModelInfo(
              id: 'gpt-5.4-mini',
              model: 'gpt-5.4-mini',
              displayName: 'GPT-5.4-Mini',
              supportedReasoningEfforts: <AgentModelReasoningEffort>[
                AgentModelReasoningEffort(effort: 'low'),
              ],
              defaultReasoningEffort: 'low',
            ),
          ],
        ),
      );
      final viewModel = _createViewModel(provider);
      await viewModel.loadModels();
      await tester.pumpWidget(_TestApp(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('agent-model-selector')),
        findsOneWidget,
      );
      expect(find.text('GPT-5.5'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('agent-model-selector')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('agent-model-option-gpt-5.4-mini')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('agent-model-option-gpt-5.4-mini')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(viewModel.selectedModelId, 'gpt-5.4-mini');
      expect(find.text('GPT-5.4-Mini'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('agent-model-option-gpt-5.4-mini')),
        findsNothing,
      );
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.viewModel,
    this.uiFontFamily,
    this.codeFontFamily = 'CodeFont',
  });

  final AgentConversationViewModel viewModel;
  final String? uiFontFamily;
  final String codeFontFamily;

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
        home: sf.Scaffold(child: AgentPane(viewModel: viewModel)),
      ),
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
    implements AgentProvider {
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
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
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
