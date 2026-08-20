import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_management_client/agent_management_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';

final class FakeProviderConfigStore implements ProviderConfigStore {
  FakeProviderConfigStore([List<AgentProviderConfig>? configurations])
    : configurations = configurations ?? <AgentProviderConfig>[];

  List<AgentProviderConfig> configurations;
  Object? readError;
  int readCount = 0;
  final writes = <List<AgentProviderConfig>>[];

  @override
  Future<List<AgentProviderConfig>> read() async {
    readCount += 1;
    final error = readError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return List<AgentProviderConfig>.from(configurations);
  }

  @override
  Future<void> write(List<AgentProviderConfig> configs) async {
    writes.add(List<AgentProviderConfig>.from(configs));
  }
}

typedef DetectHandler = Future<DetectResponse> Function(String executablePath);
typedef ConnectionHandler = Future<ConnectionTestResponse> Function(
  AgentProviderConfig config,
);
typedef ReadConfigurationHandler =
    Future<ConfigurationDocumentResponse> Function();
typedef SaveConfigurationHandler = Future<ConfigurationSaveResponse> Function(
  String contents,
);
typedef DiscoverLogsHandler = Future<List<String>> Function();
typedef ReadLogsHandler = Future<List<LogEntryResponse>> Function(
  String path,
  int maxLines,
);

final class FakeManagementDataSource implements AgentManagementDataSource {
  FakeManagementDataSource({required this.providerId});

  final String providerId;
  DetectHandler? onDetect;
  ConnectionHandler? onTestConnection;
  ReadConfigurationHandler? onReadConfiguration;
  SaveConfigurationHandler? onSaveConfiguration;
  DiscoverLogsHandler? onDiscoverLogPaths;
  ReadLogsHandler? onReadLogs;

  final detectedPaths = <String>[];
  final testedConfigurations = <AgentProviderConfig>[];
  int readConfigurationCount = 0;
  final savedContents = <String>[];
  int discoverLogPathsCount = 0;
  final logReads = <(String, int)>[];

  @override
  Future<DetectResponse> detect({required String executablePath}) {
    detectedPaths.add(executablePath);
    final handler = onDetect;
    if (handler != null) {
      return handler(executablePath);
    }
    return Future<DetectResponse>.value(
      detectionResponse(providerId: providerId),
    );
  }

  @override
  Future<ConnectionTestResponse> testConnection({
    required AgentProviderConfig config,
  }) {
    testedConfigurations.add(config);
    final handler = onTestConnection;
    if (handler != null) {
      return handler(config);
    }
    return Future<ConnectionTestResponse>.value(connectionResponse());
  }

  @override
  Future<ConfigurationDocumentResponse> readConfiguration() {
    readConfigurationCount += 1;
    final handler = onReadConfiguration;
    if (handler != null) {
      return handler();
    }
    return Future<ConfigurationDocumentResponse>.value(configurationDocument());
  }

  @override
  Future<ConfigurationSaveResponse> saveConfiguration({
    required String contents,
  }) {
    savedContents.add(contents);
    final handler = onSaveConfiguration;
    if (handler != null) {
      return handler(contents);
    }
    return Future<ConfigurationSaveResponse>.value(
      ConfigurationSaveResponse(
        document: configurationDocument(contents: contents),
        backupPath: '/config.backup',
      ),
    );
  }

  @override
  Future<List<String>> discoverLogPaths() {
    discoverLogPathsCount += 1;
    final handler = onDiscoverLogPaths;
    if (handler != null) {
      return handler();
    }
    return Future<List<String>>.value(<String>['/agent.log']);
  }

  @override
  Future<List<LogEntryResponse>> readLogs(
    String path, {
    int maxLines = 1000,
  }) {
    logReads.add((path, maxLines));
    final handler = onReadLogs;
    if (handler != null) {
      return handler(path, maxLines);
    }
    return Future<List<LogEntryResponse>>.value(<LogEntryResponse>[]);
  }
}

DetectResponse detectionResponse({
  required String providerId,
  AgentAccountStatus accountStatus = AgentAccountStatus.loggedIn,
  AgentManagementFailureStage? failureStage,
  String? failureCode,
  List<String> logPaths = const <String>['/agent.log'],
}) {
  return DetectResponse(
    providerId: providerId,
    detectedAt: DateTime.utc(2026, 8, 20, 1),
    installed: true,
    executablePath: '/bin/agent',
    version: '1.2.3',
    accountStatus: accountStatus,
    accountLabel: 'team',
    configPath: '/config',
    configExists: true,
    logPaths: logPaths,
    failureStage: failureStage,
    failureCode: failureCode,
  );
}

ConnectionTestResponse connectionResponse({
  bool success = true,
  AgentManagementFailureStage? failureStage,
  String? failureCode,
  List<AgentModelInfo> models = const <AgentModelInfo>[],
  List<String> capabilityIds = const <String>[],
}) {
  return ConnectionTestResponse(
    success: success,
    testedAt: DateTime.utc(2026, 8, 20, 2),
    elapsed: const Duration(milliseconds: 125),
    cliCallable: true,
    accountValid: success,
    protocolReady: success,
    models: models,
    capabilityIds: capabilityIds,
    failureStage: failureStage,
    failureCode: failureCode,
    protocolVersion: '2',
    agentName: 'agent',
    agentVersion: '1.2.3',
  );
}

ConfigurationDocumentResponse configurationDocument({
  String contents = 'model = "safe"',
}) {
  return ConfigurationDocumentResponse(
    path: '/config',
    format: 'toml',
    contents: contents,
    maskedContents: contents,
    exists: true,
    loadedAt: DateTime.utc(2026, 8, 20, 3),
    modifiedAt: DateTime.utc(2026, 8, 20),
    signature: 'signature',
  );
}
