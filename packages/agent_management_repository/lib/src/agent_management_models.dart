import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';

/// Immutable metadata for one Agent CLI supported by the management feature.
final class AgentDefinition extends Equatable {
  /// Creates an Agent management definition.
  const AgentDefinition({
    required this.providerId,
    required this.displayName,
    required this.vendor,
    required this.commandName,
    required this.providerKind,
    required this.protocol,
    required this.transport,
    required this.configurationFormat,
    required this.defaultConfigurationRelativePath,
    required this.packageName,
    this.isBeta = false,
  });

  /// Stable Provider id used by configuration and runtime contracts.
  final String providerId;

  /// Stable product name. Localized surrounding copy remains in Presentation.
  final String displayName;

  /// Stable vendor name.
  final String vendor;

  /// Default executable name.
  final String commandName;

  /// Provider protocol kind required by this Agent.
  final AgentProviderKind providerKind;

  /// Stable protocol label.
  final String protocol;

  /// Stable transport label.
  final String transport;

  /// Current configuration format id.
  final String configurationFormat;

  /// Default configuration path relative to the user's home directory.
  final String defaultConfigurationRelativePath;

  /// Vendor package name, or an empty string when not applicable.
  final String packageName;

  /// Whether the integration is an explicitly opt-in preview.
  final bool isBeta;

  /// Built-in Codex CLI definition.
  static const codex = AgentDefinition(
    providerId: defaultAgentProviderId,
    displayName: 'Codex',
    vendor: 'OpenAI',
    commandName: 'codex',
    providerKind: AgentProviderKind.codexAppServer,
    protocol: 'JSON-RPC',
    transport: 'stdin / stdout',
    configurationFormat: 'toml',
    defaultConfigurationRelativePath: '.codex/config.toml',
    packageName: '@openai/codex',
  );

  /// Built-in Grok CLI definition.
  static const grok = AgentDefinition(
    providerId: grokAgentProviderId,
    displayName: 'Grok',
    vendor: 'xAI',
    commandName: 'grok',
    providerKind: AgentProviderKind.acp,
    protocol: 'ACP JSON-RPC',
    transport: 'stdin / stdout',
    configurationFormat: 'toml',
    defaultConfigurationRelativePath: '.grok/config.toml',
    packageName: '',
  );

  /// Built-in Claude Code CLI definition.
  static const claudeCode = AgentDefinition(
    providerId: defaultClaudeCodeProviderId,
    displayName: 'Claude',
    vendor: 'Anthropic',
    commandName: 'claude',
    providerKind: AgentProviderKind.claudeCode,
    protocol: 'stream-json',
    transport: 'stdin / stdout',
    configurationFormat: 'json',
    defaultConfigurationRelativePath: '.claude/settings.json',
    packageName: '@anthropic-ai/claude-code',
  );

  /// All built-in Agent definitions in stable display order.
  static const all = <AgentDefinition>[codex, grok, claudeCode];

  /// Returns the built-in definition for [providerId], if one exists.
  static AgentDefinition? byProviderId(String providerId) {
    for (final definition in all) {
      if (definition.providerId == providerId) {
        return definition;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => <Object?>[
    providerId,
    displayName,
    vendor,
    commandName,
    providerKind,
    protocol,
    transport,
    configurationFormat,
    defaultConfigurationRelativePath,
    packageName,
    isBeta,
  ];
}

/// Provider-neutral account evidence from a detection operation.
enum AgentAccountState {
  /// No reliable evidence was requested or available.
  unknown,

  /// The Provider explicitly reported an authenticated account.
  loggedIn,

  /// The Provider explicitly reported no authenticated account.
  loggedOut,

  /// Account evidence could not be read reliably.
  unavailable,
}

/// Provider-neutral stage at which an Agent operation failed.
enum AgentDiagnosticStage {
  /// Executable or configuration path detection.
  fileDetection,

  /// Native process startup.
  cliStartup,

  /// CLI version parsing.
  versionDetection,

  /// Account status probing.
  accountAuthentication,

  /// Prompt-free Provider protocol initialization.
  protocolHandshake,

  /// Configuration read.
  configurationRead,

  /// Configuration validation or write.
  configurationWrite,

  /// Provider log discovery or read.
  logRead,
}

/// A content-free diagnostic attached to a domain result.
final class AgentDiagnostic extends Equatable {
  /// Creates a diagnostic from typed stage and stable code.
  const AgentDiagnostic({required this.stage, required this.code});

  /// Failure stage, when the Data source supplied one.
  final AgentDiagnosticStage? stage;

  /// Stable, non-localized diagnostic code.
  final String? code;

  @override
  List<Object?> get props => <Object?>[stage, code];
}

/// Immutable result of detecting one installed Agent CLI.
final class AgentDetection extends Equatable {
  /// Creates a domain detection result.
  AgentDetection({
    required this.providerId,
    required this.detectedAt,
    required this.installed,
    required this.accountState,
    required this.configurationPath,
    required this.configurationExists,
    required Iterable<String> logPaths,
    this.executablePath,
    this.version,
    this.accountLabel,
    this.diagnostic,
  }) : logPaths = List<String>.unmodifiable(logPaths);

  /// Canonical Provider id used to route the operation.
  final String providerId;

  /// Time at which detection completed.
  final DateTime detectedAt;

  /// Whether a callable executable was found.
  final bool installed;

  /// Resolved executable path, when installed.
  final String? executablePath;

  /// Parsed semantic version, when available.
  final String? version;

  /// Whitelisted account evidence.
  final AgentAccountState accountState;

  /// Optional whitelisted, non-identity account label.
  final String? accountLabel;

  /// Absolute Provider configuration path.
  final String configurationPath;

  /// Whether the configuration is a regular file.
  final bool configurationExists;

  /// Discovered Provider-owned log paths.
  final List<String> logPaths;

  /// Content-free diagnostic for a partial or failed detection.
  final AgentDiagnostic? diagnostic;

  @override
  List<Object?> get props => <Object?>[
    providerId,
    detectedAt,
    installed,
    executablePath,
    version,
    accountState,
    accountLabel,
    configurationPath,
    configurationExists,
    logPaths,
    diagnostic,
  ];
}

/// Result of a user-requested, prompt-free connection test.
final class AgentConnectionTest extends Equatable {
  /// Creates a domain connection-test result.
  AgentConnectionTest({
    required this.providerId,
    required this.success,
    required this.testedAt,
    required this.elapsed,
    required this.cliCallable,
    required this.accountValid,
    required this.protocolReady,
    required Iterable<AgentModelInfo> models,
    required Iterable<String> capabilityIds,
    this.diagnostic,
    this.protocolVersion,
    this.agentName,
    this.agentVersion,
  }) : models = List<AgentModelInfo>.unmodifiable(models),
       capabilityIds = List<String>.unmodifiable(capabilityIds);

  /// Canonical Provider id used to route the operation.
  final String providerId;

  /// Whether every required connection check passed.
  final bool success;

  /// Time at which the test started.
  final DateTime testedAt;

  /// Total test duration.
  final Duration elapsed;

  /// Whether the CLI executable could be resolved.
  final bool cliCallable;

  /// Whether valid account evidence was found.
  final bool accountValid;

  /// Whether the Provider protocol initialized successfully.
  final bool protocolReady;

  /// Prompt-free model catalog returned by the test.
  final List<AgentModelInfo> models;

  /// Stable neutral capability ids returned by the test.
  final List<String> capabilityIds;

  /// Content-free diagnostic for an unsuccessful test.
  final AgentDiagnostic? diagnostic;

  /// Whitelisted protocol version.
  final String? protocolVersion;

  /// Whitelisted agent name.
  final String? agentName;

  /// Whitelisted agent version.
  final String? agentVersion;

  @override
  List<Object?> get props => <Object?>[
    providerId,
    success,
    testedAt,
    elapsed,
    cliCallable,
    accountValid,
    protocolReady,
    models,
    capabilityIds,
    diagnostic,
    protocolVersion,
    agentName,
    agentVersion,
  ];
}

/// Editable current-schema Provider configuration snapshot.
final class AgentConfigurationDocument extends Equatable {
  /// Creates a configuration document.
  const AgentConfigurationDocument({
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

  /// Stable current-schema format id.
  final String format;

  /// Original editable contents. This value must never be logged.
  final String contents;

  /// Redacted contents safe for initial display.
  final String maskedContents;

  /// Whether the file existed when read.
  final bool exists;

  /// Read completion time.
  final DateTime loadedAt;

  /// Last modification time, when the file existed.
  final DateTime? modifiedAt;

  /// Content/metadata signature retained as read evidence.
  final String signature;

  @override
  List<Object?> get props => <Object?>[
    path,
    format,
    contents,
    maskedContents,
    exists,
    loadedAt,
    modifiedAt,
    signature,
  ];
}

/// Result of atomically saving a Provider configuration document.
final class AgentConfigurationSaveResult extends Equatable {
  /// Creates a configuration save result.
  const AgentConfigurationSaveResult({
    required this.document,
    this.backupPath,
  });

  /// Fresh post-save document.
  final AgentConfigurationDocument document;

  /// Backup path created for a previous file, when any.
  final String? backupPath;

  @override
  List<Object?> get props => <Object?>[document, backupPath];
}

/// Result of pure current-schema configuration validation.
final class AgentConfigurationValidation extends Equatable {
  /// Creates a validation result with a stable [failureCode].
  const AgentConfigurationValidation({this.failureCode});

  /// Shared successful validation result.
  static const valid = AgentConfigurationValidation();

  /// Stable, non-localized failure code, or null when valid.
  final String? failureCode;

  /// Whether the configuration is valid.
  bool get isValid => failureCode == null;

  @override
  List<Object?> get props => <Object?>[failureCode];
}

/// Provider-neutral log severity.
enum AgentLogLevel {
  /// Verbose diagnostic information.
  debug,

  /// Informational Provider output.
  info,

  /// Recoverable warning output.
  warning,

  /// Error or fatal output.
  error,
}

/// One redacted Provider-owned log line.
final class AgentLogEntry extends Equatable {
  /// Creates a domain log entry.
  const AgentLogEntry({
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

  /// Redacted message supplied by the Data boundary.
  final String message;

  /// Parsed log severity.
  final AgentLogLevel level;

  /// Parsed timestamp, when present.
  final DateTime? timestamp;

  @override
  List<Object?> get props => <Object?>[
    id,
    sourcePath,
    message,
    level,
    timestamp,
  ];
}
