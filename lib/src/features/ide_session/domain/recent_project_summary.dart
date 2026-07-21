/// 首页展示的近期项目摘要。
final class RecentProjectSummary {
  const RecentProjectSummary({required this.path, this.lastOpenedAt});

  /// 项目根目录。
  final String path;

  /// 最近一次成功进入项目或其会话的时间。
  ///
  /// 旧版会话没有该字段时保持为空，并按原项目列表顺序回退。
  final DateTime? lastOpenedAt;
}
