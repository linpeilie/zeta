import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_binding.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'agent_conversation_ui_state_fixtures.dart';
import 'harness/agent_pane_test_harness.dart';

/// Phase 2 §8 验收表里与切片 UI 直接相关的几条。
void main() {
  group('Phase 2 切片验收', () {
    testWidgets('同一应用里两个会话的切片完全隔离', (tester) async {
      final first = createAgentPaneViewModel(
        AgentPaneFakeProvider(),
        initialThread: agentPaneThread(id: 'thread-1', title: '会话一'),
      );
      final second = createAgentPaneViewModel(
        AgentPaneFakeProvider(),
        initialThread: agentPaneThread(id: 'thread-2', title: '会话二'),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final firstBinding = AgentConversationSliceBinding(viewModel: first);
      final secondBinding = AgentConversationSliceBinding(viewModel: second);
      addTearDown(firstBinding.dispose);
      addTearDown(secondBinding.dispose);

      // 两个 Binding 身份必须不同，否则这条测试证明不了隔离。
      expect(
        first.conversationBinding.key,
        isNot(second.conversationBinding.key),
      );

      await tester.pumpWidget(
        _TwoPaneApp(
          first: first,
          second: second,
          stores: <AgentConversationBindingKey, AgentConversationSliceStore>{
            first.conversationBinding.key: firstBinding.store,
            second.conversationBinding.key: secondBinding.store,
          },
        ),
      );
      await pumpAgentPaneUi(tester);

      // 只推第一个会话的切片。
      firstBinding.store.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '只属于会话一'),
        ),
      );
      await pumpAgentPaneUi(tester);

      expect(find.text('只属于会话一'), findsOneWidget);
      expect(
        secondBinding.store.state.header.title,
        isNot('只属于会话一'),
        reason: '第二个会话的切片状态不得被串改',
      );
    });

    testWidgets('dispose 其中一个会话，另一个仍然工作', (tester) async {
      final first = createAgentPaneViewModel(
        AgentPaneFakeProvider(),
        initialThread: agentPaneThread(id: 'thread-1', title: '会话一'),
      );
      final second = createAgentPaneViewModel(
        AgentPaneFakeProvider(),
        initialThread: agentPaneThread(id: 'thread-2', title: '会话二'),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final firstBinding = AgentConversationSliceBinding(viewModel: first);
      final secondBinding = AgentConversationSliceBinding(viewModel: second);
      addTearDown(secondBinding.dispose);

      await tester.pumpWidget(
        _TwoPaneApp(
          first: first,
          second: second,
          stores: <AgentConversationBindingKey, AgentConversationSliceStore>{
            first.conversationBinding.key: firstBinding.store,
            second.conversationBinding.key: secondBinding.store,
          },
        ),
      );
      await pumpAgentPaneUi(tester);

      firstBinding.dispose();
      await pumpAgentPaneUi(tester);

      secondBinding.store.refreshRegions(
        AgentConversationRegionsRefreshed(
          header: agentHeaderStateFixture(title: '第二个仍在更新'),
        ),
      );
      await pumpAgentPaneUi(tester);

      expect(find.text('第二个仍在更新'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('切片重建不产生一次性 effect（effect 不进状态）', (tester) async {
      final viewModel = createAgentPaneViewModel(
        AgentPaneFakeProvider(),
        initialThread: agentPaneThread(id: 'thread-1', title: '会话一'),
      );
      addTearDown(viewModel.dispose);
      final binding = AgentConversationSliceBinding(viewModel: viewModel);
      addTearDown(binding.dispose);

      final received = <AgentUiEffect>[];
      final subscription = viewModel.uiEffects.listen(received.add);
      addTearDown(subscription.cancel);

      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          sliceStores:
              <AgentConversationBindingKey, AgentConversationSliceStore>{
                viewModel.conversationBinding.key: binding.store,
              },
        ),
      );
      await pumpAgentPaneUi(tester);
      received.clear();

      // 反复推切片、反复重建：一次性 effect 只走 stream，不进切片状态，
      // 因此重建既不会重放旧 effect，也不会凭空产生新的。
      for (var i = 0; i < 5; i += 1) {
        binding.store.refreshRegions(
          AgentConversationRegionsRefreshed(
            header: agentHeaderStateFixture(title: '重建 $i'),
          ),
        );
        await pumpAgentPaneUi(tester);
      }

      expect(find.text('重建 4'), findsOneWidget);
      expect(
        received,
        isEmpty,
        reason:
            '切片状态里若混进 effect，rebuild 就会重复触发滚动/导航。'
            '每个动作应产出哪些 effect 由 agent_conversation_view_model_test 断言。',
      );
    });
  });
}

/// 同一个 `ProviderScope` 下并排渲染两个会话。
///
/// 这是"两 thread 并存"验收的关键形状：**一个容器、两个 key**，而不是两个容器。
class _TwoPaneApp extends StatelessWidget {
  const _TwoPaneApp({
    required this.first,
    required this.second,
    required this.stores,
  });

  final AgentConversationViewModel first;
  final AgentConversationViewModel second;
  final Map<AgentConversationBindingKey, AgentConversationSliceStore> stores;

  @override
  Widget build(BuildContext context) {
    final ideTheme = buildIdeThemeData(
      brightness: Brightness.dark,
      codeFontFamily: 'CodeFont',
    );
    return ProviderScope(
      overrides: [
        agentConversationSliceStoreResolverProvider.overrideWith(
          () =>
              AgentConversationSliceStoreResolverNotifier((key) => stores[key]),
        ),
      ],
      child: IdeThemeScope(
        themeMode: ThemeMode.dark,
        lightTheme: ideTheme,
        darkTheme: ideTheme,
        child: sf.ShadcnApp(
          locale: ZetaLocalization.simplifiedChinese,
          supportedLocales: ZetaLocalization.supportedLocales,
          localizationsDelegates: ZetaLocalization.delegates,
          theme: buildShadcnTheme(ideTheme),
          materialTheme: buildMaterialTheme(ideTheme),
          home: sf.Scaffold(
            child: Column(
              children: [
                Expanded(child: AgentPane(viewModel: first)),
                Expanded(child: AgentPane(viewModel: second)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
