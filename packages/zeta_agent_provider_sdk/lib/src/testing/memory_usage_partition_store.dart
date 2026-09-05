import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// 测试用用量分区仓库。
final class MemoryUsageStatisticsPartitionStore
    implements AgentUsagePartitionPort {
  MemoryUsageStatisticsPartitionStore({
    Map<String, UsageStatisticsIndexPartition> partitions =
        const <String, UsageStatisticsIndexPartition>{},
  }) : _partitions = <String, UsageStatisticsIndexPartition>{...partitions};

  final Map<String, UsageStatisticsIndexPartition> _partitions;

  @override
  Future<UsageStatisticsIndexPartition?> readPartition(String sourceKey) async {
    return _partitions[sourceKey.trim()];
  }

  @override
  Future<void> writePartition(
    String sourceKey,
    UsageStatisticsIndexPartition partition,
  ) async {
    _partitions[sourceKey.trim()] = partition;
  }
}
