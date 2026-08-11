import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

import 'harness/agent_pane_test_harness.dart';

void main() {
  group('AgentPane composer toolbar', () {
    testWidgets(
      'hides mode UI by default and shows Plan badge after more-actions select',
      (tester) async {
        final provider = AgentPaneModeFakeProvider(
          models: agentPaneModelConfigList,
        );
        final modeController = AgentConversationModeController();
        final viewModel = createAgentPaneViewModel(
          provider,
          initialThread: agentPaneThread(
            id: 'thread-mode',
            title: 'Mode thread',
          ),
          conversationModeController: modeController,
        );
        addTearDown(provider.dispose);
        addTearDown(modeController.dispose);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.initialization;
        await viewModel.sendMessage('bind session runtime');
        provider.emitEvent(
          const AgentSessionConfigUpdatedEvent(
            sessionId: 'thread-mode',
            options: <AgentSessionConfigOption>[
              AgentSessionConfigOption(
                id: 'cursor-model',
                name: 'Session model',
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
        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-session-config-cursor-model')),
        );
        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-more-actions-button')),
        );

        final planBadge = find.byKey(
          const ValueKey('agent-composer-plan-badge'),
        );
        final sessionSelector = find.byKey(
          const ValueKey('agent-session-config-cursor-model'),
        );
        final modelSelector = find.byKey(
          const ValueKey('agent-model-selector'),
        );
        final permissionSelector = find.byKey(
          const ValueKey('agent-permission-option-selector'),
        );
        // Default：不展示模式选择器 / Plan 标识。
        expect(find.byKey(const ValueKey('agent-mode-selector')), findsNothing);
        expect(planBadge, findsNothing);
        expect(sessionSelector, findsOneWidget);
        expect(modelSelector, findsOneWidget);
        expect(permissionSelector, findsOneWidget);
        // 左侧：会话配置 → 审批；模型选择器固定在右侧。
        expect(
          tester.getTopLeft(sessionSelector).dx,
          lessThan(tester.getTopLeft(permissionSelector).dx),
        );
        expect(
          tester.getTopLeft(permissionSelector).dx,
          lessThan(tester.getTopLeft(modelSelector).dx),
        );

        var selectionNotifications = 0;
        modeController.addListener(() {
          selectionNotifications += 1;
        });
        await tester.tap(
          find.byKey(const ValueKey('agent-more-actions-button')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('agent-more-actions-plan')));
        // 更多操作在 popover dismiss 完成后才切换模式。
        await pumpUntilFinder(tester, planBadge);

        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.plan,
        );
        expect(selectionNotifications, 1);
        expect(planBadge, findsOneWidget);
        // Plan 标识出现在会话配置左侧。
        expect(
          tester.getTopLeft(planBadge).dx,
          lessThan(tester.getTopLeft(sessionSelector).dx),
        );

        // 点击整颗 Plan Chip 恢复 Default（无尾部关闭按钮）。
        expect(
          find.descendant(
            of: planBadge,
            matching: find.byIcon(Icons.close_rounded),
          ),
          findsNothing,
        );
        await tester.tap(planBadge);
        await pumpUntilFinderAbsent(tester, planBadge);
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.defaultMode,
        );
        expect(planBadge, findsNothing);
        expect(selectionNotifications, 2);
        provider.emitEvent(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-mode',
            turnId: 'turn-1',
          ),
        );
        await tester.pump();
      },
    );

    testWidgets(
      'more actions opens above composer and Plan configures the next turn',
      (tester) async {
        final provider = AgentPaneModeFakeProvider(
          models: agentPaneModelConfigList,
        );
        final viewModel = createAgentPaneViewModel(
          provider,
          initialThread: agentPaneThread(
            id: 'thread-more-actions',
            title: 'More actions thread',
          ),
        );
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.initialization;
        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-more-actions-button')),
        );

        final moreActionsButton = find.byKey(
          const ValueKey('agent-more-actions-button'),
        );
        final planBadge = find.byKey(
          const ValueKey('agent-composer-plan-badge'),
        );
        expect(moreActionsButton, findsOneWidget);
        expect(find.byKey(const ValueKey('agent-mode-selector')), findsNothing);
        expect(planBadge, findsNothing);
        expect(
          find.byKey(const ValueKey('agent-mention-file-button')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('agent-attach-image-button')),
          findsNothing,
        );

        await tester.tap(moreActionsButton);
        await tester.pump(const Duration(milliseconds: 300));

        final popover = find.byKey(
          const ValueKey('agent-more-actions-popover'),
        );
        final planAction = find.byKey(
          const ValueKey('agent-more-actions-plan'),
        );
        expect(popover, findsOneWidget);
        expect(planAction, findsOneWidget);
        expect(
          find.byKey(const ValueKey('agent-mention-file-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('agent-attach-image-button')),
          findsOneWidget,
        );
        expect(
          tester.getRect(popover).bottom,
          lessThanOrEqualTo(tester.getRect(moreActionsButton).top),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await pumpUntilFinderAbsent(tester, popover);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'agent-more-actions-trigger',
        );

        await tester.tap(moreActionsButton);
        await tester.pump(const Duration(milliseconds: 300));
        expect(popover, findsOneWidget);

        await tester.tap(planAction);
        await pumpUntilFinderAbsent(tester, popover);
        await tester.pump();

        expect(popover, findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'agent-more-actions-trigger',
        );
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.plan,
        );
        expect(planBadge, findsOneWidget);

        // 再次通过更多操作 Plan 切换回 Default。
        await tester.tap(moreActionsButton);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(planAction);
        await pumpUntilFinderAbsent(tester, popover);
        await tester.pump();
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.defaultMode,
        );
        expect(planBadge, findsNothing);

        // 重新选 Plan 后再发送，确认 turn 配置仍走 Plan。
        await tester.tap(moreActionsButton);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(planAction);
        await pumpUntilFinderAbsent(tester, popover);
        await tester.pump();
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.plan,
        );

        await tester.enterText(
          find.byKey(const ValueKey('agent-message-input')),
          'Plan from more actions',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('agent-send-button')));
        await pumpUntilMessageSent(tester, provider);

        expect(
          provider.turnConfigurations.single.conversationMode!.modeId,
          AgentConversationModeId.plan,
        );
        provider.emitEvent(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-more-actions',
            turnId: 'turn-1',
          ),
        );
        await tester.pump();
      },
    );

    testWidgets('Mention file closes more actions before opening the picker', (
      tester,
    ) async {
      const mentionFile = WorkspaceNode(
        path: '/repo/lib/main.dart',
        name: 'main.dart',
        type: WorkspaceNodeType.file,
      );
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        workspaceFilesProvider: () => const <WorkspaceNode>[mentionFile],
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      await tester.tap(find.byKey(const ValueKey('agent-more-actions-button')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('agent-mention-file-button')));
      await pumpUntilFinder(
        tester,
        find.byKey(const ValueKey('agent-mention-option-/repo/lib/main.dart')),
      );

      expect(
        find.byKey(const ValueKey('agent-more-actions-popover')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('agent-mention-picker-overlay')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-mention-picker-popover')),
        findsOneWidget,
      );
    });

    testWidgets('typing @ opens inline mention picker and lists candidates', (
      tester,
    ) async {
      const mentionFile = WorkspaceNode(
        path: '/repo/lib/main.dart',
        name: 'main.dart',
        type: WorkspaceNodeType.file,
      );
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        workspaceFilesProvider: () => const <WorkspaceNode>[mentionFile],
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      final input = find.byKey(const ValueKey('agent-message-input'));
      await tester.enterText(input, '@');

      await pumpUntilFinder(
        tester,
        find.byKey(const ValueKey('agent-mention-picker-overlay')),
      );
      expect(
        find.byKey(const ValueKey('agent-mention-option-/repo/lib/main.dart')),
        findsOneWidget,
      );
    });

    testWidgets('mention picker accepts highlighted file via arrow + enter', (
      tester,
    ) async {
      const mainFile = WorkspaceNode(
        path: '/repo/lib/main.dart',
        name: 'main.dart',
        type: WorkspaceNodeType.file,
      );
      const helperFile = WorkspaceNode(
        path: '/repo/lib/helper.dart',
        name: 'helper.dart',
        type: WorkspaceNodeType.file,
      );
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        workspaceFilesProvider: () => const <WorkspaceNode>[
          helperFile,
          mainFile,
        ],
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      final input = find.byKey(const ValueKey('agent-message-input'));
      await tester.enterText(input, '@ma');

      await pumpUntilFinder(
        tester,
        find.byKey(const ValueKey('agent-mention-option-/repo/lib/main.dart')),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpUntilFinderAbsent(
        tester,
        find.byKey(const ValueKey('agent-mention-picker-overlay')),
      );

      // 接受后渲染为原子 mention chip（label 为 @name）。
      expect(find.text('@main.dart'), findsOneWidget);
    });

    testWidgets('escape dismisses mention picker without inserting', (
      tester,
    ) async {
      const mentionFile = WorkspaceNode(
        path: '/repo/lib/main.dart',
        name: 'main.dart',
        type: WorkspaceNodeType.file,
      );
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        workspaceFilesProvider: () => const <WorkspaceNode>[mentionFile],
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      final input = find.byKey(const ValueKey('agent-message-input'));
      await tester.enterText(input, '@ma');

      await pumpUntilFinder(
        tester,
        find.byKey(const ValueKey('agent-mention-picker-overlay')),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpUntilFinderAbsent(
        tester,
        find.byKey(const ValueKey('agent-mention-picker-overlay')),
      );

      final editable = tester.widget<EditableText>(
        find.descendant(of: input, matching: find.byType(EditableText)),
      );
      expect(editable.controller.text, '@ma');
    });

    testWidgets(
      'mention picker shows indexing empty state then refreshes on ready',
      (tester) async {
        const mentionFile = WorkspaceNode(
          path: '/repo/lib/main.dart',
          name: 'main.dart',
          type: WorkspaceNodeType.file,
        );
        final corpus = <WorkspaceNode>[];
        var indexReady = false;
        final filesListenable = ChangeNotifier();
        addTearDown(filesListenable.dispose);

        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(
          provider,
          workspaceFilesProvider: () => List<WorkspaceNode>.of(corpus),
          workspaceFilesListenable: filesListenable,
          workspaceFilesIndexReady: () => indexReady,
        );
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);

        final input = find.byKey(const ValueKey('agent-message-input'));
        await tester.enterText(input, '@');

        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-mention-picker-popover')),
        );
        expect(find.text('Indexing workspace…'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey('agent-mention-option-/repo/lib/main.dart'),
          ),
          findsNothing,
        );

        // 后台索引完成后通知：打开中的 picker 应刷新候选。
        corpus.add(mentionFile);
        indexReady = true;
        filesListenable.notifyListeners();
        await tester.pump();

        expect(find.text('Indexing workspace…'), findsNothing);
        expect(
          find.byKey(
            const ValueKey('agent-mention-option-/repo/lib/main.dart'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'completed Plan shows local handoff and Run plan starts Default turn',
      (tester) async {
        final provider = AgentPaneModeFakeProvider(
          models: agentPaneModelConfigList,
        );
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);

        viewModel.selectConversationMode(AgentConversationModeId.plan);
        await viewModel.sendMessage('plan this change');
        provider.emitEvent(
          const AgentMessageDeltaEvent(
            messageId: 'plan-final',
            delta: '# Final plan\n\n- Implement the change',
            role: AgentMessageRole.agent,
            kind: AgentMessageKind.plan,
            status: AgentMessageStatus.completed,
            sessionId: 'session-1',
            turnId: 'turn-1',
          ),
        );
        provider.emitEvent(
          const AgentTurnCompletedEvent(
            sessionId: 'session-1',
            turnId: 'turn-1',
          ),
        );

        const startKey = ValueKey<String>(
          'agent-plan-execute-plan-execution:session-1:turn-1',
        );
        await pumpUntilFinder(tester, find.byKey(startKey));

        expect(find.text('计划就绪'), findsOneWidget);
        expect(find.text('修改'), findsOneWidget);
        expect(find.text('执行'), findsOneWidget);
        expect(find.text('放弃'), findsOneWidget);
        expect(find.byKey(startKey), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey(
              'agent-plan-revision-input-'
              'plan-execution:session-1:turn-1',
            ),
          ),
          findsOneWidget,
        );
        // 计划卡在对话流内渲染，而不是 Composer 上方的 pending dock。
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('agent-message-list')),
            matching: find.byKey(startKey),
          ),
          findsOneWidget,
        );
        // 计划待处理时隐藏主 Composer。
        expect(find.byKey(const ValueKey('agent-message-input')), findsNothing);

        await tester.tap(find.byKey(startKey));
        await pumpLiveAgentUi(tester);

        expect(viewModel.planExecutionRequest, isNull);
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.defaultMode,
        );
        expect(
          provider.sentMessages,
          contains(AgentConversationViewModel.planExecutionPrompt),
        );
        expect(
          provider.turnConfigurations.last.conversationMode!.modeId,
          AgentConversationModeId.defaultMode,
        );
        // Fake 每次 sendMessage 递增 turn id：Plan 为 turn-1，执行回合为 turn-2。
        // 必须结束 live 执行回合，否则 elapsed ticker 会在 dispose 后仍 pending。
        provider.emitEvent(
          const AgentTurnCompletedEvent(
            sessionId: 'session-1',
            turnId: 'turn-2',
          ),
        );
        await pumpLiveAgentUi(tester);
      },
    );

    testWidgets(
      'unsupported provider keeps composer free of mode placeholders',
      (tester) async {
        final provider = AgentPaneFakeProvider(
          models: agentPaneModelConfigList,
        );
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);

        expect(find.byKey(const ValueKey('agent-mode-selector')), findsNothing);
        expect(
          find.byKey(const ValueKey('agent-model-selector')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('agent-permission-option-selector')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'composer toolbar stays on one line without scrolling in narrow windows',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 560);
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final provider = AgentPaneModeFakeProvider(
          models: agentPaneModelConfigList,
        );
        final viewModel = createAgentPaneViewModel(
          provider,
          initialThread: agentPaneThread(
            id: 'thread-narrow-mode',
            title: 'Narrow mode thread',
          ),
        );
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.initialization;
        await viewModel.sendMessage('bind session runtime');
        provider.emitEvent(
          const AgentSessionConfigUpdatedEvent(
            sessionId: 'thread-narrow-mode',
            options: <AgentSessionConfigOption>[
              AgentSessionConfigOption(
                id: 'cursor-model',
                name: 'Session model',
                category: 'model',
                kind: AgentSessionConfigOptionKind.select,
                currentValue: 'fast',
                values: <AgentSessionConfigValue>[
                  AgentSessionConfigValue(id: 'fast', label: 'Fast'),
                ],
              ),
            ],
          ),
        );
        provider.emitEvent(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-narrow-mode',
            turnId: 'turn-1',
          ),
        );
        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-session-config-cursor-model')),
        );
        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-more-actions-button')),
        );

        final moreActionsButton = find.byKey(
          const ValueKey('agent-more-actions-button'),
        );
        final selectors = find.byKey(
          const ValueKey('agent-composer-selectors'),
        );
        final toolbar = find.byKey(const ValueKey('agent-composer-toolbar'));
        final sendButton = find.byKey(const ValueKey('agent-send-button'));
        final modelSelector = find.byKey(
          const ValueKey('agent-model-selector'),
        );
        // Default 不展示模式控件；选 Plan 后再校验标识参与左侧区。
        expect(find.byKey(const ValueKey('agent-mode-selector')), findsNothing);
        expect(
          find.byKey(const ValueKey('agent-composer-plan-badge')),
          findsNothing,
        );
        await tester.tap(moreActionsButton);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('agent-more-actions-plan')));
        final planBadge = find.byKey(
          const ValueKey('agent-composer-plan-badge'),
        );
        await pumpUntilFinder(tester, planBadge);
        // 仅左侧可裁切区；模型选择器在工具栏右侧，不参与 clip 组。
        final selectorControls = <Finder>[
          planBadge,
          find.byKey(const ValueKey('agent-session-config-cursor-model')),
          find.byKey(const ValueKey('agent-permission-option-selector')),
        ];
        final wideSelectorsLeft = tester.getTopLeft(selectors).dx;
        final wideOffsets = <double>[
          for (final control in selectorControls)
            tester.getTopLeft(control).dx - wideSelectorsLeft,
        ];
        final wideWidths = <double>[
          for (final control in selectorControls) tester.getSize(control).width,
        ];

        tester.view.physicalSize = const Size(360, 560);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const ValueKey('agent-composer-compact-toolbar')),
          findsNothing,
        );
        expect(toolbar, findsOneWidget);
        expect(moreActionsButton, findsOneWidget);
        expect(selectors, findsOneWidget);
        expect(modelSelector, findsOneWidget);
        expect(sendButton, findsOneWidget);
        expect(
          find.byKey(const ValueKey('agent-composer-selector-scroll')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: selectors,
            matching: find.byKey(const ValueKey('agent-composer-plan-badge')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: selectors, matching: modelSelector),
          findsNothing,
        );
        expect(
          find.descendant(of: selectors, matching: moreActionsButton),
          findsNothing,
        );
        expect(
          find.descendant(of: selectors, matching: find.byType(Scrollable)),
          findsNothing,
        );
        expect(
          find.descendant(of: selectors, matching: find.byType(Flexible)),
          findsNothing,
        );
        expect(
          find.descendant(of: selectors, matching: find.byType(OverflowBox)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: toolbar, matching: moreActionsButton),
          findsOneWidget,
        );
        expect(
          find.descendant(of: toolbar, matching: selectors),
          findsOneWidget,
        );
        expect(
          find.descendant(of: toolbar, matching: modelSelector),
          findsOneWidget,
        );
        expect(
          find.descendant(of: toolbar, matching: sendButton),
          findsOneWidget,
        );
        final toolbarCenterY = tester.getCenter(toolbar).dy;
        expect(
          tester.getCenter(moreActionsButton).dy,
          moreOrLessEquals(toolbarCenterY, epsilon: 0.5),
        );
        expect(
          tester.getCenter(selectors).dy,
          moreOrLessEquals(toolbarCenterY, epsilon: 0.5),
        );
        expect(
          tester.getCenter(modelSelector).dy,
          moreOrLessEquals(toolbarCenterY, epsilon: 0.5),
        );
        expect(
          tester.getCenter(sendButton).dy,
          moreOrLessEquals(toolbarCenterY, epsilon: 0.5),
        );
        // 模型选择器在左侧选择器之后、发送按钮之前。
        expect(
          tester.getTopLeft(modelSelector).dx,
          greaterThan(tester.getTopLeft(selectors).dx),
        );
        expect(
          tester.getTopLeft(modelSelector).dx,
          lessThan(tester.getTopLeft(sendButton).dx),
        );
        final narrowSelectorsLeft = tester.getTopLeft(selectors).dx;
        for (var index = 0; index < selectorControls.length; index++) {
          expect(
            tester.getTopLeft(selectorControls[index]).dx - narrowSelectorsLeft,
            moreOrLessEquals(wideOffsets[index], epsilon: 0.5),
          );
          expect(
            tester.getSize(selectorControls[index]).width,
            moreOrLessEquals(wideWidths[index], epsilon: 0.5),
          );
        }
        await tester.tap(moreActionsButton);
        await tester.pump(const Duration(milliseconds: 300));
        final moreActionsPopover = find.byKey(
          const ValueKey('agent-more-actions-popover'),
        );
        final popoverRect = tester.getRect(moreActionsPopover);
        expect(popoverRect.left, greaterThanOrEqualTo(IdeSpacing.space12));
        expect(
          popoverRect.right,
          lessThanOrEqualTo(
            tester.view.physicalSize.width - IdeSpacing.space12,
          ),
        );
        expect(
          popoverRect.bottom,
          lessThanOrEqualTo(tester.getRect(moreActionsButton).top),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await pumpUntilFinderAbsent(tester, moreActionsPopover);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'permission policy matches model selector style and updates selection',
      (tester) async {
        final provider = AgentPaneFakeProvider(
          models: agentPaneModelConfigList,
        );
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);

        final modelSelector = find.byKey(
          const ValueKey('agent-model-selector'),
        );
        final permissionSelector = find.byKey(
          const ValueKey('agent-permission-option-selector'),
        );
        final modelSurface = tester.widget<PaneInteractiveSurface>(
          modelSelector,
        );
        final permissionSurface = tester.widget<PaneInteractiveSurface>(
          permissionSelector,
        );
        expect(permissionSurface.height, modelSurface.height);
        expect(permissionSurface.borderRadius, modelSurface.borderRadius);
        expect(permissionSurface.backgroundColor, modelSurface.backgroundColor);
        expect(permissionSurface.borderColor, modelSurface.borderColor);
        // 触发器短标签契约：option label，不含审批副标题。
        expect(find.text('Workspace write'), findsOneWidget);
        expect(viewModel.permissionPolicyLabel, 'Workspace write');
        expect(viewModel.permissionPolicyLabel, isNot(contains('Ask first')));

        await tester.tap(permissionSelector);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final popover = find.byKey(
          const ValueKey('agent-permission-option-popover'),
        );
        expect(popover, findsOneWidget);
        expect(tester.getSize(popover).width, 288);
        // 方案 B：弹层不再叠加 PanelCard 外层，由 shadcn SelectPopup 自带卡
        // 作为唯一表面，避免「两层」视觉。
        expect(
          find.descendant(of: popover, matching: find.byType(PanelCard)),
          findsNothing,
        );
        expect(
          find.byType(sf.SelectPopup<AgentPermissionOption>),
          findsOneWidget,
        );
        final selectedOption = tester
            .widget<sf.SelectItemButton<AgentPermissionOption>>(
              find.byKey(const ValueKey('agent-permission-option-:workspace')),
            );
        expect(selectedOption.value.id, ':workspace');
        expect(selectedOption.enabled, isNull);
        expect(
          find.descendant(
            of: find.byKey(
              const ValueKey('agent-permission-option-:workspace'),
            ),
            matching: find.text('Workspace write'),
          ),
          findsWidgets,
        );
        // popover 选项仅短 label，不渲染审批副标题。
        expect(find.text('Ask first'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('agent-permission-option-:read-only')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 3));

        expect(viewModel.permissionSelection?.optionId, ':read-only');
        // Dormant Binding 只更新会话状态和默认值，不为权限变更启动 runtime。
        expect(provider.lastAppliedPermissionOptionId, isNull);
        expect(popover, findsNothing);
        expect(find.text('Read only'), findsOneWidget);
        expect(viewModel.permissionPolicyLabel, 'Read only');
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'agent-permission-option-trigger',
        );

        await tester.tap(permissionSelector);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(popover, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(popover, findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'agent-permission-option-trigger',
        );
      },
    );

    testWidgets('permission policy is disabled while a turn is running', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(models: agentPaneModelConfigList);
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      await viewModel.sendMessage('keep the turn running');
      await tester.pump();
      expect(viewModel.isTurnRunning, isTrue);

      final permissionSelector = find.byKey(
        const ValueKey('agent-permission-option-selector'),
      );
      await tester.tap(permissionSelector);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('agent-permission-option-popover')),
        findsNothing,
      );

      final error = await viewModel.selectPermissionOption(
        agentPaneDefaultPermissionOptions.last,
      );
      expect(error, contains('当前回合执行中'));
      expect(provider.permissionApplyCount, 0);

      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();
    });

    testWidgets(
      'renders dynamic session config options and sends stable values',
      (tester) async {
        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(
          provider,
          initialThread: agentPaneThread(
            id: 'thread-config',
            title: 'Config thread',
          ),
        );
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.loadModels();
        await viewModel.initialization;
        await viewModel.sendMessage('bind session runtime');
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
        provider.emitEvent(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-config',
            turnId: 'turn-1',
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
        expect(find.byType(sf.SelectPopup<Object>), findsOneWidget);
        await tester.tap(
          find.byKey(
            const ValueKey('agent-session-config-cursor-model-option-smart'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(provider.sessionConfigSelections, <(String, String, Object)>[
          ('thread-config', 'cursor-model', 'smart'),
        ]);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'agent-session-selector-trigger',
        );

        await tester.tap(
          find.byKey(const ValueKey('agent-session-config-cursor-model')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.byType(sf.SelectPopup<Object>), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.byType(sf.SelectPopup<Object>), findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'agent-session-selector-trigger',
        );
      },
    );

    testWidgets('draft image remove button clears the thumbnail strip', (
      tester,
    ) async {
      final paneKey = GlobalKey();
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(id: 'thread-draft-image', title: 'Img'),
      );
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        AgentPaneTestApp(viewModel: viewModel, agentPaneKey: paneKey),
      );
      await viewModel.initialization;
      await pumpAgentPaneUi(tester);
      expect(
        find.byKey(const ValueKey('agent-composer-section')),
        findsOneWidget,
      );
      expect(paneKey.currentState, isNotNull);

      const draftPath = r'D:\tmp\zeta-draft-image.png';
      AgentPane.debugAddDraftImages(paneKey, const <String>[draftPath]);
      expect(AgentPane.debugDraftImagePaths(paneKey), <String>[draftPath]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(AgentPane.debugDraftImagePaths(paneKey), <String>[draftPath]);

      final draftStrip = find.byKey(
        const ValueKey('agent-composer-image-drafts'),
      );
      final removeButton = find.byKey(
        ValueKey<String>('agent-composer-remove-image-$draftPath'),
      );
      expect(draftStrip, findsOneWidget);
      expect(removeButton, findsOneWidget);

      await tester.ensureVisible(removeButton);
      await tester.tap(removeButton, warnIfMissed: true);
      await tester.pump();

      expect(draftStrip, findsNothing);
      expect(removeButton, findsNothing);
    });
  });
}
