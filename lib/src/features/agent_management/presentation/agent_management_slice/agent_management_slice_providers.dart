import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_store.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

/// 页面 store 的只读 Riverpod 镜像；autoDispose 只摘监听，不拥有 store。
final agentManagementSliceProvider =
    NotifierProvider.family<
      AgentManagementSliceNotifier,
      AgentManagementSliceState,
      AgentManagementSliceStore
    >(
      AgentManagementSliceNotifier.new,
      name: 'agentManagementSlice',
      isAutoDispose: true,
    );

final class AgentManagementSliceNotifier
    extends Notifier<AgentManagementSliceState> {
  AgentManagementSliceNotifier(this.store);

  final AgentManagementSliceStore store;

  @override
  AgentManagementSliceState build() {
    var active = true;
    var publishScheduled = false;
    final unsubscribe = store.subscribe(() {
      // 配置/日志子页会在 initState 发起加载；测试 fake 或内存仓储可能同步
      // 回流 result。延迟到当前 build 结束，并把同一微任务内的多次进度合并。
      if (publishScheduled) {
        return;
      }
      publishScheduled = true;
      scheduleMicrotask(() {
        publishScheduled = false;
        if (active && !store.isClosed) {
          state = store.state;
        }
      });
    });
    ref.onDispose(() {
      active = false;
      unsubscribe();
    });
    return store.state;
  }
}

final agentManagementAgentsProvider =
    Provider.family<List<ManagedAgent>, AgentManagementSliceStore>(
      (ref, store) => ref.watch(
        agentManagementSliceProvider(
          store,
        ).select(AgentManagementSliceSelectors.agents),
      ),
      name: 'agentManagementAgents',
      isAutoDispose: true,
    );

final agentManagementSelectedAgentProvider =
    Provider.family<ManagedAgent, AgentManagementSliceStore>(
      (ref, store) => ref.watch(
        agentManagementSliceProvider(
          store,
        ).select(AgentManagementSliceSelectors.selectedAgent),
      ),
      name: 'agentManagementSelectedAgent',
      isAutoDispose: true,
    );

final agentManagementDetectionProgressProvider =
    Provider.family<AgentDetectionProgress?, AgentManagementSliceStore>(
      (ref, store) => ref.watch(
        agentManagementSliceProvider(
          store,
        ).select((state) => state.detectionProgress),
      ),
      name: 'agentManagementDetectionProgress',
      isAutoDispose: true,
    );
