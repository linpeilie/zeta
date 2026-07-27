/// Agent 时间线动态高度虚拟滚动 feature flag。
///
/// 仅用于开发/回滚与对照测试，不作为长期用户配置。
/// - `true`：使用 `IdeAnchoredDynamicSliverList` + coordinator + scrollbar
/// - `false`：回退普通 `SliverList` + 旧 `_stickToBottom` / `animateTo`
///
/// 可通过编译期定义覆盖：
/// `--dart-define=ZETA_USE_ANCHORED_DYNAMIC_TIMELINE=false`
///
/// **阶段 5 建议**：默认保持开启至少一个发布周期；确认生产无回归后再
/// 评估移除 flag 与旧路径，切勿在本周期直接删除回退代码。
library;

/// 是否启用锚定动态高度时间线 sliver。
const bool kUseAnchoredDynamicTimelineSliver = bool.fromEnvironment(
  'ZETA_USE_ANCHORED_DYNAMIC_TIMELINE',
  defaultValue: true,
);
