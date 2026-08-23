import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_store.dart';

/// app 组合层必须注入的完整统计页 store。
final usageStatisticsSliceStoreProvider = Provider<UsageStatisticsSliceStore>(
  (ref) => throw StateError('UsageStatisticsSliceStore is not bound'),
  name: 'usageStatisticsSliceStore',
);

/// app 组合层必须注入的侧栏 store。
final agentUsagePanelSliceStoreProvider = Provider<AgentUsagePanelSliceStore>(
  (ref) => throw StateError('AgentUsagePanelSliceStore is not bound'),
  name: 'agentUsagePanelSliceStore',
);

final usageStatisticsSliceProvider =
    NotifierProvider<UsageStatisticsSliceNotifier, UsageStatisticsSliceState>(
      UsageStatisticsSliceNotifier.new,
      name: 'usageStatisticsSlice',
      dependencies: [usageStatisticsSliceStoreProvider],
      isAutoDispose: true,
    );

final class UsageStatisticsSliceNotifier
    extends Notifier<UsageStatisticsSliceState> {
  @override
  UsageStatisticsSliceState build() {
    final store = ref.watch(usageStatisticsSliceStoreProvider);
    var active = true;
    var scheduled = false;
    final unsubscribe = store.subscribe(() {
      if (scheduled) {
        return;
      }
      scheduled = true;
      scheduleMicrotask(() {
        scheduled = false;
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

final agentUsagePanelSliceProvider =
    NotifierProvider<AgentUsagePanelSliceNotifier, AgentUsagePanelSliceState>(
      AgentUsagePanelSliceNotifier.new,
      name: 'agentUsagePanelSlice',
      dependencies: [agentUsagePanelSliceStoreProvider],
      isAutoDispose: true,
    );

final class AgentUsagePanelSliceNotifier
    extends Notifier<AgentUsagePanelSliceState> {
  @override
  AgentUsagePanelSliceState build() {
    final store = ref.watch(agentUsagePanelSliceStoreProvider);
    var active = true;
    var scheduled = false;
    final unsubscribe = store.subscribe(() {
      if (scheduled) {
        return;
      }
      scheduled = true;
      scheduleMicrotask(() {
        scheduled = false;
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
