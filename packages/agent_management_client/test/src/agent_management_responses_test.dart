import 'package:agent_management_client/agent_management_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('response collections are immutable and fields retain safe values', () {
    final detectedAt = DateTime.utc(2026, 8, 20);
    final detect = DetectResponse(
      providerId: 'codex',
      detectedAt: detectedAt,
      installed: true,
      executablePath: '/bin/codex',
      version: '1.2.3',
      accountStatus: AgentAccountStatus.loggedIn,
      accountLabel: 'Authenticated',
      configPath: '/config',
      configExists: true,
      logPaths: const <String>['/log'],
      failureStage: AgentManagementFailureStage.versionDetection,
      failureCode: 'fixture',
    );
    expect(detect.providerId, 'codex');
    expect(detect.detectedAt, detectedAt);
    expect(detect.installed, isTrue);
    expect(detect.executablePath, '/bin/codex');
    expect(detect.version, '1.2.3');
    expect(detect.accountStatus, AgentAccountStatus.loggedIn);
    expect(detect.accountLabel, 'Authenticated');
    expect(detect.configPath, '/config');
    expect(detect.configExists, isTrue);
    expect(detect.failureStage, AgentManagementFailureStage.versionDetection);
    expect(detect.failureCode, 'fixture');
    expect(() => detect.logPaths.add('/other'), throwsUnsupportedError);

    final connection = ConnectionTestResponse(
      success: true,
      testedAt: detectedAt,
      elapsed: const Duration(milliseconds: 2),
      cliCallable: true,
      accountValid: true,
      protocolReady: true,
      models: <AgentModelInfo>[
        AgentModelInfo(id: 'model', model: 'model', displayName: 'Model'),
      ],
      capabilityIds: const <String>['prompt'],
      failureStage: AgentManagementFailureStage.protocolHandshake,
      failureCode: 'none',
      protocolVersion: '1',
      agentName: 'Agent',
      agentVersion: '2.0.0',
    );
    expect(connection.success, isTrue);
    expect(connection.testedAt, detectedAt);
    expect(connection.elapsed, const Duration(milliseconds: 2));
    expect(connection.cliCallable, isTrue);
    expect(connection.accountValid, isTrue);
    expect(connection.protocolReady, isTrue);
    expect(
      connection.failureStage,
      AgentManagementFailureStage.protocolHandshake,
    );
    expect(connection.failureCode, 'none');
    expect(connection.protocolVersion, '1');
    expect(connection.agentName, 'Agent');
    expect(connection.agentVersion, '2.0.0');
    expect(connection.models.clear, throwsUnsupportedError);
    expect(connection.capabilityIds.clear, throwsUnsupportedError);
  });

  test('configuration and log response models expose their full contract', () {
    final loadedAt = DateTime.utc(2026, 8, 20);
    final document = ConfigurationDocumentResponse(
      path: '/config',
      format: 'json',
      contents: '{}',
      maskedContents: '{}',
      exists: true,
      loadedAt: loadedAt,
      modifiedAt: loadedAt,
      signature: 'signature',
    );
    final saved = ConfigurationSaveResponse(
      document: document,
      backupPath: '/backup',
    );
    final log = LogEntryResponse(
      id: 'id',
      sourcePath: '/log',
      message: 'safe',
      level: AgentManagementLogLevel.warning,
      timestamp: loadedAt,
    );

    expect(document.path, '/config');
    expect(document.format, 'json');
    expect(document.contents, '{}');
    expect(document.maskedContents, '{}');
    expect(document.exists, isTrue);
    expect(document.loadedAt, loadedAt);
    expect(document.modifiedAt, loadedAt);
    expect(document.signature, 'signature');
    expect(saved.document, same(document));
    expect(saved.backupPath, '/backup');
    expect(log.id, 'id');
    expect(log.sourcePath, '/log');
    expect(log.message, 'safe');
    expect(log.level, AgentManagementLogLevel.warning);
    expect(log.timestamp, loadedAt);
  });

  test('typed configuration exception renders no configuration contents', () {
    const validation = ConfigurationValidationException('invalid-json');

    expect(validation.code, 'invalid-json');
    expect(
      validation.toString(),
      'ConfigurationValidationException(invalid-json)',
    );
  });

  test('every neutral enum value stays addressable', () {
    expect(AgentAccountStatus.values, hasLength(4));
    expect(AgentManagementFailureStage.values, hasLength(8));
    expect(AgentManagementLogLevel.values, hasLength(4));
  });
}
