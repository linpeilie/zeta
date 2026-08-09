import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/application/agent_thread_workspace_controller.dart';
import 'package:zeta/src/features/agent/data/agent_model_catalog_cache_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

import '../../../testing/fake_agent_frame_scheduler.dart';
import '../presentation/harness/agent_pane_test_harness.dart';

/// Workspace 只维护 Binding 租约：两个 thread 运行时隔离，历史读取严格惰性，
/// 单个 Binding 失效不会影响其他会话。
void main() {
  group('AgentThreadWorkspaceController conversation binding', () {
    test('AC1：两个 workspace entry 各自发一条消息，各自拿到独立实例、两条都完成', () async {
      final harness = _WorkspaceHarness();
      addTearDown(harness.dispose);

      final entryA = harness.createEntry(threadId: 'thread-a');
      final entryB = harness.createEntry(threadId: 'thread-b');

      await Future.wait(<Future<void>>[
        entryA.viewModel.sendMessage('hello from A'),
        entryB.viewModel.sendMessage('hello from B'),
      ]);
      harness.drainAll();

      // settings/catalog 使用一个 global 实例；两个 Binding 分别创建 session。
      expect(harness.factory.created, hasLength(3));
      expect(
        identical(harness.factory.created[1], harness.factory.created[2]),
        isFalse,
      );
      expect(
        entryA.viewModel.messages.map((message) => message.text),
        contains('hello from A'),
      );
      expect(
        entryB.viewModel.messages.map((message) => message.text),
        contains('hello from B'),
      );
    });

    test('AC2/AC3：打开已有 thread 读历史不创建 session 实例；首次 sendMessage 才创建', () async {
      final harness = _WorkspaceHarness();
      addTearDown(harness.dispose);

      final entry = harness.createEntry(threadId: 'thread-a');

      // 创建 entry 会通过 global runtime 预载模型目录，但 Binding 必须保持 dormant。
      expect(harness.factory.created, hasLength(1));
      expect(harness.registry.debugProviderCount, 1);
      expect(entry.binding.hasRuntime, isFalse);

      await entry.viewModel.switchThread(harness.thread(id: 'thread-a'));
      harness.drainAll();

      // AC2：只读历史，只会命中 provider 的 global scope（跨所有 entry 共享）；
      // 不会为这个 entry 单独起一个 session scope 实例。
      expect(harness.factory.created, hasLength(1));
      expect(harness.registry.debugProviderCount, 1);
      expect(entry.binding.hasRuntime, isFalse);

      await entry.viewModel.sendMessage('go');
      harness.drainAll();

      // AC3：首次提交输入才会创建这个 entry 专属的 session scope 实例
      // （global 实例继续保留，总数变成 2）。
      expect(harness.factory.created, hasLength(2));
      expect(harness.registry.debugProviderCount, 2);
      expect(entry.binding.hasRuntime, isTrue);
    });

    test('AC6：一个 entry 的实例失效不影响另一个', () async {
      final harness = _WorkspaceHarness();
      addTearDown(harness.dispose);

      final entryA = harness.createEntry(threadId: 'thread-a');
      final entryB = harness.createEntry(threadId: 'thread-b');

      await entryA.viewModel.sendMessage('hello from A');
      await entryB.viewModel.sendMessage('hello from B');
      harness.drainAll();
      expect(harness.factory.created, hasLength(3));

      // 模拟 entry A 的运行实例异常退出/被回收。
      await entryA.binding.invalidateRuntime();

      // entry B 完全不受影响：历史时间线原样保留，且能继续发消息。
      expect(
        entryB.viewModel.messages.map((message) => message.text),
        contains('hello from B'),
      );
      await entryB.viewModel.sendMessage('second from B');
      harness.drainAll();
      expect(
        entryB.viewModel.messages.map((message) => message.text),
        containsAllInOrder(<String>['hello from B', 'second from B']),
      );

      // entry A 再次发消息会自动重建它自己的实例，且不影响之前已保留的时间线。
      await entryA.viewModel.sendMessage('second from A');
      harness.drainAll();
      expect(
        entryA.viewModel.messages.map((message) => message.text),
        containsAllInOrder(<String>['hello from A', 'second from A']),
      );
      expect(harness.factory.created, hasLength(4));
    });
  });
}

final class _WorkspaceHarness {
  _WorkspaceHarness() {
    registry = AgentProviderRuntimeRegistry(providerFactory: factory);
    providerController = ActiveAgentProviderController(
      configStore: MemoryAgentProviderConfigStore(),
      modelCatalogRepository: AgentModelCatalogRepository(
        store: MemoryAgentModelCatalogCacheStore(),
      ),
      runtimeRegistry: registry,
    );
    controller = AgentThreadWorkspaceController(
      providerController: providerController,
      workspaceFilesProvider: () => const <WorkspaceNode>[],
      runtimeRegistry: registry,
      uiFrameSchedulerFactory: () {
        final scheduler = FakeAgentFrameScheduler();
        _schedulers.add(scheduler);
        return scheduler;
      },
    );
  }

  final _MultiInstanceProviderFactory factory = _MultiInstanceProviderFactory();
  final List<FakeAgentFrameScheduler> _schedulers = <FakeAgentFrameScheduler>[];
  late final AgentProviderRuntimeRegistry registry;
  late final ActiveAgentProviderController providerController;
  late final AgentThreadWorkspaceController controller;

  AgentThreadWorkspaceEntry createEntry({required String threadId}) {
    final entry = controller.ensureThreadEntry(
      projectPath: '/repo',
      providerId: AgentProviderConfig.defaultCodex.id,
      threadId: threadId,
    );
    entry.viewModel.updateWorkspace(
      projectPath: '/repo',
      contextFilePath: null,
    );
    return entry;
  }

  AgentThreadSummary thread({required String id}) {
    return AgentThreadSummary(
      id: id,
      providerId: AgentProviderConfig.defaultCodex.id,
      projectPath: '/repo',
      title: id,
      sessionPath: '/repo/$id.jsonl',
      preview: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
      status: AgentThreadRuntimeStatus.idle,
    );
  }

  void drainAll() {
    for (final scheduler in _schedulers) {
      scheduler.drainFrames();
    }
  }

  Future<void> dispose() async {
    controller.dispose();
    providerController.dispose();
    await registry.close();
  }
}

/// 与 [AgentPaneFakeProviderFactory] 不同：每次 create 返回**新**实例，
/// 这样不同 scope（global / 各个 entry 的 session）拿到的才是可区分的对象。
final class _MultiInstanceProviderFactory implements AgentProviderFactory {
  final List<AgentPaneFakeProvider> created = <AgentPaneFakeProvider>[];

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = AgentPaneFakeProvider();
    created.add(provider);
    return provider;
  }
}
