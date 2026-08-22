import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_static_capabilities.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'harness/agent_pane_test_harness.dart';

void main() {
  group('AgentPane model config', () {
    testWidgets('first catalog failure shows an explicit model error', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(
        modelListError: StateError('sensitive provider failure'),
      );
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      expect(viewModel.models, isEmpty);
      expect(viewModel.modelConfigUiState.refreshError, '模型列表刷新失败，已保留现有配置。');
      expect(find.text('模型加载失败'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('agent-model-refresh-error')),
        findsOneWidget,
      );
      final selector = find.byKey(const ValueKey('agent-model-selector'));
      expect(selector, findsOneWidget);
      final tooltip = find.ancestor(
        of: selector,
        matching: find.byType(IdeTooltip),
      );
      expect(tester.widget<IdeTooltip>(tooltip).message, contains('模型列表刷新失败'));
      expect(
        tester.widget<IdeTooltip>(tooltip).message,
        isNot(contains('sensitive provider failure')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('model config expands inline and keeps popover open', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(models: agentPaneModelConfigList);
      final viewModel = createAgentPaneViewModel(provider);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      expect(
        find.byKey(const ValueKey('agent-model-selector')),
        findsOneWidget,
      );
      final modelSelector = find.byKey(const ValueKey('agent-model-selector'));
      final selectorSurface = tester.widget<PaneInteractiveSurface>(
        modelSelector,
      );
      // effort 直接展示协议原值（如 medium），比中文单字略宽。
      expect(tester.getSize(modelSelector).width, lessThan(240));
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

      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );

      final popover = find.byKey(const ValueKey('agent-model-config-popover'));
      expect(tester.getSize(popover).width, 288);
      final popoverRect = tester.getRect(popover);
      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(popoverRect.height, greaterThan(0));
      expect(popoverRect.top, greaterThanOrEqualTo(0));
      expect(popoverRect.bottom, lessThanOrEqualTo(viewportHeight));
      final popoverPanel = find.descendant(
        of: popover,
        matching: find.byType(PanelCard),
      );
      final modelPopoverPanel = tester.widget<PanelCard>(popoverPanel.first);
      final colors = IdeColors.of(tester.element(modelSelector));
      expect(modelPopoverPanel.color, colors.surfaceElevated);
      expect(modelPopoverPanel.borderRadius, IdeRadius.allSmall);
      expect(modelPopoverPanel.boxShadow, isEmpty);
      final openSelectorSurface = tester.widget<PaneInteractiveSurface>(
        modelSelector,
      );
      expect(openSelectorSurface.selected, isTrue);
      expect(
        openSelectorSurface.selectedBackgroundColor,
        colors.frame.withValues(alpha: 0.72),
      );
      expect(openSelectorSurface.selectedBorderColor, isNull);
      expect(
        find.descendant(of: modelSelector, matching: find.byType(Stack)),
        findsNothing,
      );
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
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-reasoning-segment-control')),
        findsOneWidget,
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
      await tester.pump(const Duration(milliseconds: 300));
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

      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );
      expect(viewModel.selectedModelId, 'gpt-5.4-mini');
      expect(
        find.byKey(const ValueKey('agent-model-config-popover')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-model-inline-config-gpt-5.4-mini')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('Claude effort catalog renders reasoning options', (
      tester,
    ) async {
      final provider = _ClaudeEffortModelProvider();
      final viewModel = createAgentPaneViewModelWithStore(
        provider,
        MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[
              AgentProviderConfig.defaultClaudeCode,
            ],
            activeProviderId: defaultClaudeCodeProviderId,
          ),
        ),
      );
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      expect(viewModel.modelConfigUiState.supportsReasoningOptions, isTrue);
      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );

      expect(find.text('该模型未提供可配置的思考程度'), findsNothing);
      expect(
        find.byKey(const ValueKey('agent-reasoning-segment-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-reasoning-option-low')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-reasoning-option-max')),
        findsOneWidget,
      );
    });

    testWidgets(
      'reasoning slider previews continuously and commits once on release',
      (tester) async {
        final provider = AgentPaneFakeProvider(
          models: agentPaneModelConfigList,
        );
        final store = RecordingAgentProviderConfigStore();
        final viewModel = createAgentPaneViewModelWithStore(provider, store);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);

        await tapAndWaitForFinder(
          tester,
          find.byKey(const ValueKey('agent-model-selector')),
          find.byKey(const ValueKey('agent-model-config-popover')),
        );
        await tester.tap(
          find.byKey(const ValueKey('agent-model-option-gpt-5.4-mini')),
        );
        await tester.pump(const Duration(milliseconds: 500));

        expect(viewModel.selectedReasoningEffort, 'low');
        final miniConfig = find.byKey(
          const ValueKey('agent-model-inline-config-gpt-5.4-mini'),
        );
        final track = find.descendant(
          of: miniConfig,
          matching: find.byKey(const ValueKey('agent-reasoning-slider-track')),
        );
        final popover = find.byKey(
          const ValueKey('agent-model-config-popover'),
        );
        final popoverScrollable = find
            .descendant(of: popover, matching: find.byType(Scrollable))
            .first;
        await tester.scrollUntilVisible(
          track,
          80,
          scrollable: popoverScrollable,
        );
        await tester.pump(const Duration(milliseconds: 200));
        final trackRect = tester.getRect(track);
        final popoverRect = tester.getRect(popover);
        expect(
          track.hitTestable(),
          findsOneWidget,
          reason: 'track=$trackRect, popover=$popoverRect',
        );
        expect(trackRect.width, greaterThan(100));
        final thumb = find.descendant(
          of: miniConfig,
          matching: find.byKey(const ValueKey('agent-reasoning-slider-thumb')),
        );
        final initialThumbRect = tester.getRect(thumb);
        final topInset = initialThumbRect.top - trackRect.top;
        final bottomInset = trackRect.bottom - initialThumbRect.bottom;
        final leftInset = initialThumbRect.left - trackRect.left;
        expect(topInset, closeTo(bottomInset, 0.01));
        expect(leftInset, closeTo(topInset, 0.01));
        final optionMarkers = find.descendant(
          of: miniConfig,
          matching: find.byKey(
            const ValueKey('agent-reasoning-option-markers'),
          ),
        );
        expect(optionMarkers, findsNothing);
        final saveCountBeforeDrag = store.saveCount;
        final dragStart = Offset(trackRect.left + 14, trackRect.center.dy);
        final dragEnd = Offset(trackRect.right - 14, trackRect.center.dy);
        final gesture = await tester.startGesture(dragStart);
        await tester.pump();
        expect(optionMarkers, findsOneWidget);
        for (var step = 1; step <= 6; step += 1) {
          await gesture.moveTo(
            Offset.lerp(dragStart, dragEnd, step / 6)!,
            timeStamp: Duration(milliseconds: step * 16),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: miniConfig,
                  matching: find.byKey(
                    const ValueKey('agent-reasoning-current-label'),
                  ),
                ),
              )
              .data,
          'xhigh',
        );
        expect(viewModel.selectedReasoningEffort, 'low');
        expect(store.saveCount, saveCountBeforeDrag);
        final flowAnimation = find.descendant(
          of: miniConfig,
          matching: find.byKey(
            const ValueKey('agent-reasoning-max-flow-animation'),
          ),
        );
        final impactAnimation = find.descendant(
          of: miniConfig,
          matching: find.byKey(
            const ValueKey('agent-reasoning-max-impact-animation'),
          ),
        );
        final flowController =
            tester.widget<AnimatedBuilder>(flowAnimation).animation
                as AnimationController;
        final impactController =
            tester.widget<AnimatedBuilder>(impactAnimation).animation
                as AnimationController;
        expect(flowController.isAnimating, isTrue);
        expect(impactController.isAnimating, isTrue);
        expect(impactController.value, inExclusiveRange(0, 1));

        await gesture.up();
        await tester.pump(const Duration(milliseconds: 500));

        expect(optionMarkers, findsNothing);
        expect(viewModel.selectedReasoningEffort, 'xhigh');
        expect(store.saveCount, saveCountBeforeDrag + 1);
        final maximumThumbRect = tester.getRect(thumb);
        final rightInset = trackRect.right - maximumThumbRect.right;
        expect(rightInset, closeTo(topInset, 0.01));
        expect(maximumThumbRect.top - trackRect.top, closeTo(topInset, 0.01));
        expect(
          trackRect.bottom - maximumThumbRect.bottom,
          closeTo(topInset, 0.01),
        );
        final maxEffect = find.descendant(
          of: miniConfig,
          matching: find.byKey(const ValueKey('agent-reasoning-max-effect')),
        );
        final currentLabel = find.descendant(
          of: miniConfig,
          matching: find.byKey(const ValueKey('agent-reasoning-current-label')),
        );
        expect(tester.widget<AnimatedOpacity>(maxEffect).opacity, 1);
        expect(flowController.isAnimating, isTrue);
        expect(impactController.isAnimating, isFalse);
        expect(impactController.value, 1);
        final labelStyle = tester.widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: currentLabel,
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        );
        expect(
          labelStyle.style.color,
          IdeColors.of(tester.element(currentLabel)).intelligenceAccent,
        );
        expect(
          find.byKey(const ValueKey('agent-model-config-popover')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'reasoning slider exposes semantics and keeps max effect static '
      'when motion is reduced',
      (tester) async {
        final provider = AgentPaneFakeProvider(
          models: agentPaneModelConfigList,
        );
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(
          AgentPaneTestApp(viewModel: viewModel, disableAnimations: true),
        );
        await pumpAgentPaneUi(tester);

        await tapAndWaitForFinder(
          tester,
          find.byKey(const ValueKey('agent-model-selector')),
          find.byKey(const ValueKey('agent-model-config-popover')),
        );
        await tester.tap(
          find.byKey(const ValueKey('agent-model-option-gpt-5.5')),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final selectedConfig = find.byKey(
          const ValueKey('agent-model-inline-config-gpt-5.5'),
        );
        final slider = find.descendant(
          of: selectedConfig,
          matching: find.byKey(
            const ValueKey('agent-reasoning-segment-control'),
          ),
        );
        final semantics = tester.getSemantics(slider);
        expect(semantics.label, '思考程度');
        expect(semantics.value, 'medium');
        final sliderSemantics = find.semantics.byLabel('思考程度');
        tester.semantics.increase(sliderSemantics);
        await tester.pump();
        expect(viewModel.selectedReasoningEffort, 'high');
        tester.semantics.increase(sliderSemantics);
        await tester.pump();

        expect(viewModel.selectedReasoningEffort, 'xhigh');
        final maxEffect = find.descendant(
          of: selectedConfig,
          matching: find.byKey(const ValueKey('agent-reasoning-max-effect')),
        );
        expect(tester.widget<AnimatedOpacity>(maxEffect).opacity, 1);
        final flowAnimation = find.descendant(
          of: maxEffect,
          matching: find.byKey(
            const ValueKey('agent-reasoning-max-flow-animation'),
          ),
        );
        final flowController =
            tester.widget<AnimatedBuilder>(flowAnimation).animation
                as AnimationController;
        final impactAnimation = find.descendant(
          of: maxEffect,
          matching: find.byKey(
            const ValueKey('agent-reasoning-max-impact-animation'),
          ),
        );
        final impactController =
            tester.widget<AnimatedBuilder>(impactAnimation).animation
                as AnimationController;
        expect(flowController.isAnimating, isFalse);
        expect(flowController.value, closeTo(0.45, 0.001));
        expect(impactController.isAnimating, isFalse);
        expect(impactController.value, 1);

        tester.semantics.decrease(sliderSemantics);
        await tester.pump();
        expect(viewModel.selectedReasoningEffort, 'high');
        expect(tester.widget<AnimatedOpacity>(maxEffect).opacity, 0);
        expect(flowController.value, 0);
        expect(impactController.value, 0);
      },
    );

    testWidgets('single reasoning effort stays fixed without max effect', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(
        models: agentPaneSingleReasoningModelList,
      );
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );
      await tester.tap(
        find.byKey(const ValueKey('agent-model-option-solo-reasoning')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final selectedConfig = find.byKey(
        const ValueKey('agent-model-inline-config-solo-reasoning'),
      );
      final slider = find.descendant(
        of: selectedConfig,
        matching: find.byKey(const ValueKey('agent-reasoning-segment-control')),
      );
      final semantics = tester.getSemantics(slider).getSemanticsData();
      expect(semantics.value, 'balanced');
      expect(semantics.hasAction(SemanticsAction.increase), isFalse);
      expect(semantics.hasAction(SemanticsAction.decrease), isFalse);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: selectedConfig,
                matching: find.byKey(
                  const ValueKey('agent-reasoning-max-effect'),
                ),
              ),
            )
            .opacity,
        0,
      );

      final track = find.descendant(
        of: selectedConfig,
        matching: find.byKey(const ValueKey('agent-reasoning-slider-track')),
      );
      await tester.tap(track);
      await tester.pump();
      expect(viewModel.selectedReasoningEffort, 'balanced');
    });

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
            agentPaneModelConfigList.models.first,
            for (var index = 1; index <= 14; index++)
              AgentModelInfo(
                id: 'model-$index',
                model: 'model-$index',
                displayName: 'Model $index',
              ),
          ],
        );
        final provider = AgentPaneFakeProvider(models: models);
        final viewModel = createAgentPaneViewModel(provider);
        addTearDown(viewModel.dispose);
        await viewModel.loadModels();
        await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
        await pumpAgentPaneUi(tester);
        expect(
          MediaQuery.sizeOf(
            tester.element(find.byKey(const ValueKey('agent-model-selector'))),
          ).width,
          280,
        );

        await tapAndWaitForFinder(
          tester,
          find.byKey(const ValueKey('agent-model-selector')),
          find.byKey(const ValueKey('agent-model-config-popover')),
        );
        // 浮层首帧可能仍在定位动画中，再推进一帧再量几何。
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
      final provider = AgentPaneFakeProvider(models: agentPaneModelConfigList);
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

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
      final provider = AgentPaneFakeProvider(models: agentPaneModelConfigList);
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );
      await tester.tap(
        find.byKey(const ValueKey('agent-model-option-gpt-5.5')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final xhighOption = find.byKey(
        const ValueKey('agent-reasoning-option-xhigh'),
      );
      await tester.ensureVisible(xhighOption);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(xhighOption);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('agent-fast-switch-gpt-5.5')));
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
        const ValueKey('agent-model-alert-切换到 high 并开启 Fast'),
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

    testWidgets('model config supports keyboard model and effort navigation', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(models: agentPaneModelConfigList);
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));

      expect(viewModel.selectedModelId, 'gpt-5.4-mini');
      expect(
        find.byKey(const ValueKey('agent-model-inline-config-gpt-5.4-mini')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 300));
      expect(viewModel.selectedReasoningEffort, 'high');
    });

    testWidgets('model config rolls back failed save and retries inline', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(models: agentPaneModelConfigList);
      final initialPreference = AgentModelPreference(
        modelId: 'gpt-5.5',
        reasoningEffort: 'medium',
        fastEnabled: false,
        serviceTierId: null,
        updatedAt: DateTime.utc(2026, 7, 15),
      );
      final store = ToggleFailAgentProviderConfigStore(
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
          ],
        ),
      );
      final viewModel = createAgentPaneViewModelWithStore(provider, store);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );
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

    testWidgets('model config shows next-turn banner while a turn is running', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(models: agentPaneModelConfigList);
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await viewModel.sendMessage('Keep working');
      await pumpLiveAgentUi(tester);

      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );

      expect(
        find.byKey(const ValueKey('agent-model-next-turn-banner')),
        findsOneWidget,
      );
      expect(find.text('配置将在下一回合生效'), findsOneWidget);
      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();
    });

    testWidgets('model config reports an automatic fallback once', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(models: agentPaneModelConfigList);
      final store = MemoryAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex.copyWith(
              selectedModel: 'retired-model',
              selectedReasoningEffort: 'medium',
            ),
            AgentProviderConfig.defaultGrok,
          ],
        ),
      );
      final viewModel = createAgentPaneViewModelWithStore(provider, store);
      addTearDown(viewModel.dispose);
      await viewModel.loadModels();
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      expect(viewModel.selectedModelId, 'gpt-5.5');
      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );
      expect(
        find.byKey(const ValueKey('agent-model-auto-switch-notice')),
        findsOneWidget,
      );
      expect(find.textContaining('retired-model'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpUntilFinderAbsent(
        tester,
        find.byKey(const ValueKey('agent-model-config-popover')),
      );
      await tapAndWaitForFinder(
        tester,
        find.byKey(const ValueKey('agent-model-selector')),
        find.byKey(const ValueKey('agent-model-config-popover')),
      );
      expect(
        find.byKey(const ValueKey('agent-model-auto-switch-notice')),
        findsNothing,
      );
    });
  });
}

final class _ClaudeEffortModelProvider extends AgentPaneFakeProvider {
  _ClaudeEffortModelProvider()
    : super(
        models: const AgentModelList(
          models: <AgentModelInfo>[
            AgentModelInfo(
              id: 'opus',
              model: 'opus',
              displayName: 'Opus',
              supportedReasoningEfforts: <AgentModelReasoningEffort>[
                AgentModelReasoningEffort(effort: 'low'),
                AgentModelReasoningEffort(effort: 'medium'),
                AgentModelReasoningEffort(effort: 'high'),
                AgentModelReasoningEffort(effort: 'xhigh'),
                AgentModelReasoningEffort(effort: 'max'),
              ],
              isDefault: true,
            ),
          ],
        ),
      );

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultClaudeCode;

  @override
  AgentProviderCapabilities get capabilities =>
      AgentProviderStaticCapabilities.claudeCode;
}
