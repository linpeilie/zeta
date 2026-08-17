import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

/// 测试与未注入目录时的简体中文等价文案，与当前 zh ARB 逐字一致。
final class FallbackUsageStatisticsTextCatalog
    implements UsageStatisticsTextCatalog {
  const FallbackUsageStatisticsTextCatalog();

  @override
  String timeRangeLabel(UsageTimeRangePreset preset) => switch (preset) {
    UsageTimeRangePreset.today => '当天',
    UsageTimeRangePreset.last7Days => '最近7天',
    UsageTimeRangePreset.last30Days => '最近30天',
    UsageTimeRangePreset.last90Days => '最近90天',
    UsageTimeRangePreset.thisMonth => '本月',
    UsageTimeRangePreset.previousMonth => '上个月',
    UsageTimeRangePreset.custom => '自定义时间',
  };

  @override
  String taskStatusLabel(UsageTaskStatus status) => switch (status) {
    UsageTaskStatus.running => '运行中',
    UsageTaskStatus.completed => '成功',
    UsageTaskStatus.interrupted => '已取消',
    UsageTaskStatus.failed => '失败',
    UsageTaskStatus.unknown => '未知',
  };

  @override
  String errorCategoryLabel(UsageErrorCategory category) => switch (category) {
    UsageErrorCategory.account => '账号异常',
    UsageErrorCategory.cli => '运行时异常',
    UsageErrorCategory.network => '网络错误',
    UsageErrorCategory.timeout => '超时',
    UsageErrorCategory.cancelled => '用户取消',
    UsageErrorCategory.other => '其他异常',
  };

  @override
  String errorNextAction(UsageErrorCategory category) => switch (category) {
    UsageErrorCategory.account => '检查 Codex 登录状态与当前套餐额度。',
    UsageErrorCategory.cli => '检查 Codex 版本、配置和运行日志。',
    UsageErrorCategory.network => '检查网络、代理设置后重试。',
    UsageErrorCategory.timeout => '缩小任务范围后重试。',
    UsageErrorCategory.cancelled => '如需继续，请重新发起该任务。',
    UsageErrorCategory.other => '打开任务详情或 Agent 日志查看原始原因。',
  };

  @override
  String trendMetricLabel(UsageTrendMetric metric) => switch (metric) {
    UsageTrendMetric.calls => '调用次数',
    UsageTrendMetric.successRate => '成功率',
    UsageTrendMetric.totalTokens => 'Token 消耗',
    UsageTrendMetric.averageResponse => '平均响应时间',
    UsageTrendMetric.averageDuration => '任务耗时',
  };

  @override
  String rankSortLabel(UsageRankSort sort) => switch (sort) {
    UsageRankSort.calls => '调用次数',
    UsageRankSort.totalTokens => 'Token 消耗',
    UsageRankSort.failures => '失败次数',
    UsageRankSort.averageDuration => '任务耗时',
  };

  @override
  String get unknownProjectName => '未知项目';

  @override
  String loadFailed(Object error) => '无法加载使用统计：$error';

  @override
  String get quotaUnreadable => '套餐额度暂时无法读取';

  @override
  String get agentTemporarilyUnavailable => '当前 Agent 暂时无法连接';

  @override
  String get tokenHistoryUnavailable => 'Token 历史暂时无法读取';

  @override
  String get tokenSourceMismatch => 'Token 历史数据源配置不匹配';

  @override
  String get noTokenHistory => '暂无 Token 历史';

  @override
  String get todayTokensUnreadable => '今日 Token 暂时无法读取';

  @override
  String get indexWriteFailed => '统计索引暂时无法保存，本次结果仍可正常查看。';

  @override
  String indexReadRescanned(String providerName) =>
      '$providerName 统计索引暂时无法读取，已重新扫描本地历史。';

  @override
  String get agentDisabledOrUnavailable => '该 Agent 已禁用或不可用';

  @override
  String get agentUsageTemporarilyUnavailable => 'Agent 用量暂时无法读取';

  @override
  String sessionDirIncomplete(String name) => '$name 会话目录未能完整枚举，已展示可读取的数据。';

  @override
  String sessionFilesUnreadable(String count, String name) =>
      '$count 个 $name 会话文件读取失败，已展示其余数据。';

  @override
  String historyRowsCorrupt(String count, String name) =>
      '$count 行 $name 历史损坏，已跳过并继续统计。';
}
