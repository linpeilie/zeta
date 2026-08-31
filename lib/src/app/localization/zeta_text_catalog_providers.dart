import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_text_catalog.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// 当前显示语言下的全部文本目录。
///
/// **fail-closed**：显示语言要等常规设置读完才冻结，在那之前没有正确答案。这里
/// 宁可抛错，也不要先按 fallback 语言发一份目录出去——桌面通知的标题、原生菜单
/// 的标签都从这里取，发错一次就是用户可见的语言闪变。
///
/// 组合根在 `installLocaleDependentRuntime` 里用闭包覆盖它。这是组合根**唯一**
/// 保留的内部 override 类别（语言冻结之前值还不存在，写不进 provider body），
/// 调用方不要再覆盖同一个 provider。
///
/// 设计系统自有文案（`ZetaUiTextCatalog`）不在这里出口：它在语言冻结之前就要被
/// 读一次（第一帧的 loading 底色也在 `ShadcnApp` 里），而 provider 会把那次读到
/// 的值缓存住。它由 `ZetaAppComposition.zetaUiTextCatalog` 直接读字段，未冻结时
/// 回退英文。
final zetaTextCatalogsProvider = Provider<ZetaTextCatalogs>(
  (ref) => throw StateError(
    'Text catalogs were read before the composition root froze the display '
    'language',
  ),
  name: 'zetaTextCatalogs',
);

/// Agent 会话 UI 文案。
final agentUiTextCatalogProvider = Provider<AgentUiTextCatalog>(
  (ref) => ref.watch(zetaTextCatalogsProvider).agentUi,
  name: 'agentUiTextCatalog',
);

/// Agent 管理页文案。
final agentManagementTextCatalogProvider = Provider<AgentManagementTextCatalog>(
  (ref) => ref.watch(zetaTextCatalogsProvider).agentManagement,
  name: 'agentManagementTextCatalog',
);

/// 桌面通知文案。
final desktopAttentionTextCatalogProvider =
    Provider<DesktopAttentionTextCatalog>(
      (ref) => ref.watch(zetaTextCatalogsProvider).desktopAttention,
      name: 'desktopAttentionTextCatalog',
    );

/// 使用统计文案。
final usageStatisticsTextCatalogProvider = Provider<UsageStatisticsTextCatalog>(
  (ref) => ref.watch(zetaTextCatalogsProvider).usageStatistics,
  name: 'usageStatisticsTextCatalog',
);
