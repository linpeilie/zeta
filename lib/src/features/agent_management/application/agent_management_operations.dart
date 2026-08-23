import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

/// Agent 管理页面可发起的操作与只读快照。
///
/// 契约本身不依赖 Flutter。迁移期旧 controller 与新 MVI store 都实现它，
/// presentation 只在最外层选择监听方式，内部控件不再绑定具体状态容器。
abstract interface class AgentManagementOperations {
  List<ManagedAgent> get agents;

  ManagedAgent get agent;

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

  Future<void> detect();

  Future<void> setEnabled(bool enabled);

  Future<void> setAccountDataEnrichmentEnabled(bool enabled);

  Future<AgentConnectionTestResult?> testConnection();

  Future<AgentConfigurationDocument?> loadConfiguration();

  String? validateConfiguration(String content);

  Future<AgentConfigurationSaveResult> saveConfiguration(
    String content, {
    bool overwriteExternalChanges = false,
  });

  Future<List<AgentLogEntry>> loadLogs();
}
