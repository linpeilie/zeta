import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

extension AgentAccountStateL10n on AgentAccountState {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AgentAccountState.unknown => l10n.mgmtAccountUnknown,
    AgentAccountState.checking => l10n.mgmtAccountChecking,
    AgentAccountState.loggedIn => l10n.mgmtAccountLoggedInShort,
    AgentAccountState.loggedOut => l10n.mgmtAccountLoggedOut,
    AgentAccountState.expired => l10n.mgmtAccountExpired,
    AgentAccountState.notRequired => l10n.mgmtAccountNotRequired,
    AgentAccountState.unavailable => l10n.mgmtAccountUnknown,
  };
}

extension AgentRuntimeStateL10n on AgentRuntimeState {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AgentRuntimeState.notRunning => l10n.mgmtRuntimeNotRunning,
    AgentRuntimeState.idle => l10n.mgmtRuntimeIdle,
    AgentRuntimeState.starting => l10n.mgmtRuntimeStarting,
    AgentRuntimeState.running => l10n.mgmtRunning,
    AgentRuntimeState.stopping => l10n.mgmtRuntimeStopping,
    AgentRuntimeState.error => l10n.mgmtRuntimeError,
    AgentRuntimeState.unavailable => l10n.mgmtRuntimeUnavailable,
    AgentRuntimeState.disabled => l10n.mgmtRuntimeDisabled,
  };
}

extension AgentDiagnosticStageL10n on AgentDiagnosticStage {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    AgentDiagnosticStage.fileDetection => l10n.mgmtStageFileDetection,
    AgentDiagnosticStage.cliStartup => l10n.mgmtStageCliStartup,
    AgentDiagnosticStage.versionDetection => l10n.mgmtStageVersionDetection,
    AgentDiagnosticStage.accountAuthentication =>
      l10n.mgmtStageAccountAuthentication,
    AgentDiagnosticStage.protocolHandshake => l10n.mgmtStageProtocolHandshake,
    AgentDiagnosticStage.modelLoading => l10n.mgmtStageModelLoading,
    AgentDiagnosticStage.configurationRead => l10n.mgmtStageConfigurationRead,
    AgentDiagnosticStage.testRequest => l10n.mgmtStageTestRequest,
    AgentDiagnosticStage.processExit => l10n.mgmtStageProcessExit,
  };
}
