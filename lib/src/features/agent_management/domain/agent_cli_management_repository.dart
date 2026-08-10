import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

/// 单个 Agent CLI 的检测、配置与日志仓库契约。
///
/// Codex / Grok 各自实现；管理控制器按 agentId 路由。
abstract class AgentCliManagementRepository {
  /// 与 [AgentDefinition.id] / [AgentProviderConfig.id] 对齐的稳定 id。
  String get agentId;

  /// 执行完整但不产生模型费用的自动检测。
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  });

  /// 无计费连接测试（initialize + model list）。
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  });

  /// 将用户选择的 CLI 路径转为可持久化 provider 配置。
  Future<AgentProviderConfig> providerConfigForPath({
    required AgentProviderConfig current,
    required String path,
  });

  /// 本地配置文件绝对路径。
  String get configPath;

  /// 读取配置文档（含脱敏内容）。
  Future<AgentConfigurationDocument> readConfiguration();

  /// 校验配置内容；返回 null 表示合法。
  String? validateConfiguration(String content);

  /// 安全保存配置。
  Future<AgentConfigurationSaveResult> saveConfiguration({
    required AgentConfigurationDocument original,
    required String content,
    bool overwriteExternalChanges = false,
  });

  /// 发现本机日志路径。
  Future<List<String>> discoverLogPaths();

  /// 读取日志尾部（脱敏后）。
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  });
}

/// 检测进度回调。
typedef AgentDetectionProgressCallback =
    void Function(AgentDetectionProgress progress, ManagedAgent partial);
