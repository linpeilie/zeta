import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

import '../../../testing/fake_agent_frame_scheduler.dart';
import 'harness/agent_pane_test_harness.dart';

/// 会话级 Provider 实例改造会引入「闲置回收 + 再次发送时重建」。回收销毁的只应是
/// 子进程实例，会话本身（时间线、草稿、已选 thread）必须原样留在 Pane 里。
///
/// 这里用现有的 `invalidateProvider` 作为「实例被销毁并重建」的等价触发，先把这条
/// 不变量钉住；回收器落地后它会直接复用（见 02-现状测绘.md Q3）。
void main() {
  group('Provider 实例重建时的会话不变量', () {
    test('实例被销毁并重建后，已有会话时间线不被清空', () async {
      final harness = _RecycleHarness();
      addTearDown(harness.dispose);

      await harness.viewModel.sendMessage('first');
      harness.scheduler.drainFrames();

      expect(harness.factory.created, hasLength(1));
      expect(harness.messageTexts, contains('first'));

      await harness.registry.invalidateProvider(
        AgentProviderConfig.defaultCodex.id,
      );
      await harness.viewModel.sendMessage('second');
      harness.scheduler.drainFrames();

      expect(harness.factory.created, hasLength(2));
      expect(
        harness.messageTexts,
        containsAllInOrder(<String>['first', 'second']),
      );
    });

    test('实例重建后 runtime identity 递增，旧实例已退役', () async {
      final harness = _RecycleHarness();
      addTearDown(harness.dispose);

      await harness.viewModel.sendMessage('first');
      harness.scheduler.drainFrames();
      final before = harness.controller.activeProviderRuntimeIdentity;

      await harness.registry.invalidateProvider(
        AgentProviderConfig.defaultCodex.id,
      );
      await harness.viewModel.sendMessage('second');
      harness.scheduler.drainFrames();
      final after = harness.controller.activeProviderRuntimeIdentity;

      expect(before, isNotNull);
      expect(after, isNotNull);
      expect(after!.generation, before!.generation + 1);
      expect(harness.registry.permissionStateStore.isCurrent(before), isFalse);
      expect(harness.registry.permissionStateStore.isCurrent(after), isTrue);
    });
  });
}

final class _RecycleHarness {
  _RecycleHarness() {
    registry = AgentProviderRuntimeRegistry(providerFactory: factory);
    controller = ActiveAgentProviderController(
      providerFactory: factory,
      configStore: MemoryAgentProviderConfigStore(),
      runtimeRegistry: registry,
    );
    viewModel = AgentConversationViewModel(
      providerController: controller,
      uiFrameScheduler: scheduler,
    )..updateWorkspace(projectPath: '/repo', contextFilePath: null);
  }

  final _MultiInstanceProviderFactory factory = _MultiInstanceProviderFactory();
  final FakeAgentFrameScheduler scheduler = FakeAgentFrameScheduler();
  late final AgentProviderRuntimeRegistry registry;
  late final ActiveAgentProviderController controller;
  late final AgentConversationViewModel viewModel;

  List<String> get messageTexts =>
      viewModel.messages.map((message) => message.text).toList();

  Future<void> dispose() async {
    viewModel.dispose();
    controller.dispose();
    await registry.close();
  }
}

/// 与 [AgentPaneFakeProviderFactory] 不同：每次 create 返回**新**实例，
/// 这样销毁旧实例后重建才能被观测到。
final class _MultiInstanceProviderFactory implements AgentProviderFactory {
  final List<AgentPaneFakeProvider> created = <AgentPaneFakeProvider>[];

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = AgentPaneFakeProvider();
    created.add(provider);
    return provider;
  }
}
