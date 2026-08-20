import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_management_client/agent_management_client.dart';
import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:claude_code_client/claude_code_client.dart';
import 'package:codex_app_server_client/codex_app_server_client.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:grok_acp_client/grok_acp_client.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:project_session_client/project_session_client.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:settings_client/settings_client.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:usage_statistics_storage_client/usage_statistics_storage_client.dart';
import 'package:workspace_client/workspace_client.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/app/app.dart';
import 'package:zeta/app/platform/platform.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta_logging/zeta_logging.dart';
import 'package:zeta_storage/zeta_storage.dart';

class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    super.onError(bloc, error, stackTrace);
  }
}

/// Builds the process-wide dependency graph for one run.
typedef ZetaCompositionBuilder = Future<ZetaComposition> Function(
  AppDependencies dependencies,
);

/// The dependency graph owned by the composition root for one process.
///
/// Holds the Repository set handed to the widget tree plus the ordered
/// shutdown hooks for every resource the composition root created.
final class ZetaComposition {
  const ZetaComposition._(this._shutdownHooks, {required this.repositories});

  /// Repositories provided to the widget tree.
  final AppRepositories repositories;

  final List<Future<void> Function()> _shutdownHooks;

  /// Releases every owned resource in reverse construction order.
  ///
  /// Every hook runs even when an earlier one fails; the first failure is
  /// rethrown once the remaining hooks have been given their chance to run.
  Future<void> close() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final hook in _shutdownHooks.reversed) {
      try {
        await hook();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}

/// Starts the app with locale-dependent services frozen before the first frame.
Future<void> bootstrap(
  FutureOr<Widget> Function(
    AppDependencies dependencies,
    ZetaComposition composition,
  )
  builder, {
  Locale? platformLocale,
  void Function(Widget app) appRunner = runApp,
  ZetaCompositionBuilder compose = composeZeta,
}) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  final systemLocale = platformLocale ?? binding.platformDispatcher.locale;
  final language = resolveAppLanguageFromFirstSystemLocale(
    languageCode: systemLocale.languageCode,
    scriptCode: systemLocale.scriptCode,
    countryCode: systemLocale.countryCode,
  );
  final frozenLocale = switch (language) {
    AppLanguage.english => const Locale('en'),
    AppLanguage.simplifiedChinese => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
    ),
  };
  final l10n = lookupAppLocalizations(frozenLocale);
  final dependencies = AppDependencies(
    locale: frozenLocale,
    failureMessages: FailureMessages(l10n),
    desktopNotificationCopyResolver: DesktopNotificationCopyResolver(l10n),
  );

  final composition = await compose(dependencies);
  appRunner(await builder(dependencies, composition));
}

/// Constructs every Data client, platform adapter and Repository.
///
/// This is the only place that may see all three at once. Every seam has a
/// production default so `bootstrap` can call this with no arguments, while
/// tests can compose the same graph against a temporary home directory
/// without touching plugins or launching Provider CLIs.
Future<ZetaComposition> composeZeta(
  AppDependencies dependencies, {
  ZetaDataPaths? dataPaths,
  Map<String, String>? environment,
  bool? isWindows,
  ZetaPlatformFacades? facades,
  ProcessStarter? codexProcessStarter,
  ProcessStarter? claudeProcessStarter,
  ProcessStarter? grokProcessStarter,
  Map<AgentProviderKind, AgentProviderBundleFactory>? bundleFactories,
}) async {
  final hostEnvironment = environment ?? Platform.environment;
  final windows = isWindows ?? Platform.isWindows;
  final paths =
      dataPaths ??
      ZetaDataPaths.fromEnvironment(
        environment: hostEnvironment,
        isWindows: windows,
      );
  await paths.ensureDirectories();
  configureAppLogging(logDirectory: paths.logsDirectory);

  final platform =
      facades ??
      ZetaPlatformFacades.production(
        linuxNotificationActionName:
            dependencies.desktopNotificationCopyResolver.linuxActionName,
      );
  final shutdownHooks = <Future<void> Function()>[shutdownAppLogging];

  final providerHomes = _ProviderHomes.resolve(
    environment: hostEnvironment,
    isWindows: windows,
  );

  // Data ------------------------------------------------------------------
  final configStore = FileProviderConfigStore(file: paths.providersFile);
  final modelCatalogCache = FileAgentModelCatalogCacheStore(
    file: paths.agentModelCatalogCacheFile,
  );
  final turnContextStore = FileAgentTurnContextStore(
    rootDirectory: paths.sessionStateDirectory,
  );
  final usagePartitionStore = UsagePartitionStore(
    storage: AtomicUsageDocumentStorage.fromFile(
      paths.usageStatisticsIndexFile,
    ),
  );
  shutdownHooks.add(usagePartitionStore.close);

  final factories =
      bundleFactories ??
      _bundleFactories(
        codexProcessStarter: codexProcessStarter,
        claudeProcessStarter: claudeProcessStarter,
        grokProcessStarter: grokProcessStarter,
      );

  // Platform adapters -----------------------------------------------------
  final fileSelector = FileSelectorAdapter(platform.fileSelector);
  final windowCommands = WindowCommandAdapter(
    platform.windowManager,
    platform.macOsWindow,
  );
  final menuCommands = MethodChannelMenuCommandAdapter(platform.menuChannel);
  shutdownHooks.add(menuCommands.close);

  // Repositories ----------------------------------------------------------
  final desktopPlatformRepository = DesktopPlatformRepository(
    directoryPicker: fileSelector,
    filePicker: fileSelector,
    clipboard: PasteboardClipboardAdapter(platform.pasteboard),
    fileManager: SystemFileManagerAdapter(platform.fileManager),
    window: windowCommands,
    menu: menuCommands,
  );

  final workspaceRepository = WorkspaceRepository(
    scanner: FileWorkspaceScanner(fileSystem: const IoWorkspaceFileSystem()),
  );
  shutdownHooks.add(workspaceRepository.close);

  final settingsRepository = SettingsRepository(
    generalStore: FileGeneralSettingsStore(
      storage: AtomicSettingsDocumentStorage.fromFile(
        paths.generalSettingsFile,
      ),
    ),
    appearanceStore: FileAppearanceSettingsStore(
      storage: AtomicSettingsDocumentStorage.fromFile(paths.appearanceFile),
    ),
    fontCatalog: MethodChannelSystemFontCatalogAdapter(platform.fontChannel),
  );
  shutdownHooks.add(settingsRepository.close);

  final agentProviderRepository = AgentProviderRepository(
    configStore: configStore,
    modelCatalogCache: modelCatalogCache,
    bundleFactories: factories,
    logger: loggerFor('zeta.agent.provider_repository'),
  );
  shutdownHooks.add(agentProviderRepository.close);

  final agentConversationRepository = AgentConversationRepository(
    turnContextStore: turnContextStore,
    logger: loggerFor('zeta.agent.conversation_repository'),
  );
  shutdownHooks.add(agentConversationRepository.close);

  final agentManagementRepository = AgentManagementRepository(
    configStore: configStore,
    managementClients: _managementClients(
      homes: providerHomes,
      bundleFactories: factories,
    ),
  );

  // `bundleFor` is synchronous and needs loaded configuration; the ports below
  // are read once here so no Repository has to depend on another one.
  await agentProviderRepository.ready;
  final ports = _resolveProviderPorts(agentProviderRepository);

  final projectSessionRepository = ProjectSessionRepository(
    store: ProjectSessionStore(
      storage: AtomicProjectSessionDocumentStorage.fromFile(
        paths.ideSessionFile,
      ),
    ),
    threadCatalogs: ports.threadCatalogs,
  );
  shutdownHooks.add(projectSessionRepository.close);

  final usageStatisticsRepository = UsageStatisticsRepository(
    codex: CodexUsageReader(codexHome: providerHomes.codex),
    claude: ClaudeCodeUsageReader(claudeHome: providerHomes.claude),
    grok: GrokUsageReader(grokHome: providerHomes.grok),
    cacheStore: usagePartitionStore,
    codexProvider: _identityFor(AgentProviderConfig.defaultCodex),
    claudeProvider: _identityFor(AgentProviderConfig.defaultClaudeCode),
    grokProvider: _identityFor(AgentProviderConfig.defaultGrok),
    quotaProviders: ports.quotaProviders,
  );

  final desktopNotificationsRepository = DesktopNotificationsRepository(
    notifications: FlutterDesktopNotificationAdapter(platform.notifications),
    attention: MethodChannelDesktopAttentionAdapter(platform.attentionChannel),
  );

  return ZetaComposition._(
    shutdownHooks,
    repositories: AppRepositories(
      workspaceRepository: workspaceRepository,
      projectSessionRepository: projectSessionRepository,
      desktopPlatformRepository: desktopPlatformRepository,
      settingsRepository: settingsRepository,
      agentProviderRepository: agentProviderRepository,
      agentConversationRepository: agentConversationRepository,
      agentManagementRepository: agentManagementRepository,
      usageStatisticsRepository: usageStatisticsRepository,
      desktopNotificationsRepository: desktopNotificationsRepository,
    ),
  );
}

UsageProviderIdentity _identityFor(AgentProviderConfig config) =>
    UsageProviderIdentity(id: config.id, name: config.displayName);

Map<AgentProviderKind, AgentProviderBundleFactory> _bundleFactories({
  required ProcessStarter? codexProcessStarter,
  required ProcessStarter? claudeProcessStarter,
  required ProcessStarter? grokProcessStarter,
}) {
  return <AgentProviderKind, AgentProviderBundleFactory>{
    AgentProviderKind.codexAppServer: CodexProviderBundleFactory(
      peerFactory: CodexProviderBundleFactory.createPeer,
      processStarter:
          codexProcessStarter ?? CodexProviderBundleFactory.startProcess,
      logger: loggerFor('zeta.agent.codex'),
    ),
    AgentProviderKind.claudeCode: ClaudeProviderBundleFactory(
      peerFactory: ClaudeProviderBundleFactory.createPeer,
      processStarter:
          claudeProcessStarter ?? ClaudeProviderBundleFactory.startProcess,
      logger: loggerFor('zeta.agent.claude_code'),
    ),
    AgentProviderKind.acp: GrokProviderBundleFactory(
      processStarter:
          grokProcessStarter ?? GrokProviderBundleFactory.startProcess,
      logger: loggerFor('zeta.agent.grok'),
    ),
  };
}

Map<String, AgentManagementDataSource> _managementClients({
  required _ProviderHomes homes,
  required Map<AgentProviderKind, AgentProviderBundleFactory> bundleFactories,
}) {
  const codexLocator = CodexCliLocator();
  const claudeLocator = ClaudeCodeCliLocator();
  const grokLocator = GrokCliLocator();
  final claudeAuthProbe = ClaudeCodeAuthStatusProbe(
    locate: claudeLocator.locate,
  );
  final protocolProbe = agentProtocolProbeFor(bundleFactories);

  return <String, AgentManagementDataSource>{
    defaultAgentProviderId: CodexAgentManagementDataSource(
      configPath: homes.join(homes.codex, 'config.toml'),
      logDirectory: homes.join(homes.codex, 'log'),
      resolvePath: codexLocator.resolvePath,
      locate: codexLocator.locate,
      protocolProbe: protocolProbe,
    ),
    defaultClaudeCodeProviderId: ClaudeCodeAgentManagementDataSource(
      configPath: homes.join(homes.claude, 'settings.json'),
      logDirectory: homes.join(homes.claude, 'logs'),
      resolvePath: claudeLocator.resolvePath,
      locate: claudeLocator.locate,
      accountProbe: claudeAuthProbe.accountProbe,
      protocolProbe: protocolProbe,
    ),
    grokAgentProviderId: GrokAgentManagementDataSource(
      configPath: homes.join(homes.grok, 'config.toml'),
      logDirectory: homes.join(homes.grok, 'logs'),
      resolvePath: grokLocator.resolvePath,
      locate: grokLocator.locate,
      protocolProbe: protocolProbe,
    ),
  };
}

/// Binds composition-owned bundle factories to the management probe seam.
AgentManagementProtocolProbe agentProtocolProbeFor(
  Map<AgentProviderKind, AgentProviderBundleFactory> bundleFactories,
) {
  return (config) => probeAgentProtocol(config, bundleFactories);
}

/// Runs one prompt-free protocol handshake against a throwaway runtime.
///
/// Detection happens before any session exists, so this deliberately does not
/// borrow the Repository-owned global runtime: the probe owns the instance it
/// creates and disposes it before returning. Failures propagate unchanged so
/// the Data source keeps its own timeout and failure-code mapping.
Future<AgentProtocolProbeResponse> probeAgentProtocol(
  AgentProviderConfig config,
  Map<AgentProviderKind, AgentProviderBundleFactory> bundleFactories,
) async {
  final factory = bundleFactories[config.kind];
  if (factory == null) {
    return AgentProtocolProbeResponse(
      success: false,
      accountValid: false,
      failureCode: 'bundle-factory-missing',
    );
  }
  final bundle = factory.createBundle(config);
  try {
    await bundle.runtime.initialize();
    final catalog = bundle.modelCatalog;
    final models = catalog == null
        ? const <AgentModelInfo>[]
        : (await catalog.listModels()).models;
    final info = bundle.runtime.runtimeInfo;
    return AgentProtocolProbeResponse(
      success: true,
      accountValid: true,
      models: models,
      protocolVersion: info?.protocolVersion,
      agentName: info?.protocolName,
      agentVersion: info?.cliVersion,
    );
  } finally {
    try {
      await bundle.runtime.dispose();
    } on Object {
      // A throwaway probe runtime must never mask the handshake outcome.
    }
  }
}

_ProviderPorts _resolveProviderPorts(AgentProviderRepository repository) {
  final threadCatalogs = <String, AgentThreadCatalogPort>{};
  final quotaProviders = <String, AgentUsageQuotaProvider>{};
  for (final config in repository.configSnapshot.configs) {
    if (!config.enabled) {
      continue;
    }
    final AgentProviderBundle bundle;
    try {
      bundle = repository.bundleFor(config.id);
    } on AgentProviderRepositoryException {
      continue;
    }
    final threadCatalog = bundle.threadCatalog;
    if (threadCatalog != null) {
      threadCatalogs[config.id] = threadCatalog;
    }
    final usageQuota = bundle.usageQuota;
    if (usageQuota != null) {
      quotaProviders[config.id] = usageQuota;
    }
  }
  return _ProviderPorts(
    threadCatalogs: threadCatalogs,
    quotaProviders: quotaProviders,
  );
}

final class _ProviderPorts {
  const _ProviderPorts({
    required this.threadCatalogs,
    required this.quotaProviders,
  });

  final Map<String, AgentThreadCatalogPort> threadCatalogs;
  final Map<String, AgentUsageQuotaProvider> quotaProviders;
}

/// Vendor CLI home directories read from the host environment.
final class _ProviderHomes {
  const _ProviderHomes._({
    required this.codex,
    required this.claude,
    required this.grok,
    required this.separator,
  });

  factory _ProviderHomes.resolve({
    required Map<String, String> environment,
    required bool isWindows,
  }) {
    final home = resolveUserHomeDirectory(
      environment: environment,
      isWindows: isWindows,
    );
    final separator = isWindows ? r'\' : '/';
    String resolve(String overrideKey, String directoryName) {
      final override = environment[overrideKey]?.trim();
      if (override != null && override.isNotEmpty) {
        return override;
      }
      if (home == null || home.trim().isEmpty) {
        return directoryName;
      }
      return _joinWith(separator, home, directoryName);
    }

    return _ProviderHomes._(
      codex: resolve('CODEX_HOME', '.codex'),
      claude: resolve('CLAUDE_HOME', '.claude'),
      grok: resolve('GROK_HOME', '.grok'),
      separator: separator,
    );
  }

  final String codex;
  final String claude;
  final String grok;
  final String separator;

  String join(String parent, String child) =>
      _joinWith(separator, parent, child);
}

String _joinWith(String separator, String parent, String child) {
  if (parent.endsWith(separator)) {
    return '$parent$child';
  }
  return '$parent$separator$child';
}
