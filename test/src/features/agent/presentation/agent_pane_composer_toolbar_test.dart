import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

import 'harness/agent_pane_test_harness.dart';

void main() {
  group('AgentPane composer toolbar', () {
    testWidgets(
      'mode selector leads composer controls and dispatches one selection',
      (tester) async {
        final provider = AgentPaneModeFakeProvider(
          models: agentPaneModelConfigList,
        );
        final modeController = AgentConversationModeController();
        final viewModel = createAgentPaneViewModel(
          provider,
          conversationModeController: modeController,
        );
        addTearDown(provider.dispose);
        addTearDown(modeController.dispose);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.switchThread(
          agentPaneThread(id: 'thread-mode', title: 'Mode thread'),
        );
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
          find.byKey(const ValueKey('agent-mode-selector')),
        );
        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-session-config-cursor-model')),
        );

        final modeSelector = find.byKey(const ValueKey('agent-mode-selector'));
        final sessionSelector = find.byKey(
          const ValueKey('agent-session-config-cursor-model'),
        );
        final modelSelector = find.byKey(
          const ValueKey('agent-model-selector'),
        );
        final permissionSelector = find.byKey(
          const ValueKey('agent-permission-policy-selector'),
        );
        expect(modeSelector, findsOneWidget);
        expect(sessionSelector, findsOneWidget);
        expect(modelSelector, findsOneWidget);
        expect(permissionSelector, findsOneWidget);
        // 左侧：模式 → 会话配置 → 审批；模型选择器固定在右侧。
        expect(
          tester.getTopLeft(modeSelector).dx,
          lessThan(tester.getTopLeft(sessionSelector).dx),
        );
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
        await tester.tap(modeSelector);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('agent-mode-option-plan')));
        await tester.pump();

        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.plan,
        );
        expect(selectionNotifications, 1);
      },
    );

    testWidgets(
      'more actions opens above composer and Plan configures the next turn',
      (tester) async {
        final provider = AgentPaneModeFakeProvider(
          models: agentPaneModelConfigList,
        );
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.switchThread(
          agentPaneThread(
            id: 'thread-more-actions',
            title: 'More actions thread',
          ),
        );
        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-mode-selector')),
        );

        final moreActionsButton = find.byKey(
          const ValueKey('agent-more-actions-button'),
        );
        expect(moreActionsButton, findsOneWidget);
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

        await pumpUntilFinder(tester, find.text('Run plan'));

        expect(find.text('Plan ready'), findsOneWidget);
        expect(find.text('Dismiss'), findsOneWidget);
        expect(find.text('Keep planning'), findsOneWidget);
        expect(find.text('Run plan'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey(
              'agent-plan-execution-start-'
              'plan-execution:session-1:turn-1',
            ),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Run plan'));
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
          find.byKey(const ValueKey('agent-permission-policy-selector')),
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
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.switchThread(
          agentPaneThread(
            id: 'thread-narrow-mode',
            title: 'Narrow mode thread',
          ),
        );
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
        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-mode-selector')),
        );
        await pumpUntilFinder(
          tester,
          find.byKey(const ValueKey('agent-session-config-cursor-model')),
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
        // 仅左侧可裁切区；模型选择器在工具栏右侧，不参与 clip 组。
        final selectorControls = <Finder>[
          find.byKey(const ValueKey('agent-mode-selector')),
          find.byKey(const ValueKey('agent-session-config-cursor-model')),
          find.byKey(const ValueKey('agent-permission-policy-selector')),
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
            matching: find.byKey(const ValueKey('agent-mode-selector')),
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
        expect(permissionSurface.backgroundColor, modelSurface.backgroundColor);
        expect(permissionSurface.borderColor, modelSurface.borderColor);
        expect(find.text('Workspace write'), findsOneWidget);

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
        expect(
          find.byType(sf.SelectPopup<AgentPermissionPreset>),
          findsOneWidget,
        );
        final selectedOption = tester
            .widget<sf.SelectItemButton<AgentPermissionPreset>>(
              find.byKey(const ValueKey('agent-permission-preset-workspace')),
            );
        expect(selectedOption.value.id, 'workspace');
        expect(selectedOption.enabled, isNull);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('agent-permission-preset-workspace')),
            matching: find.text('Ask first'),
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('agent-permission-preset-fullAccess')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(viewModel.permissionSelection.matchedPresetId, 'fullAccess');
        expect(popover, findsNothing);
        expect(find.text('Full access'), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'agent-permission-policy-trigger',
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
          'agent-permission-policy-trigger',
        );
      },
    );

    testWidgets(
      'renders dynamic session config options and sends stable values',
      (tester) async {
        final provider = AgentPaneFakeProvider();
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(provider.dispose);
        addTearDown(viewModel.dispose);
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await viewModel.loadModels();
        await viewModel.switchThread(
          agentPaneThread(id: 'thread-config', title: 'Config thread'),
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
  });
}
