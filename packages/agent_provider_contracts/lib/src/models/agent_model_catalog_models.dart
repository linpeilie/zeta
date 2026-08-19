import 'package:agent_provider_contracts/src/models/agent_model_selection_models.dart';

/// 可跨 Provider 实例复用的模型目录快照。
final class AgentModelCatalogSnapshot {
  const AgentModelCatalogSnapshot({
    required this.providerId,
    required this.configFingerprint,
    required this.includeHidden,
    required this.models,
    required this.fetchedAt,
    required this.source,
  });

  /// Provider 的稳定配置 id。
  final String providerId;

  /// 不包含密钥的运行时配置指纹，用于识别需要失效的目录。
  final String configFingerprint;

  /// 当前目录是否包含隐藏模型。
  final bool includeHidden;

  /// 规范化后的完整模型目录。
  final AgentModelList models;

  /// 最近一次成功从 Provider 获取目录的时间。
  final DateTime fetchedAt;

  /// 最近一次成功来源，仅用于诊断和缓存元数据。
  final String source;
}

/// 模型目录缓存的持久化端口。
abstract interface class AgentModelCatalogCacheStore {
  /// 读取全部缓存。
  ///
  /// 文件不存在时返回空列表；损坏或不兼容内容必须抛出类型化解码失败，
  /// 由上层决定是否重建缓存。
  Future<List<AgentModelCatalogSnapshot>> load();

  /// 原子保存完整缓存快照。
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots);
}
