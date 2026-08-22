import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'harness/agent_pane_test_harness.dart';

void main() {
  group('AgentPane pending interactions', () {
    testWidgets('user input supports stable option ids and multi-select', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(
          id: 'thread-question',
          title: 'Question thread',
        ),
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await viewModel.loadModels();
      await viewModel.initialization;
      await _startLiveTurn(tester, viewModel);
      await pumpAgentPaneUi(tester);
      final messageInput = find.byKey(const ValueKey('agent-message-input'));
      await tester.enterText(messageInput, '需要保留的草稿');

      provider.emitEvent(
        const AgentQuestionRequestedEvent(
          AgentQuestionRequest(
            id: 'question-1',
            title: 'Choose scope',
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

      final dock = find.byKey(const ValueKey('agent-pending-interaction-dock'));
      final conversationFooter = find.byKey(
        const ValueKey('agent-conversation-footer'),
      );
      final composerSurface = find.byKey(
        const ValueKey('agent-composer-focus-ring'),
      );
      final messageList = find.byKey(const ValueKey('agent-message-list'));
      final submitButton = find.byKey(
        const ValueKey('agent-question-submit-question-1-scope'),
      );
      expect(dock, findsOneWidget);
      expect(find.descendant(of: dock, matching: submitButton), findsOneWidget);
      expect(
        find.descendant(of: messageList, matching: submitButton),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('agent-question-skip-question-1-scope')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-permission-deny-question-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('agent-permission-cancel-question-1')),
        findsNothing,
      );
      expect(composerSurface, findsNothing);
      expect(messageInput, findsNothing);
      expect(tester.getSize(conversationFooter).height, greaterThan(0));
      // 用户提问仍由 live 活动条反馈等待状态；不能复用计划文档的隐藏条件。
      expect(
        find.byKey(const ValueKey('agent-live-activity-status')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('agent-question-question-1-scope-source')),
      );
      await tester.tap(
        find.byKey(const ValueKey('agent-question-question-1-scope-tests')),
      );
      await tester.pump(IdeMotion.durationFast);
      await tester.tap(
        find.byKey(const ValueKey('agent-question-submit-question-1-scope')),
      );
      await tester.pump();

      expect(provider.questionResponses, hasLength(1));
      expect(provider.questionResponses.single.answers['scope'], <String>[
        'source',
        'tests',
      ]);
      expect(provider.permissionDecisions, isEmpty);
      expect(dock, findsNothing);
      expect(composerSurface, findsOneWidget);
      expect(messageInput, findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: messageInput,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '需要保留的草稿',
      );
      await _finishLiveTurn(tester, provider, sessionId: 'thread-question');
    });

    testWidgets(
      'single-choice questions advance automatically and support review',
      (tester) async {
        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(
          provider,
          initialThread: agentPaneThread(
            id: 'thread-wizard',
            title: 'Question wizard',
          ),
        );
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.loadModels();
        await viewModel.initialization;
        await _startLiveTurn(tester, viewModel);

        provider.emitEvent(
          const AgentQuestionRequestedEvent(
            AgentQuestionRequest(
              id: 'question-wizard',
              title: 'Implementation choices',
              sessionId: 'thread-wizard',
              questions: <AgentUserInputQaPair>[
                AgentUserInputQaPair(
                  questionId: 'layout',
                  question: 'Choose the layout',
                  optionItems: <AgentUserInputOption>[
                    AgentUserInputOption(id: 'rows', label: 'List rows'),
                    AgentUserInputOption(id: 'cards', label: 'Cards'),
                  ],
                ),
                AgentUserInputQaPair(
                  questionId: 'motion',
                  question: 'Choose the motion',
                  optionItems: <AgentUserInputOption>[
                    AgentUserInputOption(id: 'subtle', label: 'Subtle'),
                    AgentUserInputOption(id: 'none', label: 'None'),
                  ],
                ),
              ],
            ),
          ),
        );
        await pumpAgentPaneUi(tester);

        final firstOption = find.byKey(
          const ValueKey('agent-question-question-wizard-layout-rows'),
        );
        expect(find.text('Choose the layout'), findsOneWidget);
        expect(find.text('Choose the motion'), findsNothing);
        expect(find.text('1 of 2'), findsOneWidget);

        await tester.tap(firstOption);
        await tester.pump();
        expect(
          tester
              .widget<PaneInteractiveSurface>(
                find.descendant(
                  of: firstOption,
                  matching: find.byType(PaneInteractiveSurface),
                ),
              )
              .selected,
          isTrue,
        );
        expect(find.text('Choose the layout'), findsOneWidget);

        await tester.pump(IdeMotion.durationFast);
        await tester.pump(IdeMotion.durationNormal);
        await tester.pump();
        expect(find.text('Choose the motion'), findsOneWidget);
        expect(find.text('2 of 2'), findsOneWidget);
        expect(provider.questionResponses, isEmpty);

        await tester.tap(
          find.byKey(
            const ValueKey('agent-question-previous-question-wizard-motion'),
          ),
        );
        await tester.pump(IdeMotion.durationNormal);
        await tester.pump();
        expect(find.text('Choose the layout'), findsOneWidget);
        expect(
          tester
              .widget<PaneInteractiveSurface>(
                find.descendant(
                  of: firstOption,
                  matching: find.byType(PaneInteractiveSurface),
                ),
              )
              .selected,
          isTrue,
        );

        await tester.tap(
          find.byKey(
            const ValueKey('agent-question-next-question-wizard-layout'),
          ),
        );
        await tester.pump(IdeMotion.durationNormal);
        await tester.pump();
        expect(find.text('Choose the motion'), findsOneWidget);

        await tester.tap(
          find.byKey(
            const ValueKey('agent-question-question-wizard-motion-subtle'),
          ),
        );
        await tester.pump(IdeMotion.durationFast);
        await tester.pump();

        expect(provider.questionResponses, hasLength(1));
        expect(
          provider.questionResponses.single.answers,
          <String, List<String>>{
            'layout': <String>['rows'],
            'motion': <String>['subtle'],
          },
        );
        expect(
          find.byKey(const ValueKey('agent-pending-interaction-dock')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('agent-composer-focus-ring')),
          findsOneWidget,
        );
        await _finishLiveTurn(tester, provider, sessionId: 'thread-wizard');
      },
    );

    testWidgets(
      'custom answers expand inline while skip and close keep distinct semantics',
      (tester) async {
        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(
          provider,
          initialThread: agentPaneThread(
            id: 'thread-other',
            title: 'Other answer',
          ),
        );
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.loadModels();
        await viewModel.initialization;
        await _startLiveTurn(tester, viewModel);

        provider.emitEvent(
          const AgentQuestionRequestedEvent(
            AgentQuestionRequest(
              id: 'question-other',
              title: 'Implementation choices',
              sessionId: 'thread-other',
              questions: <AgentUserInputQaPair>[
                AgentUserInputQaPair(
                  questionId: 'strategy',
                  question: 'Choose a strategy',
                  isOther: true,
                  optionItems: <AgentUserInputOption>[
                    AgentUserInputOption(
                      id: 'default',
                      label: 'Default strategy',
                    ),
                  ],
                ),
                AgentUserInputQaPair(
                  questionId: 'details',
                  question: 'Add implementation details',
                ),
              ],
            ),
          ),
        );
        await pumpAgentPaneUi(tester);

        await tester.tap(
          find.byKey(
            const ValueKey(
              'agent-question-other-trigger-question-other-strategy',
            ),
          ),
        );
        await tester.pump(IdeMotion.durationNormal);
        final otherField = find.byKey(
          const ValueKey('agent-question-other-question-other-strategy'),
        );
        expect(otherField, findsOneWidget);

        await tester.enterText(otherField, '自定义实现方案');
        await tester.pump();
        await tester.tap(
          find.byKey(
            const ValueKey(
              'agent-question-other-submit-question-other-strategy',
            ),
          ),
        );
        await pumpAgentPaneUi(tester);
        expect(find.text('Add implementation details'), findsOneWidget);
        expect(provider.questionResponses, isEmpty);

        final skipDetails = find.byKey(
          const ValueKey('agent-question-skip-question-other-details'),
        );
        await tester.ensureVisible(skipDetails);
        await tester.pump();
        await tester.tap(skipDetails);
        await tester.pump();
        expect(provider.questionResponses, hasLength(1));
        expect(
          provider.questionResponses.single.answers,
          <String, List<String>>{
            'strategy': <String>['自定义实现方案'],
          },
        );

        provider.emitEvent(
          const AgentQuestionRequestedEvent(
            AgentQuestionRequest(
              id: 'question-close',
              title: 'Close semantics',
              sessionId: 'thread-other',
              questions: <AgentUserInputQaPair>[
                AgentUserInputQaPair(
                  questionId: 'scope',
                  question: 'Select scopes',
                  allowMultiple: true,
                  optionItems: <AgentUserInputOption>[
                    AgentUserInputOption(id: 'source', label: 'Source'),
                  ],
                ),
              ],
            ),
          ),
        );
        await pumpAgentPaneUi(tester);
        await tester.tap(
          find.byKey(
            const ValueKey('agent-question-question-close-scope-source'),
          ),
        );
        await tester.pump();
        final closeQuestion = find.byKey(
          const ValueKey('agent-question-close-question-close-scope'),
        );
        await tester.ensureVisible(closeQuestion);
        await tester.pump(IdeMotion.durationNormal);
        await tester.tap(closeQuestion);
        await tester.pump();

        expect(provider.questionResponses, hasLength(2));
        expect(provider.questionResponses.last.answers, isEmpty);
        await _finishLiveTurn(tester, provider, sessionId: 'thread-other');
      },
    );

    testWidgets('question transitions honor reduced motion', (tester) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(
          id: 'thread-reduced-motion',
          title: 'Reduced motion',
        ),
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(
        AgentPaneTestApp(viewModel: viewModel, disableAnimations: true),
      );
      await viewModel.loadModels();
      await viewModel.initialization;
      await _startLiveTurn(tester, viewModel);

      provider.emitEvent(
        const AgentQuestionRequestedEvent(
          AgentQuestionRequest(
            id: 'question-reduced-motion',
            title: 'Reduced motion',
            sessionId: 'thread-reduced-motion',
            questions: <AgentUserInputQaPair>[
              AgentUserInputQaPair(
                questionId: 'first',
                question: 'First reduced-motion question',
                optionItems: <AgentUserInputOption>[
                  AgentUserInputOption(id: 'yes', label: 'Yes'),
                ],
              ),
              AgentUserInputQaPair(
                questionId: 'second',
                question: 'Second reduced-motion question',
                optionItems: <AgentUserInputOption>[
                  AgentUserInputOption(id: 'yes', label: 'Yes'),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(
          const ValueKey('agent-question-question-reduced-motion-first-yes'),
        ),
      );
      await tester.pump();

      expect(find.text('First reduced-motion question'), findsNothing);
      expect(find.text('Second reduced-motion question'), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget);
      await _finishLiveTurn(
        tester,
        provider,
        sessionId: 'thread-reduced-motion',
      );
    });

    testWidgets('renders and accepts an independent plan approval card', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(id: 'thread-plan', title: 'Plan thread'),
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await viewModel.loadModels();
      await viewModel.initialization;
      await _startLiveTurn(tester, viewModel);
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
      expect(find.text('接受计划'), findsOneWidget);
      expect(find.text('执行'), findsNothing);
      final execute = find.byKey(const ValueKey('agent-plan-execute-plan-1'));
      expect(execute, findsOneWidget);
      // 计划卡在对话流内渲染，不再挂到 Composer 上方的 pending dock。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('agent-message-list')),
          matching: execute,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-pending-interaction-dock')),
        findsNothing,
      );
      await tester.tap(execute);
      await tester.pump();

      expect(
        provider.planDecisions.single.kind,
        AgentPlanApprovalDecisionKind.accepted,
      );
      expect(execute, findsNothing);
      await _finishLiveTurn(tester, provider, sessionId: 'thread-plan');
    });

    testWidgets(
      'keeps plans out of the dock and hides composer while pending',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(480, 400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(
          provider,
          initialThread: agentPaneThread(
            id: 'thread-pending',
            title: 'Pending thread',
          ),
        );
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.loadModels();
        await viewModel.initialization;
        await _startLiveTurn(tester, viewModel);

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
        final composer = find.byKey(const ValueKey('agent-message-input'));
        expect(dock, findsOneWidget);
        expect(permission, findsOneWidget);
        expect(find.text('Approve command'), findsOneWidget);
        expect(find.text('允许'), findsOneWidget);
        expect(find.text('拒绝'), findsOneWidget);
        expect(find.text('取消'), findsOneWidget);
        expect(find.text('本会话允许'), findsOneWidget);
        expect(find.text('flutter test'), findsOneWidget);
        final dockPadding = tester.widget<Padding>(
          find.ancestor(of: dock, matching: find.byType(Padding)).first,
        );
        expect(
          dockPadding.padding.resolve(TextDirection.ltr).bottom,
          IdeSpacing.space12,
        );
        // dock 只承载权限与提问；计划卡已移入对话流。
        expect(
          find.byKey(const ValueKey('agent-pending-plan-plan-long')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('agent-message-list')),
            matching: find.byKey(
              const ValueKey('agent-plan-document-card-plan-long'),
            ),
          ),
          findsOneWidget,
        );
        // 无计划卡后 dock 回到紧凑上限（400 * 0.35 = 140）。
        expect(tester.getSize(dock).height, lessThanOrEqualTo(140));
        // 权限 / 计划审批待处理时仍隐藏主 Composer。
        expect(composer, findsNothing);
        await _finishLiveTurn(tester, provider, sessionId: 'thread-pending');
      },
    );
  });
}

Future<void> _startLiveTurn(
  WidgetTester tester,
  AgentConversationViewModel viewModel,
) async {
  await viewModel.sendMessage('Start live interaction');
  await pumpLiveAgentUi(tester);
}

Future<void> _finishLiveTurn(
  WidgetTester tester,
  AgentPaneFakeProvider provider, {
  required String sessionId,
}) async {
  provider.emitEvent(
    AgentTurnCompletedEvent(sessionId: sessionId, turnId: 'turn-1'),
  );
  await tester.pump();
}
