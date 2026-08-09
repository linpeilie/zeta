import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

import '../../../testing/fake_agent_frame_scheduler.dart';
import 'harness/agent_pane_test_harness.dart';

/// 04-目标态与步骤.md §S5：turn 开始时 pin 该 entry 的 provider 实例，turn
/// 完成/失败/取消三条路径都要释放——三条缺一就是 pin 泄漏，S6 起意味着这个
/// scope 永远不会被回收器命中。本步骤没有回收器读 pinCount，这里只钉住"记录
/// 本身是对的"，不涉及任何实际回收行为。
void main() {
  group('turn 生命周期的 pin（S5）', () {
    test('turn 运行中 pinCount == 1', () async {
      final harness = _PinHarness();
      addTearDown(harness.dispose);

      expect(await harness.currentPinCount(), 0);

      await harness.viewModel.sendMessage('hello');
      harness.scheduler.drainFrames();

      expect(harness.viewModel.isTurnRunning, isTrue);
      expect(await harness.currentPinCount(), 1);
    });

    test('turn 正常完成后 pinCount 归零', () async {
      final harness = _PinHarness();
      addTearDown(harness.dispose);

      await harness.viewModel.sendMessage('hello');
      harness.scheduler.drainFrames();
      expect(await harness.currentPinCount(), 1);

      harness.provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await Future<void>.delayed(Duration.zero);
      harness.scheduler.drainFrames();

      expect(harness.viewModel.isTurnRunning, isFalse);
      expect(await harness.currentPinCount(), 0);
    });

    test('turn 失败（server 上报 failed）后 pinCount 归零', () async {
      final harness = _PinHarness();
      addTearDown(harness.dispose);

      await harness.viewModel.sendMessage('hello');
      harness.scheduler.drainFrames();
      expect(await harness.currentPinCount(), 1);

      harness.provider.emitEvent(
        const AgentTurnCompletedEvent(
          sessionId: 'session-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.failed,
          errorMessage: 'boom',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      harness.scheduler.drainFrames();

      expect(harness.viewModel.isTurnRunning, isFalse);
      expect(await harness.currentPinCount(), 0);
    });

    test('turn 未被接受（本地异常，从未真正开始）后 pinCount 归零', () async {
      final harness = _PinHarness();
      addTearDown(harness.dispose);

      harness.provider.sendMessageThrows = true;
      await harness.viewModel.sendMessage('hello');
      harness.scheduler.drainFrames();

      // 这条路径根本没有走到"turn 已被 server 接受"，不会有后续的
      // turn/completed 事件——finally 块必须自己释放，否则永久泄漏。
      expect(await harness.currentPinCount(), 0);
    });

    test(
      'turn 被取消（cancelActiveTurn + server 确认 interrupted）后 pinCount 归零',
      () async {
        final harness = _PinHarness();
        addTearDown(harness.dispose);

        await harness.viewModel.sendMessage('hello');
        harness.scheduler.drainFrames();
        expect(await harness.currentPinCount(), 1);

        await harness.viewModel.cancelActiveTurn();
        expect(
          harness.provider.cancelledTurnIds,
          contains('turn-1'),
          reason:
              'cancelActiveTurn 本身只发 RPC，不直接结束 turn；真正的结束靠下面'
              '模拟的 server 确认事件',
        );

        harness.provider.emitEvent(
          const AgentTurnCompletedEvent(
            sessionId: 'session-1',
            turnId: 'turn-1',
            status: AgentHistoryTurnStatus.interrupted,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        harness.scheduler.drainFrames();

        expect(harness.viewModel.isTurnRunning, isFalse);
        expect(await harness.currentPinCount(), 0);
      },
    );
  });
}

final class _PinHarness {
  _PinHarness() {
    final factory = AgentPaneFakeProviderFactory(provider);
    registry = AgentProviderRuntimeRegistry(providerFactory: factory);
    controller = ActiveAgentProviderController(
      configStore: MemoryAgentProviderConfigStore(),
      runtimeRegistry: registry,
    );
    viewModel = AgentConversationViewModel(
      providerController: controller,
      uiFrameScheduler: scheduler,
    )..updateWorkspace(projectPath: '/repo', contextFilePath: null);
  }

  final _PinTestProvider provider = _PinTestProvider();
  final FakeAgentFrameScheduler scheduler = FakeAgentFrameScheduler();
  late final AgentProviderRuntimeRegistry registry;
  late final ActiveAgentProviderController controller;
  late final AgentConversationViewModel viewModel;

  /// 借一个探针租约读当前 pinCount（pinCount 挂在注册表共享的 entry 上，不是
  /// 某一个具体租约对象），读完立刻还，不影响实际计数。
  Future<int> currentPinCount() async {
    final probe = await registry.acquire(AgentProviderConfig.defaultCodex);
    final count = probe.pinCount;
    await probe.release();
    return count;
  }

  Future<void> dispose() async {
    viewModel.dispose();
    controller.dispose();
    await registry.close();
  }
}

/// 在 [AgentPaneFakeProvider] 基础上加一个可控的发送失败开关，用于钉住"turn
/// 从未被 server 接受"这条 pin 释放路径。
final class _PinTestProvider extends AgentPaneFakeProvider {
  bool sendMessageThrows = false;
  final List<String> cancelledTurnIds = <String>[];

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) {
    if (sendMessageThrows) {
      throw StateError('send failed');
    }
    return super.sendMessage(
      session: session,
      context: context,
      message: message,
      inputs: inputs,
      clientUserMessageId: clientUserMessageId,
      configuration: configuration,
    );
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    cancelledTurnIds.add(turn.id);
  }
}
