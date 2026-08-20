import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_management_client/agent_management_client.dart' as client;
import 'package:agent_management_repository/src/agent_management_models.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';

// Public dependency names intentionally differ from private fields.
// ignore_for_file: prefer_initializing_formals

/// Stable operation categories for Agent management Repository failures.
enum AgentManagementRepositoryOperation {
  /// Resolve a configured management client.
  resolveClient,

  /// Read the current global Provider configuration.
  readProviderConfiguration,

  /// Detect an Agent CLI.
  detect,

  /// Run a prompt-free connection test.
  testConnection,

  /// Read a Provider-owned configuration document.
  readConfiguration,

  /// Save a Provider-owned configuration document.
  saveConfiguration,

  /// Discover Provider-owned log paths.
  discoverLogPaths,

  /// Read redacted Provider logs.
  readLogs,
}

/// Stable failure categories exposed to the application layer.
enum AgentManagementRepositoryFailureCode {
  /// No management client is registered for the requested Provider.
  unknownProvider,

  /// Persisted Provider configuration is missing or inconsistent.
  invalidProviderConfiguration,

  /// A client returned a result for a different Provider id.
  providerResponseMismatch,

  /// Provider-owned configuration contents are invalid.
  invalidConfiguration,

  /// An external client operation failed.
  clientFailure,
}

/// A content-free Agent management Repository failure.
final class AgentManagementRepositoryFailure extends Equatable {
  /// Creates a typed Repository failure.
  const AgentManagementRepositoryFailure({
    required this.providerId,
    required this.operation,
    required this.code,
    required this.diagnosticCode,
  });

  /// Canonical Provider id, or the normalized requested id when unknown.
  final String providerId;

  /// Operation that failed.
  final AgentManagementRepositoryOperation operation;

  /// Stable failure category.
  final AgentManagementRepositoryFailureCode code;

  /// Stable, non-localized diagnostic code.
  final String diagnosticCode;

  @override
  List<Object?> get props => <Object?>[
    providerId,
    operation,
    code,
    diagnosticCode,
  ];
}

/// A typed Repository exception retaining private diagnostic context.
final class AgentManagementRepositoryException implements Exception {
  /// Creates a Repository exception.
  const AgentManagementRepositoryException({
    required this.failure,
    required this.cause,
    required this.stackTrace,
  });

  /// Vendor-neutral failure exposed to the application layer.
  final AgentManagementRepositoryFailure failure;

  /// Original exception retained for sanitized diagnostic logging only.
  final Object cause;

  /// Original stack trace retained for sanitized diagnostic logging only.
  final StackTrace stackTrace;

  @override
  String toString() =>
      'AgentManagementRepositoryException('
      '${failure.operation.name}, ${failure.code.name}, '
      '${failure.diagnosticCode})';
}

/// Stateless domain boundary for Agent detection, diagnostics, configuration,
/// and logs.
final class AgentManagementRepository {
  /// Creates a Repository from canonical Provider ids to management clients.
  AgentManagementRepository({
    required Map<String, client.AgentManagementDataSource> managementClients,
    required ProviderConfigStore configStore,
  }) : _managementClients = _freezeClients(managementClients),
       _configStore = configStore;

  final Map<String, client.AgentManagementDataSource> _managementClients;
  final ProviderConfigStore _configStore;

  /// Built-in immutable management definitions in stable display order.
  List<AgentDefinition> get definitions => AgentDefinition.all;

  /// Detects one Agent CLI without sending a model prompt.
  ///
  /// When [executablePath] is omitted, the current Provider configuration's
  /// `cliPath` extension or command is used. The routed Provider id remains the
  /// source of truth and must match the id returned by the Data client.
  Future<AgentDetection> detect(
    String providerId, {
    String? executablePath,
  }) async {
    final resolved = _resolveClient(providerId);
    final requestedPath = executablePath?.trim();
    final path = requestedPath == null || requestedPath.isEmpty
        ? _detectionPath(await _providerConfiguration(resolved.providerId))
        : requestedPath;
    final response = await _clientCall(
      providerId: resolved.providerId,
      operation: AgentManagementRepositoryOperation.detect,
      call: () => resolved.source.detect(executablePath: path),
    );
    if (response.providerId.trim() != resolved.providerId) {
      _fail(
        providerId: resolved.providerId,
        operation: AgentManagementRepositoryOperation.detect,
        code: AgentManagementRepositoryFailureCode.providerResponseMismatch,
        diagnosticCode: 'provider_response_mismatch',
        cause: StateError('Management response Provider id did not match'),
      );
    }
    return _mapDetection(resolved.providerId, response);
  }

  /// Runs a user-requested, prompt-free connection test.
  Future<AgentConnectionTest> testConnection(String providerId) async {
    final resolved = _resolveClient(providerId);
    final configuration = await _providerConfiguration(resolved.providerId);
    final response = await _clientCall(
      providerId: resolved.providerId,
      operation: AgentManagementRepositoryOperation.testConnection,
      call: () => resolved.source.testConnection(config: configuration),
    );
    return _mapConnectionTest(resolved.providerId, response);
  }

  /// Reads the current Provider-owned configuration document.
  Future<AgentConfigurationDocument> readConfiguration(
    String providerId,
  ) async {
    final resolved = _resolveClient(providerId);
    final response = await _clientCall(
      providerId: resolved.providerId,
      operation: AgentManagementRepositoryOperation.readConfiguration,
      call: resolved.source.readConfiguration,
    );
    return _mapConfigurationDocument(response);
  }

  /// Atomically saves current-schema Provider-owned [contents].
  ///
  /// The Data boundary validates its configured format again before writing.
  Future<AgentConfigurationSaveResult> saveConfiguration(
    String providerId, {
    required String contents,
  }) async {
    final resolved = _resolveClient(providerId);
    final response = await _clientCall(
      providerId: resolved.providerId,
      operation: AgentManagementRepositoryOperation.saveConfiguration,
      call: () => resolved.source.saveConfiguration(contents: contents),
    );
    return AgentConfigurationSaveResult(
      document: _mapConfigurationDocument(response.document),
      backupPath: response.backupPath,
    );
  }

  /// Purely validates current-schema configuration [contents] for [format].
  ///
  /// Presentation must dispatch this through a Bloc event rather than invoking
  /// the Repository directly from a Widget.
  AgentConfigurationValidation validateConfiguration({
    required String format,
    required String contents,
  }) {
    final failureCode = client.validateConfiguration(
      format.trim().toLowerCase(),
      contents,
    );
    return failureCode == null
        ? AgentConfigurationValidation.valid
        : AgentConfigurationValidation(failureCode: failureCode);
  }

  /// Discovers Provider-owned log paths in deterministic order.
  Future<List<String>> discoverLogPaths(String providerId) async {
    final resolved = _resolveClient(providerId);
    final paths = await _clientCall(
      providerId: resolved.providerId,
      operation: AgentManagementRepositoryOperation.discoverLogPaths,
      call: resolved.source.discoverLogPaths,
    );
    return _sortedUniquePaths(paths);
  }

  /// Reads and merges redacted logs from [paths].
  ///
  /// The returned list is globally bounded by [maxLines] after deterministic
  /// timestamp/id ordering. A non-positive bound returns an empty list without
  /// invoking the Data client.
  Future<List<AgentLogEntry>> readLogs(
    String providerId,
    Iterable<String> paths, {
    int maxLines = 1000,
  }) async {
    final resolved = _resolveClient(providerId);
    if (maxLines <= 0) {
      return const <AgentLogEntry>[];
    }
    final entries = <AgentLogEntry>[];
    for (final path in paths.toSet()) {
      final responses = await _clientCall(
        providerId: resolved.providerId,
        operation: AgentManagementRepositoryOperation.readLogs,
        call: () => resolved.source.readLogs(path, maxLines: maxLines),
      );
      entries.addAll(responses.map(_mapLogEntry));
    }
    entries.sort(_compareLogEntries);
    final start = entries.length > maxLines ? entries.length - maxLines : 0;
    return List<AgentLogEntry>.unmodifiable(entries.sublist(start));
  }

  _ResolvedManagementClient _resolveClient(String providerId) {
    final normalized = providerId.trim();
    final source = _managementClients[normalized];
    if (normalized.isEmpty || source == null) {
      _fail(
        providerId: normalized,
        operation: AgentManagementRepositoryOperation.resolveClient,
        code: AgentManagementRepositoryFailureCode.unknownProvider,
        diagnosticCode: 'provider_unknown',
        cause: ArgumentError.value(providerId, 'providerId'),
      );
    }
    return _ResolvedManagementClient(normalized, source);
  }

  Future<AgentProviderConfig> _providerConfiguration(String providerId) async {
    late List<AgentProviderConfig> configurations;
    try {
      configurations = await _configStore.read();
    } on AgentConfigDecodeException catch (error, stackTrace) {
      throw _exception(
        providerId: providerId,
        operation: AgentManagementRepositoryOperation.readProviderConfiguration,
        code: AgentManagementRepositoryFailureCode.invalidProviderConfiguration,
        diagnosticCode: 'provider_configuration_invalid',
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw _exception(
        providerId: providerId,
        operation: AgentManagementRepositoryOperation.readProviderConfiguration,
        code: AgentManagementRepositoryFailureCode.clientFailure,
        diagnosticCode: 'provider_configuration_read_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    AgentProviderConfig? configuration;
    for (final candidate in configurations) {
      if (candidate.id.trim() != providerId) {
        continue;
      }
      if (configuration != null) {
        _fail(
          providerId: providerId,
          operation:
              AgentManagementRepositoryOperation.readProviderConfiguration,
          code:
              AgentManagementRepositoryFailureCode.invalidProviderConfiguration,
          diagnosticCode: 'provider_configuration_duplicate',
          cause: StateError('Duplicate Provider configuration'),
        );
      }
      configuration = candidate;
    }
    configuration ??= _defaultConfiguration(providerId);
    if (configuration == null) {
      _fail(
        providerId: providerId,
        operation: AgentManagementRepositoryOperation.readProviderConfiguration,
        code: AgentManagementRepositoryFailureCode.invalidProviderConfiguration,
        diagnosticCode: 'provider_configuration_missing',
        cause: StateError('Provider configuration is missing'),
      );
    }
    if (configuration.id != providerId) {
      _fail(
        providerId: providerId,
        operation: AgentManagementRepositoryOperation.readProviderConfiguration,
        code: AgentManagementRepositoryFailureCode.invalidProviderConfiguration,
        diagnosticCode: 'provider_id_not_canonical',
        cause: StateError('Provider id is not canonical'),
      );
    }
    final definition = AgentDefinition.byProviderId(providerId);
    if (definition != null && configuration.kind != definition.providerKind) {
      _fail(
        providerId: providerId,
        operation: AgentManagementRepositoryOperation.readProviderConfiguration,
        code: AgentManagementRepositoryFailureCode.invalidProviderConfiguration,
        diagnosticCode: 'provider_kind_mismatch',
        cause: StateError('Provider kind does not match management client'),
      );
    }
    if (configuration.command.trim().isEmpty) {
      _fail(
        providerId: providerId,
        operation: AgentManagementRepositoryOperation.readProviderConfiguration,
        code: AgentManagementRepositoryFailureCode.invalidProviderConfiguration,
        diagnosticCode: 'provider_command_missing',
        cause: StateError('Provider command is missing'),
      );
    }
    return configuration;
  }

  Future<T> _clientCall<T>({
    required String providerId,
    required AgentManagementRepositoryOperation operation,
    required Future<T> Function() call,
  }) async {
    try {
      return await call();
    } on client.ConfigurationValidationException catch (error, stackTrace) {
      throw _exception(
        providerId: providerId,
        operation: operation,
        code: AgentManagementRepositoryFailureCode.invalidConfiguration,
        diagnosticCode: error.code,
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw _exception(
        providerId: providerId,
        operation: operation,
        code: AgentManagementRepositoryFailureCode.clientFailure,
        diagnosticCode: '${operation.name}_failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

Map<String, client.AgentManagementDataSource> _freezeClients(
  Map<String, client.AgentManagementDataSource> clients,
) {
  final result = <String, client.AgentManagementDataSource>{};
  for (final entry in clients.entries) {
    final providerId = entry.key.trim();
    if (providerId.isEmpty) {
      throw ArgumentError.value(entry.key, 'managementClients', 'blank id');
    }
    if (result.containsKey(providerId)) {
      throw ArgumentError.value(
        entry.key,
        'managementClients',
        'duplicate normalized id',
      );
    }
    result[providerId] = entry.value;
  }
  return Map<String, client.AgentManagementDataSource>.unmodifiable(result);
}

AgentProviderConfig? _defaultConfiguration(String providerId) {
  return switch (providerId) {
    defaultAgentProviderId => AgentProviderConfig.defaultCodex,
    grokAgentProviderId => AgentProviderConfig.defaultGrok,
    defaultClaudeCodeProviderId => AgentProviderConfig.defaultClaudeCode,
    _ => null,
  };
}

String _detectionPath(AgentProviderConfig configuration) {
  final storedPath = configuration.extra['cliPath'];
  if (storedPath is String && storedPath.trim().isNotEmpty) {
    return storedPath.trim();
  }
  return configuration.command.trim();
}

AgentDetection _mapDetection(
  String providerId,
  client.DetectResponse response,
) {
  return AgentDetection(
    providerId: providerId,
    detectedAt: response.detectedAt,
    installed: response.installed,
    executablePath: response.executablePath,
    version: response.version,
    accountState: _mapAccountState(response.accountStatus),
    accountLabel: response.accountLabel,
    configurationPath: response.configPath,
    configurationExists: response.configExists,
    logPaths: _sortedUniquePaths(response.logPaths),
    diagnostic: _mapDiagnostic(
      response.failureStage,
      response.failureCode,
    ),
  );
}

AgentConnectionTest _mapConnectionTest(
  String providerId,
  client.ConnectionTestResponse response,
) {
  return AgentConnectionTest(
    providerId: providerId,
    success: response.success,
    testedAt: response.testedAt,
    elapsed: response.elapsed,
    cliCallable: response.cliCallable,
    accountValid: response.accountValid,
    protocolReady: response.protocolReady,
    models: response.models,
    capabilityIds: response.capabilityIds,
    diagnostic: _mapDiagnostic(
      response.failureStage,
      response.failureCode,
    ),
    protocolVersion: response.protocolVersion,
    agentName: response.agentName,
    agentVersion: response.agentVersion,
  );
}

AgentConfigurationDocument _mapConfigurationDocument(
  client.ConfigurationDocumentResponse response,
) {
  return AgentConfigurationDocument(
    path: response.path,
    format: response.format,
    contents: response.contents,
    maskedContents: response.maskedContents,
    exists: response.exists,
    loadedAt: response.loadedAt,
    modifiedAt: response.modifiedAt,
    signature: response.signature,
  );
}

AgentLogEntry _mapLogEntry(client.LogEntryResponse response) {
  return AgentLogEntry(
    id: response.id,
    sourcePath: response.sourcePath,
    message: response.message,
    level: switch (response.level) {
      client.AgentManagementLogLevel.debug => AgentLogLevel.debug,
      client.AgentManagementLogLevel.info => AgentLogLevel.info,
      client.AgentManagementLogLevel.warning => AgentLogLevel.warning,
      client.AgentManagementLogLevel.error => AgentLogLevel.error,
    },
    timestamp: response.timestamp,
  );
}

AgentAccountState _mapAccountState(client.AgentAccountStatus status) {
  return switch (status) {
    client.AgentAccountStatus.unknown => AgentAccountState.unknown,
    client.AgentAccountStatus.loggedIn => AgentAccountState.loggedIn,
    client.AgentAccountStatus.loggedOut => AgentAccountState.loggedOut,
    client.AgentAccountStatus.unavailable => AgentAccountState.unavailable,
  };
}

AgentDiagnostic? _mapDiagnostic(
  client.AgentManagementFailureStage? stage,
  String? code,
) {
  if (stage == null && code == null) {
    return null;
  }
  return AgentDiagnostic(
    stage: switch (stage) {
      client.AgentManagementFailureStage.fileDetection =>
        AgentDiagnosticStage.fileDetection,
      client.AgentManagementFailureStage.cliStartup =>
        AgentDiagnosticStage.cliStartup,
      client.AgentManagementFailureStage.versionDetection =>
        AgentDiagnosticStage.versionDetection,
      client.AgentManagementFailureStage.accountAuthentication =>
        AgentDiagnosticStage.accountAuthentication,
      client.AgentManagementFailureStage.protocolHandshake =>
        AgentDiagnosticStage.protocolHandshake,
      client.AgentManagementFailureStage.configurationRead =>
        AgentDiagnosticStage.configurationRead,
      client.AgentManagementFailureStage.configurationWrite =>
        AgentDiagnosticStage.configurationWrite,
      client.AgentManagementFailureStage.logRead =>
        AgentDiagnosticStage.logRead,
      null => null,
    },
    code: code,
  );
}

List<String> _sortedUniquePaths(Iterable<String> paths) {
  final result = paths.toSet().toList()..sort();
  return List<String>.unmodifiable(result);
}

int _compareLogEntries(AgentLogEntry left, AgentLogEntry right) {
  final leftTime = left.timestamp;
  final rightTime = right.timestamp;
  if (leftTime == null && rightTime == null) {
    return left.id.compareTo(right.id);
  }
  if (leftTime == null) {
    return -1;
  }
  if (rightTime == null) {
    return 1;
  }
  final timeComparison = leftTime.compareTo(rightTime);
  return timeComparison == 0 ? left.id.compareTo(right.id) : timeComparison;
}

Never _fail({
  required String providerId,
  required AgentManagementRepositoryOperation operation,
  required AgentManagementRepositoryFailureCode code,
  required String diagnosticCode,
  required Object cause,
}) {
  throw _exception(
    providerId: providerId,
    operation: operation,
    code: code,
    diagnosticCode: diagnosticCode,
    cause: cause,
    stackTrace: StackTrace.current,
  );
}

AgentManagementRepositoryException _exception({
  required String providerId,
  required AgentManagementRepositoryOperation operation,
  required AgentManagementRepositoryFailureCode code,
  required String diagnosticCode,
  required Object cause,
  required StackTrace stackTrace,
}) {
  return AgentManagementRepositoryException(
    failure: AgentManagementRepositoryFailure(
      providerId: providerId,
      operation: operation,
      code: code,
      diagnosticCode: diagnosticCode,
    ),
    cause: cause,
    stackTrace: stackTrace,
  );
}

final class _ResolvedManagementClient {
  const _ResolvedManagementClient(this.providerId, this.source);

  final String providerId;
  final client.AgentManagementDataSource source;
}
