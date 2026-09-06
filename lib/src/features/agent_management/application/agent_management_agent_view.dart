import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// 不透明、仅在当前组合目录存活的详情资源标识；不能序列化。
final class AgentManagementDetailsHandle {
  AgentManagementDetailsHandle();
}

/// 仅含显示字段的静态贡献定义。
final class AgentManagementDisplayDefinition {
  const AgentManagementDisplayDefinition({
    required this.id,
    required this.displayName,
    required this.vendor,
    required this.commandName,
    required this.protocol,
    required this.transport,
    required this.configFormat,
    this.isBeta = false,
  });

  final String id;
  final String displayName;
  final String vendor;
  final String commandName;
  final String protocol;
  final String transport;
  final String configFormat;

  /// 是否需要用户显式启用并确认兼容性风险的预览能力。
  final bool isBeta;
}

/// 显式连接测试的安全摘要；原始资料只在 app 目录中。
final class AgentManagementConnectionCheckSummary {
  AgentManagementConnectionCheckSummary({
    required this.success,
    required this.testedAt,
    required this.elapsed,
    required this.cliCallable,
    required this.accountValid,
    required this.protocolReady,
    this.failureStage,
    this.message,
    this.detailsHandle,
    this.protocolVersion,
    this.agentName,
    this.agentVersion,
    List<String> capabilitySummary = const <String>[],
    this.capabilityFingerprint,
    this.compatibilitySummary,
    this.exitReason,
  }) : capabilitySummary = List.unmodifiable(capabilitySummary);

  final bool success;
  final DateTime testedAt;
  final Duration elapsed;
  final bool cliCallable;
  final bool accountValid;
  final bool protocolReady;
  final AgentDiagnosticStage? failureStage;
  final String? message;
  final AgentManagementDetailsHandle? detailsHandle;

  /// 握手诊断只保存白名单摘要，不包含原始 payload。
  final String? protocolVersion;
  final String? agentName;
  final String? agentVersion;
  final List<String> capabilitySummary;
  final String? capabilityFingerprint;
  final String? compatibilitySummary;
  final String? exitReason;
}

/// 探测独占的已确认字段，不包含用户设置或会话运行事实。
final class AgentDetectionDetails {
  AgentDetectionDetails({
    this.installationState = AgentInstallationState.unknown,
    this.executableLocated = false,
    this.currentVersion,
    this.latestVersion,
    this.accountState = AgentAccountState.unknown,
    this.accountLabel,
    this.versionState = AgentVersionState.unknown,
    this.lastDetectedAt,
    this.errorStage,
    this.safeErrorMessage,
    this.safeSuggestion,
    this.configExists = false,
    this.configModifiedAt,
    this.availableLogFileCount = 0,
    this.modelsUpdatedAt,
    this.modelSource,
    this.connectionTest,
    this.detailsHandle,
    List<AgentModelInfo> detectedModels = const [],
  }) : detectedModels = List.unmodifiable(detectedModels);
  final AgentInstallationState installationState;
  final bool executableLocated;
  final String? currentVersion;
  final String? latestVersion;
  final AgentAccountState accountState;
  final String? accountLabel;
  final AgentVersionState versionState;
  final DateTime? lastDetectedAt;
  final AgentDiagnosticStage? errorStage;
  final String? safeErrorMessage;
  final String? safeSuggestion;
  final bool configExists;
  final DateTime? configModifiedAt;
  final int availableLogFileCount;
  final DateTime? modelsUpdatedAt;
  final String? modelSource;
  final AgentManagementConnectionCheckSummary? connectionTest;
  final AgentManagementDetailsHandle? detailsHandle;
  final List<AgentModelInfo> detectedModels;
}

/// 临时进度不携带详情句柄，也不成为已确认结果。
final class AgentDetectionPartial {
  const AgentDetectionPartial({
    this.installationState,
    this.currentVersion,
    this.accountState,
    this.versionState,
  });
  final AgentInstallationState? installationState;
  final String? currentVersion;
  final AgentAccountState? accountState;
  final AgentVersionState? versionState;
}

/// 用户显式检查的独立覆盖，空模型目录不覆盖探测目录。
final class AgentManagementConnectionCheckState {
  AgentManagementConnectionCheckState({
    required this.result,
    List<AgentModelInfo> models = const [],
    this.modelsUpdatedAt,
    this.modelSource,
  }) : models = List.unmodifiable(models);
  final AgentManagementConnectionCheckSummary result;
  final List<AgentModelInfo> models;
  final DateTime? modelsUpdatedAt;
  final String? modelSource;
}

/// 由确认证据、当前设置、实时运行事实计算出的安全只读视图。
final class AgentManagementAgentView {
  const AgentManagementAgentView({
    required this.definition,
    required this.details,
    required this.enabled,
    required this.runtimeState,
    this.connectionCheck,
    this.confirmedConfigExists,
    this.confirmedConfigModifiedAt,
    this.logFileCount,
  });
  final AgentManagementDisplayDefinition definition;
  final AgentDetectionDetails details;
  final bool enabled;
  final AgentRuntimeState runtimeState;
  final AgentManagementConnectionCheckState? connectionCheck;
  final bool? confirmedConfigExists;
  final DateTime? confirmedConfigModifiedAt;
  final int? logFileCount;
  AgentInstallationState get installationState => details.installationState;
  bool get executableLocated => details.executableLocated;
  String? get currentVersion => details.currentVersion;
  String? get latestVersion => details.latestVersion;
  AgentAccountState get accountState => details.accountState;
  String? get accountLabel => details.accountLabel;
  AgentVersionState get versionState => details.versionState;
  DateTime? get lastDetectedAt => details.lastDetectedAt;
  AgentDiagnosticStage? get errorStage => connectionCheck == null
      ? details.errorStage
      : connectionCheck!.result.failureStage;
  String? get errorMessage => connectionCheck == null
      ? details.safeErrorMessage
      : connectionCheck!.result.success
      ? null
      : connectionCheck!.result.message;
  String? get suggestion => details.safeSuggestion;
  AgentManagementDetailsHandle? get detailsHandle => details.detailsHandle;
  AgentManagementDetailsHandle? get diagnosticHandle => connectionCheck == null
      ? details.detailsHandle
      : connectionCheck!.result.detailsHandle;
  AgentManagementConnectionCheckSummary? get connectionTest =>
      connectionCheck?.result ?? details.connectionTest;
  bool get _hasExplicitModels => connectionCheck?.models.isNotEmpty == true;
  List<AgentModelInfo> get models =>
      _hasExplicitModels ? connectionCheck!.models : details.detectedModels;
  DateTime? get modelsUpdatedAt => _hasExplicitModels
      ? connectionCheck!.modelsUpdatedAt
      : details.modelsUpdatedAt;
  String? get modelSource =>
      _hasExplicitModels ? connectionCheck!.modelSource : details.modelSource;
  bool get configExists => confirmedConfigExists ?? details.configExists;
  DateTime? get configModifiedAt =>
      confirmedConfigModifiedAt ?? details.configModifiedAt;
  int get availableLogFileCount =>
      logFileCount ?? details.availableLogFileCount;
  bool get installed => installationState == AgentInstallationState.installed;
  bool get updateAvailable => versionState == AgentVersionState.updateAvailable;
  bool get needsAttention =>
      installed &&
      (accountState == AgentAccountState.loggedOut ||
          accountState == AgentAccountState.expired ||
          accountState == AgentAccountState.unavailable ||
          runtimeState == AgentRuntimeState.error ||
          runtimeState == AgentRuntimeState.unavailable ||
          errorMessage != null ||
          versionState == AgentVersionState.checkFailed);
}
