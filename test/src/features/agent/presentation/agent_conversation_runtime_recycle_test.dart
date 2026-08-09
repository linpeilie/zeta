import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_binding_manager.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';

import '../../../testing/fake_agent_frame_scheduler.dart';
import '../../../testing/agent_conversation_binding_test_harness.dart';
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

      expect(
        harness.factory.created,
        hasLength(2),
        reason: 'workspace 目录使用 global runtime，发送使用独立 session runtime',
      );
      expect(harness.messageTexts, contains('first'));

      await harness.registry.invalidateProvider(
        AgentProviderConfig.defaultCodex.id,
      );
      await harness.viewModel.sendMessage('second');
      harness.scheduler.drainFrames();

      expect(harness.factory.created, hasLength(3));
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
      final before = harness
          .bindingHarness
          .manager
          .bindings
          .values
          .single
          .runtimeSnapshot
          ?.runtimeIdentity;

      await harness.registry.invalidateProvider(
        AgentProviderConfig.defaultCodex.id,
      );
      await harness.viewModel.sendMessage('second');
      harness.scheduler.drainFrames();
      final after = harness
          .bindingHarness
          .manager
          .bindings
          .values
          .single
          .runtimeSnapshot
          ?.runtimeIdentity;

      expect(before, isNotNull);
      expect(after, isNotNull);
      expect(after!.generation, before!.generation + 1);
      expect(harness.factory.created.first.disposed, isTrue);
      expect(
        harness.bindingLease.binding.permissions.isRuntimeAttached,
        isTrue,
      );
    });
  });
}

final class _RecycleHarness {
  _RecycleHarness() {
    registry = AgentProviderRuntimeRegistry(providerFactory: factory);
    controller = AgentProviderSettingsController(
      configStore: MemoryAgentProviderConfigStore(),
      runtimeRegistry: registry,
    );
    bindingHarness = AgentConversationBindingTestHarness(
      registry: registry,
      settings: controller,
    );
    bindingLease = bindingHarness.acquireDraft(
      AgentProviderConfig.defaultCodex,
    );
    viewModel = AgentConversationViewModel(
      providerController: controller,
      conversationBinding: bindingLease.binding,
      globalRuntime: bindingHarness.globalRuntime,
      uiFrameScheduler: scheduler,
    )..updateContext(projectPath: '/repo', contextFilePath: null);
  }

  final _MultiInstanceProviderFactory factory = _MultiInstanceProviderFactory();
  final FakeAgentFrameScheduler scheduler = FakeAgentFrameScheduler();
  late final AgentProviderRuntimeRegistry registry;
  late final AgentProviderSettingsController controller;
  late final AgentConversationBindingTestHarness bindingHarness;
  late final AgentConversationBindingLease bindingLease;
  late final AgentConversationViewModel viewModel;

  List<String> get messageTexts =>
      viewModel.messages.map((message) => message.text).toList();

  Future<void> dispose() async {
    viewModel.dispose();
    await bindingHarness.close();
    controller.dispose();
    await registry.close();
  }
}

/// 与 [AgentPaneFakeProviderFactory] 不同：每次 create 返回**新**实例，
/// 这样销毁旧实例后重建才能被观测到。
final class _MultiInstanceProviderFactory implements AgentProviderFactory {
  final List<_RecycleProvider> created = <_RecycleProvider>[];

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = _RecycleProvider();
    created.add(provider);
    return provider;
  }
}

final class _RecycleProvider extends AgentPaneFakeProvider {
  bool disposed = false;

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}
