import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Provider 设置与全局目录能力的 application 边界。
///
/// 会话消费者只依赖这个端口，不依赖 UI 层的具体控制器，也不能从这里创建
/// session runtime。后者只能通过 `AgentConversationBinding.beginTurn()` 完成。
abstract interface class AgentProviderSettingsPort {
  AgentProviderSettings get settings;

  String get activeProviderId;

  String get activeProviderName;

  AgentProviderConfig get activeProviderConfig;

  List<AgentProviderConfig> get enabledProviders;

  bool isProviderEnabled(String providerId);

  AgentProviderConfig? providerConfigById(String providerId);

  AgentProviderCapabilities capabilitiesForProviderId(String providerId);

  /// 返回插件定义声明的稳定模型目录来源标签。
  String modelCatalogSourceFor(AgentProviderConfig config);

  /// 记录一次模型目录快照。
  ///
  /// presentation 只声明"记录这批模型"，缓存指纹、去重与落盘由 application
  /// 侧的目录仓库决定——调用方不再触达 `AgentModelCatalogRepository`。
  Future<void> recordModelCatalog({
    required AgentProviderConfig config,
    required AgentModelList models,
    required String source,
  });

  /// 加载模型目录；命中缓存立即回调 [onCacheHit]，必要时用 [refreshLoader] 刷新。
  ///
  /// `source` 由端口内部按 [modelCatalogSourceFor] 解析，调用方不需要知道。
  Future<AgentModelCatalogLoadResult> loadModelCatalog({
    required AgentProviderConfig config,
    required AgentModelCatalogLoader refreshLoader,
    bool forceRefresh = false,
    void Function(AgentModelCatalogSnapshot snapshot)? onCacheHit,
  });

  Future<void> updateProviderConfig(
    AgentProviderConfig updated, {
    bool restartProvider = false,
  });

  Future<void> setProviderEnabled(String providerId, bool enabled);

  Future<void> setActiveProvider(String providerId);

  Future<void> persistModelSelection(
    AgentModelSelection selection,
    Map<String, AgentModelPreference> preferences,
  );

  Future<void> persistPermissionOptionId(String optionId);

  Future<void> persistPermissionOptionIdForProvider(
    String providerId,
    String optionId,
  );

  Future<AgentProviderSettings> loadSettings();

  /// 订阅设置快照变化；返回的函数用于取消订阅。
  void Function() subscribe(void Function() listener);
}
