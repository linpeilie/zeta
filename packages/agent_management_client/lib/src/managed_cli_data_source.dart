// Public dependency names intentionally differ from private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_management_client/src/agent_management_data_source.dart';
import 'package:agent_management_client/src/agent_management_file_system.dart';
import 'package:agent_management_client/src/agent_management_responses.dart';
import 'package:agent_management_client/src/cli_process_runner.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:toml/toml.dart';
import 'package:zeta_logging/zeta_logging.dart';

/// Resolves one user-selected vendor CLI path through the vendor-owned locator.
typedef AgentManagementCliPathResolver =
    Future<ResolvedCliProcessCommand?> Function(String path);

/// Locates a vendor CLI from its neutral provider configuration.
typedef AgentManagementCliLocator = Future<ResolvedCliProcessCommand?> Function(
  AgentProviderConfig config,
);

/// Runs a prompt-free vendor protocol probe.
typedef AgentManagementProtocolProbe =
    Future<AgentProtocolProbeResponse> Function(AgentProviderConfig config);

/// Reads whitelisted account evidence without returning credentials.
typedef AgentManagementAccountProbe = Future<AccountProbeResponse> Function(
  ResolvedCliProcessCommand command,
  Map<String, String> environment,
);

/// Safe account evidence returned by an injected vendor probe.
final class AccountProbeResponse {
  /// Creates account evidence.
  const AccountProbeResponse({required this.status, this.label});

  /// Provider-neutral account status.
  final AgentAccountStatus status;

  /// Optional non-identity label.
  final String? label;
}

/// Whitelisted output from an injected vendor protocol probe.
final class AgentProtocolProbeResponse {
  /// Creates a protocol probe response.
  AgentProtocolProbeResponse({
    required this.success,
    required this.accountValid,
    List<AgentModelInfo> models = const <AgentModelInfo>[],
    List<String> capabilityIds = const <String>[],
    this.failureCode,
    this.protocolVersion,
    this.agentName,
    this.agentVersion,
  }) : models = List<AgentModelInfo>.unmodifiable(models),
       capabilityIds = List<String>.unmodifiable(capabilityIds);

  /// Whether protocol initialization completed.
  final bool success;

  /// Whether the probe found valid account evidence.
  final bool accountValid;

  /// Prompt-free model catalog results.
  final List<AgentModelInfo> models;

  /// Stable neutral capability ids.
  final List<String> capabilityIds;

  /// Stable failure code, when unsuccessful.
  final String? failureCode;

  /// Whitelisted protocol version.
  final String? protocolVersion;

  /// Whitelisted agent name.
  final String? agentName;

  /// Whitelisted agent version.
  final String? agentVersion;
}

/// Shared implementation for vendor-specific management data sources.
base class ManagedCliDataSource implements AgentManagementDataSource {
  /// Creates a vendor-neutral CLI management implementation.
  ManagedCliDataSource({
    required this.providerId,
    required this.configPath,
    required this.configFormat,
    required AgentManagementCliPathResolver resolvePath,
    required AgentManagementCliLocator locate,
    required AgentManagementProtocolProbe protocolProbe,
    required List<String> logDirectories,
    required bool Function(String path) acceptsLogPath,
    AgentManagementAccountProbe? accountProbe,
    List<String> versionArguments = const <String>['--version'],
    CliProcessRunner processRunner = const CliProcessRunner(),
    AgentManagementFileSystem fileSystem = const IoAgentManagementFileSystem(),
    DateTime Function()? now,
  }) : _resolvePath = resolvePath,
       _locate = locate,
       _protocolProbe = protocolProbe,
       _accountProbe = accountProbe,
       _versionArguments = List<String>.unmodifiable(versionArguments),
       _logDirectories = List<String>.unmodifiable(logDirectories),
       _acceptsLogPath = acceptsLogPath,
       _processRunner = processRunner,
       _fileSystem = fileSystem,
       _now = now ?? DateTime.now;

  /// Stable provider id.
  final String providerId;

  /// Absolute current-schema configuration path.
  final String configPath;

  /// Stable `json` or `toml` configuration format.
  final String configFormat;

  final AgentManagementCliPathResolver _resolvePath;
  final AgentManagementCliLocator _locate;
  final AgentManagementProtocolProbe _protocolProbe;
  final AgentManagementAccountProbe? _accountProbe;
  final List<String> _versionArguments;
  final List<String> _logDirectories;
  final bool Function(String path) _acceptsLogPath;
  final CliProcessRunner _processRunner;
  final AgentManagementFileSystem _fileSystem;
  final DateTime Function() _now;

  @override
  Future<DetectResponse> detect({required String executablePath}) async {
    final command = await _resolvePath(executablePath);
    final configMetadata = await _fileSystem.metadata(configPath);
    final logs = await discoverLogPaths();
    if (command == null) {
      return DetectResponse(
        providerId: providerId,
        detectedAt: _now(),
        installed: false,
        accountStatus: AgentAccountStatus.unknown,
        configPath: configPath,
        configExists: configMetadata.isFile,
        logPaths: logs,
        failureStage: AgentManagementFailureStage.fileDetection,
        failureCode: 'cli-not-found',
      );
    }

    CliProcessResult versionResult;
    try {
      versionResult = await _processRunner.run(
        command,
        _versionArguments,
        timeout: const Duration(seconds: 10),
      );
    } on Object {
      return DetectResponse(
        providerId: providerId,
        detectedAt: _now(),
        installed: false,
        executablePath: command.displayPath ?? executablePath,
        accountStatus: AgentAccountStatus.unavailable,
        configPath: configPath,
        configExists: configMetadata.isFile,
        logPaths: logs,
        failureStage: AgentManagementFailureStage.cliStartup,
        failureCode: 'cli-start-failed',
      );
    }
    final version = _semanticVersion(versionResult.combinedOutput);
    final versionReady = versionResult.succeeded && version != null;

    var account = const AccountProbeResponse(
      status: AgentAccountStatus.unknown,
    );
    final probe = _accountProbe;
    if (probe != null) {
      try {
        account = await probe(command, const <String, String>{});
      } on Object {
        account = const AccountProbeResponse(
          status: AgentAccountStatus.unavailable,
        );
      }
    }
    return DetectResponse(
      providerId: providerId,
      detectedAt: _now(),
      installed: true,
      executablePath: command.displayPath ?? executablePath,
      version: version,
      accountStatus: account.status,
      accountLabel: account.label,
      configPath: configPath,
      configExists: configMetadata.isFile,
      logPaths: logs,
      failureStage: versionReady
          ? null
          : AgentManagementFailureStage.versionDetection,
      failureCode: versionReady ? null : 'version-unavailable',
    );
  }

  @override
  Future<ConnectionTestResponse> testConnection({
    required AgentProviderConfig config,
  }) async {
    final testedAt = _now();
    final stopwatch = Stopwatch()..start();
    final command = await _locate(config);
    if (command == null) {
      stopwatch.stop();
      return ConnectionTestResponse(
        success: false,
        testedAt: testedAt,
        elapsed: stopwatch.elapsed,
        cliCallable: false,
        accountValid: false,
        protocolReady: false,
        failureStage: AgentManagementFailureStage.fileDetection,
        failureCode: 'cli-not-found',
      );
    }
    try {
      final result = await _protocolProbe(config).timeout(
        const Duration(seconds: 60),
      );
      stopwatch.stop();
      return ConnectionTestResponse(
        success: result.success,
        testedAt: testedAt,
        elapsed: stopwatch.elapsed,
        cliCallable: true,
        accountValid: result.accountValid,
        protocolReady: result.success,
        models: result.models,
        capabilityIds: result.capabilityIds,
        failureStage: result.success
            ? null
            : AgentManagementFailureStage.protocolHandshake,
        failureCode: result.failureCode,
        protocolVersion: result.protocolVersion,
        agentName: result.agentName,
        agentVersion: result.agentVersion,
      );
    } on TimeoutException {
      stopwatch.stop();
      return ConnectionTestResponse(
        success: false,
        testedAt: testedAt,
        elapsed: stopwatch.elapsed,
        cliCallable: true,
        accountValid: false,
        protocolReady: false,
        failureStage: AgentManagementFailureStage.protocolHandshake,
        failureCode: 'probe-timeout',
      );
    } on Object {
      stopwatch.stop();
      return ConnectionTestResponse(
        success: false,
        testedAt: testedAt,
        elapsed: stopwatch.elapsed,
        cliCallable: true,
        accountValid: false,
        protocolReady: false,
        failureStage: AgentManagementFailureStage.protocolHandshake,
        failureCode: 'probe-failed',
      );
    }
  }

  @override
  Future<ConfigurationDocumentResponse> readConfiguration() async {
    final metadata = await _fileSystem.metadata(configPath);
    if (metadata.isLink) {
      throw FileSystemException(
        'Refusing symbolic-link configuration',
        configPath,
      );
    }
    final exists = metadata.isFile;
    final contents = exists ? await _fileSystem.readText(configPath) : '';
    return ConfigurationDocumentResponse(
      path: configPath,
      format: configFormat,
      contents: contents,
      maskedContents: maskSensitiveConfiguration(contents),
      exists: exists,
      loadedAt: _now(),
      modifiedAt: metadata.modifiedAt,
      signature: configurationSignature(contents, metadata.modifiedAt),
    );
  }

  @override
  Future<ConfigurationSaveResponse> saveConfiguration({
    required String contents,
  }) async {
    final validationCode = validateConfiguration(configFormat, contents);
    if (validationCode != null) {
      throw ConfigurationValidationException(validationCode);
    }
    final metadata = await _fileSystem.metadata(configPath);
    if (metadata.isLink) {
      throw FileSystemException(
        'Refusing symbolic-link configuration',
        configPath,
      );
    }
    final stamp = _now().microsecondsSinceEpoch;
    final backupPath = await _fileSystem.writeTextAtomically(
      configPath,
      contents,
      backupSuffix: '.zeta-backup-$stamp',
    );
    return ConfigurationSaveResponse(
      document: await readConfiguration(),
      backupPath: backupPath,
    );
  }

  @override
  Future<List<String>> discoverLogPaths() async {
    final paths = <String>[];
    for (final directory in _logDirectories) {
      final candidates = await _fileSystem.listFiles(
        directory,
        recursive: true,
      );
      paths.addAll(candidates.where(_acceptsLogPath));
    }
    paths.sort();
    return List<String>.unmodifiable(paths.toSet());
  }

  @override
  Future<List<LogEntryResponse>> readLogs(
    String path, {
    int maxLines = 1000,
  }) async {
    if (maxLines <= 0) {
      return const <LogEntryResponse>[];
    }
    final metadata = await _fileSystem.metadata(path);
    if (!metadata.isFile || metadata.isLink) {
      return const <LogEntryResponse>[];
    }
    final tail = await _fileSystem.readTextTail(path, maxBytes: 512 * 1024);
    final allLines = const LineSplitter().convert(tail.contents);
    final lines = tail.skippedPrefix && allLines.isNotEmpty
        ? allLines.skip(1)
        : allLines;
    final entries = <LogEntryResponse>[];
    var index = 0;
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      entries.add(
        LogEntryResponse(
          id: '$path:${index++}',
          sourcePath: path,
          message: redactSensitiveText(line),
          level: _logLevel(line),
          timestamp: _timestamp(line),
        ),
      );
    }
    final start = entries.length > maxLines ? entries.length - maxLines : 0;
    return List<LogEntryResponse>.unmodifiable(entries.sublist(start));
  }
}

/// Codex-specific management Data source configuration.
final class CodexAgentManagementDataSource extends ManagedCliDataSource {
  /// Creates a Codex management source with vendor-owned locator seams.
  CodexAgentManagementDataSource({
    required super.configPath,
    required super.resolvePath,
    required super.locate,
    required super.protocolProbe,
    required String logDirectory,
    super.accountProbe,
    super.processRunner,
    super.fileSystem,
    super.now,
  }) : super(
         providerId: 'codex',
         configFormat: 'toml',
         logDirectories: <String>[logDirectory],
         acceptsLogPath: _acceptsCodexLog,
       );
}

/// Grok-specific management Data source configuration.
final class GrokAgentManagementDataSource extends ManagedCliDataSource {
  /// Creates a Grok management source with vendor-owned locator seams.
  GrokAgentManagementDataSource({
    required super.configPath,
    required super.resolvePath,
    required super.locate,
    required super.protocolProbe,
    required String logDirectory,
    super.accountProbe,
    super.processRunner,
    super.fileSystem,
    super.now,
  }) : super(
         providerId: 'grok',
         configFormat: 'toml',
         logDirectories: <String>[logDirectory],
         acceptsLogPath: _acceptsGrokLog,
       );
}

/// Claude Code-specific management Data source configuration.
final class ClaudeCodeAgentManagementDataSource extends ManagedCliDataSource {
  /// Creates a Claude Code source with vendor-owned locator and auth seams.
  ClaudeCodeAgentManagementDataSource({
    required super.configPath,
    required super.resolvePath,
    required super.locate,
    required super.protocolProbe,
    required String logDirectory,
    required super.accountProbe,
    super.processRunner,
    super.fileSystem,
    super.now,
  }) : super(
         providerId: 'claude-code',
         configFormat: 'json',
         logDirectories: <String>[logDirectory],
         acceptsLogPath: _acceptsClaudeLog,
       );
}

/// Validates current-schema management configuration text.
String? validateConfiguration(String format, String contents) {
  try {
    switch (format) {
      case 'json':
        final decoded = jsonDecode(contents);
        if (decoded is! Map) {
          return 'json-object-required';
        }
      case 'toml':
        TomlDocument.parse(contents);
      default:
        return 'unsupported-config-format';
    }
  } on FormatException {
    return 'invalid-$format';
  }
  return null;
}

/// Masks common JSON/TOML credential assignments without retaining values.
String maskSensitiveConfiguration(String contents) {
  final assignment = RegExp(
    r'^(\s*(?:api[_-]?key|token|secret|password|authorization|access[_-]?token|refresh[_-]?token)\s*=\s*)([^\r\n#]+)',
    caseSensitive: false,
    multiLine: true,
  );
  final tomlMasked = contents.replaceAllMapped(
    assignment,
    (match) => '${match.group(1)}"••••••"',
  );
  final jsonField = RegExp(
    r'("(?:api[_-]?key|token|secret|password|authorization|access[_-]?token|refresh[_-]?token)"\s*:\s*)"[^"]*"',
    caseSensitive: false,
  );
  return tomlMasked.replaceAllMapped(
    jsonField,
    (match) => '${match.group(1)}"••••••"',
  );
}

/// Builds a non-cryptographic conflict signature without retaining contents.
String configurationSignature(String contents, DateTime? modifiedAt) {
  var hash = 0x811c9dc5;
  for (final unit in contents.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return '${modifiedAt?.millisecondsSinceEpoch ?? 0}:${contents.length}:$hash';
}

bool _acceptsCodexLog(String path) => path.toLowerCase().endsWith('.log');

bool _acceptsGrokLog(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.jsonl') ||
      lower.endsWith('.log') ||
      lower.endsWith('.txt');
}

bool _acceptsClaudeLog(String path) => path.toLowerCase().endsWith('.log');

String? _semanticVersion(String output) => RegExp(
  r'\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b',
).firstMatch(output)?.group(1);

AgentManagementLogLevel _logLevel(String line) {
  final normalized = line.toLowerCase();
  if (normalized.contains('error') || normalized.contains('fatal')) {
    return AgentManagementLogLevel.error;
  }
  if (normalized.contains('warn')) {
    return AgentManagementLogLevel.warning;
  }
  if (normalized.contains('debug') || normalized.contains('trace')) {
    return AgentManagementLogLevel.debug;
  }
  return AgentManagementLogLevel.info;
}

DateTime? _timestamp(String line) {
  final match = RegExp(
    r'(\d{4}-\d{2}-\d{2}[T ][0-9:.+-]+(?:Z)?)',
  ).firstMatch(line);
  return match == null
      ? null
      : DateTime.tryParse(match.group(1)!.replaceFirst(' ', 'T'));
}
