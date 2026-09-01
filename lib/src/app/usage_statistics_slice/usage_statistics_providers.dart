import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

/// Agent 统计面板的数据源。
///
/// **null 是一个取值，不是"没注入"**：兜底实现要用统计切片内部那份和完整统计页
/// 共享的 `AgentUsageQueryService`，app 层拿不到它，也不该为了拿它再建第二份
/// （查询服务带缓存，建两份就是两套口径）。因此 null 的含义是"用切片自己按共享
/// 查询服务建的那个"。宿主要隔离本机 Agent 历史时覆盖成自己的实现。
final agentUsagePanelRepositoryProvider = Provider<AgentUsagePanelRepository?>(
  (ref) => null,
  name: 'agentUsagePanelRepository',
);

/// 是否在启动及每个回合结束后自动刷新 Agent 用量。
///
/// 生产默认打开：会读本机 Agent CLI 的历史记录。widget test 由
/// `zetaTestComposition` 关掉；注入了假仓储、数据来源已经不碰本机之后，用例
/// 再显式覆盖成 `true`。不要从"有没有传统计仓储"反推——一个可选参数同时决定
/// 数据源和刷新策略，改一处就会悄悄改另一处。
final agentUsageAutoRefreshEnabledProvider = Provider<bool>(
  (ref) => true,
  name: 'agentUsageAutoRefreshEnabled',
);
