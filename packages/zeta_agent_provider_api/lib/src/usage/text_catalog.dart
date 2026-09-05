/// Provider 用量来源的中立文案端口。
abstract interface class AgentUsageSourceTextCatalog {
  String get indexWriteFailed;
  String indexReadRescanned(String providerName);
  String sessionDirIncomplete(String name);
  String sessionFilesUnreadable(String count, String name);
  String historyRowsCorrupt(String count, String name);
}

/// 保持原用量来源默认文案，宿主可显式替换。
final class FallbackAgentUsageSourceTextCatalog
    implements AgentUsageSourceTextCatalog {
  const FallbackAgentUsageSourceTextCatalog();
  @override
  String get indexWriteFailed => '统计索引暂时无法保存，本次结果仍可正常查看。';

  @override
  String indexReadRescanned(String providerName) =>
      '$providerName 统计索引暂时无法读取，已重新扫描本地历史。';

  @override
  String sessionDirIncomplete(String name) => '$name 会话目录未能完整枚举，已展示可读取的数据。';

  @override
  String sessionFilesUnreadable(String count, String name) =>
      '$count 个 $name 会话文件读取失败，已展示其余数据。';

  @override
  String historyRowsCorrupt(String count, String name) =>
      '$count 行 $name 历史损坏，已跳过并继续统计。';
}
