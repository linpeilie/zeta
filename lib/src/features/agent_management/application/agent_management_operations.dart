import 'agent_management_agent_view.dart';
import 'agent_management_detection_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// Agent 管理页面可发起的操作与只读快照。
///
/// 契约本身不依赖 Flutter，由应用会话级 AgentManagementSliceNotifier 唯一实现。
abstract interface class AgentManagementOperations {
  List<AgentManagementAgentView> get agents;

  AgentManagementAgentView get agent;

  String get selectedAgentId;

  AgentDetectionProgress? get detectionProgress;

  AgentConfigurationDocument? get configuration;

  List<AgentLogEntry> get logs;

  bool get initialized;

  bool get detecting;

  bool get testing;

  bool get loadingConfiguration;

  bool get savingConfiguration;

  bool get loadingLogs;

  bool get updatingAccountDataEnrichment;

  String? get operationError;

  bool get supportsAccountDataEnrichment;

  bool get accountDataEnrichmentEnabled;

  List<AgentProviderConfig> get availableThreadProviders;

  Future<List<AgentProviderConfig>> loadAvailableThreadProviders();

  void selectAgent(String agentId);

  Future<void> initialize({bool autoDetect = false});

  /// 显式刷新同义入口；保留调用方的 typed 终态。
  Future<AgentManagementDetectionRunResult> detect();
  Future<AgentManagementDetectionRunResult> ensureDetected();
  Future<AgentManagementDetectionRunResult> refreshDetection();
  void cancelDetection();

  Future<void> setEnabled(bool enabled);

  Future<void> setAccountDataEnrichmentEnabled(bool enabled);

  Future<AgentManagementConnectionCheckSummary?> testConnection();

  Future<AgentConfigurationDocument?> loadConfiguration();

  String? validateConfiguration(String content);

  Future<AgentConfigurationSaveResult> saveConfiguration(
    String content, {
    bool overwriteExternalChanges = false,
  });

  Future<List<AgentLogEntry>> loadLogs();
}
