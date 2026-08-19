import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Provider-neutral account evidence returned by management detection.
enum AgentAccountStatus {
  /// No reliable evidence was requested or available.
  unknown,

  /// The provider explicitly reported an authenticated account.
  loggedIn,

  /// The provider explicitly reported no authenticated account.
  loggedOut,

  /// Account evidence could not be read reliably.
  unavailable,
}

/// Provider-neutral stage at which a management operation failed.
enum AgentManagementFailureStage {
  /// Executable or configuration path detection.
  fileDetection,

  /// Native process startup.
  cliStartup,

  /// CLI version parsing.
  versionDetection,

  /// Account status probing.
  accountAuthentication,

  /// Prompt-free provider protocol initialization.
  protocolHandshake,

  /// Configuration read.
  configurationRead,

  /// Configuration validation or write.
  configurationWrite,

  /// Provider log discovery or read.
  logRead,
}

/// Provider-neutral log severity.
enum AgentManagementLogLevel {
  /// Verbose diagnostic information.
  debug,

  /// Informational provider output.
  info,

  /// Recoverable warning output.
  warning,

  /// Error or fatal output.
  error,
}

/// Result of detecting one installed CLI without sending a model prompt.
final class DetectResponse {
  /// Creates an immutable detection response.
  DetectResponse({
    required this.providerId,
    required this.detectedAt,
    required this.installed,
    required this.accountStatus,
    required this.configPath,
    required this.configExists,
    required List<String> logPaths,
    this.executablePath,
    this.version,
    this.accountLabel,
    this.failureStage,
    this.failureCode,
  }) : logPaths = List<String>.unmodifiable(logPaths);

  /// Stable provider id.
  final String providerId;

  /// Time at which detection completed.
  final DateTime detectedAt;

  /// Whether a callable executable was found.
  final bool installed;

  /// Resolved user-visible executable path, when installed.
  final String? executablePath;

  /// Parsed CLI semantic version, when available.
  final String? version;

  /// Whitelisted account evidence.
  final AgentAccountStatus accountStatus;

  /// Whitelisted, non-identity account label.
  final String? accountLabel;

  /// Absolute provider configuration path.
  final String configPath;

  /// Whether the configuration is a regular file.
  final bool configExists;

  /// Discovered provider-owned log paths.
  final List<String> logPaths;

  /// Failure stage for unavailable or partially detected CLIs.
  final AgentManagementFailureStage? failureStage;

  /// Stable, non-localized diagnostic code.
  final String? failureCode;
}

/// Result of a user-requested, prompt-free connection test.
final class ConnectionTestResponse {
  /// Creates an immutable connection response.
  ConnectionTestResponse({
    required this.success,
    required this.testedAt,
    required this.elapsed,
    required this.cliCallable,
    required this.accountValid,
    required this.protocolReady,
    List<AgentModelInfo> models = const <AgentModelInfo>[],
    List<String> capabilityIds = const <String>[],
    this.failureStage,
    this.failureCode,
    this.protocolVersion,
    this.agentName,
    this.agentVersion,
  }) : models = List<AgentModelInfo>.unmodifiable(models),
       capabilityIds = List<String>.unmodifiable(capabilityIds);

  /// Whether all required connection checks passed.
  final bool success;

  /// Time at which the test started.
  final DateTime testedAt;

  /// Total elapsed time.
  final Duration elapsed;

  /// Whether the CLI executable could be resolved.
  final bool cliCallable;

  /// Whether the probe found valid account evidence.
  final bool accountValid;

  /// Whether the provider protocol initialized successfully.
  final bool protocolReady;

  /// Models returned by the prompt-free probe.
  final List<AgentModelInfo> models;

  /// Stable neutral capability ids returned by the probe.
  final List<String> capabilityIds;

  /// Failure stage, if unsuccessful.
  final AgentManagementFailureStage? failureStage;

  /// Stable, non-localized failure code.
  final String? failureCode;

  /// Whitelisted protocol version.
  final String? protocolVersion;

  /// Whitelisted agent name.
  final String? agentName;

  /// Whitelisted agent version.
  final String? agentVersion;
}

/// Current provider configuration document returned by the Data layer.
final class ConfigurationDocumentResponse {
  /// Creates a configuration snapshot.
  const ConfigurationDocumentResponse({
    required this.path,
    required this.format,
    required this.contents,
    required this.maskedContents,
    required this.exists,
    required this.loadedAt,
    required this.signature,
    this.modifiedAt,
  });

  /// Absolute configuration path.
  final String path;

  /// Stable format id such as `json` or `toml`.
  final String format;

  /// Original editable contents; callers must not log this value.
  final String contents;

  /// Redacted contents safe for initial display and diagnostics.
  final String maskedContents;

  /// Whether the file existed when read.
  final bool exists;

  /// Read completion time.
  final DateTime loadedAt;

  /// Last modification time, when the file existed.
  final DateTime? modifiedAt;

  /// Content and metadata signature used for conflict detection.
  final String signature;
}

/// Result of atomically saving a provider configuration document.
final class ConfigurationSaveResponse {
  /// Creates a save result.
  const ConfigurationSaveResponse({required this.document, this.backupPath});

  /// Fresh post-save document.
  final ConfigurationDocumentResponse document;

  /// Backup path created for a previous file, when any.
  final String? backupPath;
}

/// One redacted provider-owned log line.
final class LogEntryResponse {
  /// Creates a log response.
  const LogEntryResponse({
    required this.id,
    required this.sourcePath,
    required this.message,
    required this.level,
    required this.timestamp,
  });

  /// Stable entry id within the read result.
  final String id;

  /// Provider-owned source path.
  final String sourcePath;

  /// Redacted message.
  final String message;

  /// Parsed log severity.
  final AgentManagementLogLevel level;

  /// Parsed timestamp, when present.
  final DateTime? timestamp;
}

/// Configuration contents failed current-schema validation.
final class ConfigurationValidationException implements Exception {
  /// Creates a validation failure with a safe [code].
  const ConfigurationValidationException(this.code);

  /// Stable validation code without raw configuration contents.
  final String code;

  @override
  String toString() => 'ConfigurationValidationException($code)';
}
