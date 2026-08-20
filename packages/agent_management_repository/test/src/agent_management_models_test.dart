import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('built-in definitions are complete, comparable, and discoverable', () {
    const custom = AgentDefinition(
      providerId: 'custom',
      displayName: 'Custom',
      vendor: 'Vendor',
      commandName: 'custom',
      providerKind: AgentProviderKind.acp,
      protocol: 'protocol',
      transport: 'stdio',
      configurationFormat: 'json',
      defaultConfigurationRelativePath: '.custom/config.json',
      packageName: 'custom-package',
      isBeta: true,
    );
    final sameCustom = AgentDefinition(
      providerId: custom.providerId,
      displayName: custom.displayName,
      vendor: custom.vendor,
      commandName: custom.commandName,
      providerKind: custom.providerKind,
      protocol: custom.protocol,
      transport: custom.transport,
      configurationFormat: custom.configurationFormat,
      defaultConfigurationRelativePath: custom.defaultConfigurationRelativePath,
      packageName: custom.packageName,
      isBeta: custom.isBeta,
    );
    expect(
      custom,
      sameCustom,
    );
    expect(custom.isBeta, isTrue);
    expect(AgentDefinition.codex.isBeta, isFalse);
    expect(AgentDefinition.grok.vendor, 'xAI');
    expect(AgentDefinition.grok.packageName, isEmpty);
    expect(AgentDefinition.grok.providerKind, AgentProviderKind.acp);
    expect(AgentDefinition.claudeCode.vendor, 'Anthropic');
    expect(AgentDefinition.claudeCode.commandName, 'claude');
    expect(AgentDefinition.claudeCode.protocol, 'stream-json');
    expect(AgentDefinition.claudeCode.configurationFormat, 'json');
    expect(
      AgentDefinition.claudeCode.defaultConfigurationRelativePath,
      '.claude/settings.json',
    );
    expect(
      AgentDefinition.claudeCode.packageName,
      '@anthropic-ai/claude-code',
    );
    for (final definition in AgentDefinition.all) {
      expect(
        AgentDefinition.byProviderId(definition.providerId),
        same(definition),
      );
    }
    expect(AgentDefinition.byProviderId('missing'), isNull);
  });

  test('detection and diagnostic values are immutable and comparable', () {
    final paths = <String>['/agent.log'];
    const diagnostic = AgentDiagnostic(
      stage: AgentDiagnosticStage.cliStartup,
      code: 'failed',
    );
    final detection = AgentDetection(
      providerId: 'codex',
      detectedAt: DateTime.utc(2026),
      installed: true,
      executablePath: '/bin/codex',
      version: '1.0.0',
      accountState: AgentAccountState.loggedIn,
      accountLabel: 'team',
      configurationPath: '/config',
      configurationExists: true,
      logPaths: paths,
      diagnostic: diagnostic,
    );
    final same = AgentDetection(
      providerId: 'codex',
      detectedAt: DateTime.utc(2026),
      installed: true,
      executablePath: '/bin/codex',
      version: '1.0.0',
      accountState: AgentAccountState.loggedIn,
      accountLabel: 'team',
      configurationPath: '/config',
      configurationExists: true,
      logPaths: const <String>['/agent.log'],
      diagnostic: const AgentDiagnostic(
        stage: AgentDiagnosticStage.cliStartup,
        code: 'failed',
      ),
    );
    paths.clear();

    expect(detection, same);
    expect(
      diagnostic,
      AgentDiagnostic(
        stage: diagnostic.stage,
        code: diagnostic.code,
      ),
    );
    expect(detection.logPaths, <String>['/agent.log']);
    expect(detection.logPaths.clear, throwsUnsupportedError);
  });

  test('connection result freezes lists and compares every field', () {
    final model = AgentModelInfo(
      id: 'model',
      model: 'model',
      displayName: 'Model',
    );
    final models = <AgentModelInfo>[model];
    final capabilities = <String>['tools'];
    final result = AgentConnectionTest(
      providerId: 'codex',
      success: false,
      testedAt: DateTime.utc(2026),
      elapsed: const Duration(seconds: 1),
      cliCallable: true,
      accountValid: false,
      protocolReady: false,
      models: models,
      capabilityIds: capabilities,
      diagnostic: const AgentDiagnostic(
        stage: AgentDiagnosticStage.protocolHandshake,
        code: 'failed',
      ),
      protocolVersion: '2',
      agentName: 'agent',
      agentVersion: '1.0.0',
    );
    final same = AgentConnectionTest(
      providerId: 'codex',
      success: false,
      testedAt: DateTime.utc(2026),
      elapsed: const Duration(seconds: 1),
      cliCallable: true,
      accountValid: false,
      protocolReady: false,
      models: <AgentModelInfo>[model],
      capabilityIds: const <String>['tools'],
      diagnostic: const AgentDiagnostic(
        stage: AgentDiagnosticStage.protocolHandshake,
        code: 'failed',
      ),
      protocolVersion: '2',
      agentName: 'agent',
      agentVersion: '1.0.0',
    );
    models.clear();
    capabilities.clear();

    expect(result, same);
    expect(result.models, <AgentModelInfo>[model]);
    expect(result.capabilityIds, <String>['tools']);
    expect(result.models.clear, throwsUnsupportedError);
    expect(result.capabilityIds.clear, throwsUnsupportedError);
  });

  test('configuration values and validation are comparable', () {
    final document = AgentConfigurationDocument(
      path: '/config',
      format: 'toml',
      contents: 'model = "safe"',
      maskedContents: 'model = "safe"',
      exists: true,
      loadedAt: DateTime.utc(2026),
      modifiedAt: DateTime.utc(2025),
      signature: 'signature',
    );
    final sameDocument = AgentConfigurationDocument(
      path: '/config',
      format: 'toml',
      contents: 'model = "safe"',
      maskedContents: 'model = "safe"',
      exists: true,
      loadedAt: DateTime.utc(2026),
      modifiedAt: DateTime.utc(2025),
      signature: 'signature',
    );
    final save = AgentConfigurationSaveResult(
      document: document,
      backupPath: '/backup',
    );

    expect(document, sameDocument);
    expect(
      save,
      AgentConfigurationSaveResult(
        document: sameDocument,
        backupPath: '/backup',
      ),
    );
    expect(AgentConfigurationValidation.valid.isValid, isTrue);
    final invalid = AgentConfigurationValidation(
      failureCode: <String>['invalid'].single,
    );
    expect(
      invalid,
      AgentConfigurationValidation(failureCode: invalid.failureCode),
    );
    expect(
      const AgentConfigurationValidation(failureCode: 'invalid').isValid,
      isFalse,
    );
  });

  test('log entries compare every redacted domain field', () {
    final timestamp = DateTime.utc(2026);
    final entry = AgentLogEntry(
      id: 'entry',
      sourcePath: '/agent.log',
      message: 'redacted',
      level: AgentLogLevel.warning,
      timestamp: timestamp,
    );

    expect(
      entry,
      AgentLogEntry(
        id: 'entry',
        sourcePath: '/agent.log',
        message: 'redacted',
        level: AgentLogLevel.warning,
        timestamp: timestamp,
      ),
    );
  });
}
