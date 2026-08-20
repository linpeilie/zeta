import 'dart:async';

import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:app_ui/app_ui.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/app/app_dependencies.dart';
import 'package:zeta/app/app_repositories.dart';
import 'package:zeta/app/router/app_router.dart';
import 'package:zeta/ide_session/ide_session.dart';
import 'package:zeta/l10n/l10n.dart';

class RoutedApp extends StatefulWidget {
  const RoutedApp({
    required this.dependencies,
    required this.repositories,
    super.key,
  });

  final AppDependencies dependencies;
  final AppRepositories repositories;

  @override
  State<RoutedApp> createState() => _RoutedAppState();
}

class _RoutedAppState extends State<RoutedApp> {
  late final IdeSessionCubit _session;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    _session = IdeSessionCubit(
      projectSessionRepository: widget.repositories.projectSessionRepository,
    );
    unawaited(_restore());
  }

  Future<void> _restore() async {
    await _session.restore();
    if (!mounted) {
      return;
    }
    final location = locationFromSession(
      route: _session.state.initialRoute,
      workspaceRepository: widget.repositories.workspaceRepository,
    );
    setState(() {
      _router = createIdeRouter(initialLocation: location);
    });
  }

  @override
  void dispose() {
    unawaited(_session.close());
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    final repositories = widget.repositories;
    return MultiRepositoryProvider(
      providers: <RepositoryProvider<dynamic>>[
        RepositoryProvider<WorkspaceRepository>.value(
          value: repositories.workspaceRepository,
        ),
        RepositoryProvider<ProjectSessionRepository>.value(
          value: repositories.projectSessionRepository,
        ),
        RepositoryProvider<DesktopPlatformRepository>.value(
          value: repositories.desktopPlatformRepository,
        ),
        RepositoryProvider<SettingsRepository>.value(
          value: repositories.settingsRepository,
        ),
        RepositoryProvider<AgentProviderRepository>.value(
          value: repositories.agentProviderRepository,
        ),
        RepositoryProvider<AgentConversationRepository>.value(
          value: repositories.agentConversationRepository,
        ),
        RepositoryProvider<AgentManagementRepository>.value(
          value: repositories.agentManagementRepository,
        ),
        RepositoryProvider<UsageStatisticsRepository>.value(
          value: repositories.usageStatisticsRepository,
        ),
        RepositoryProvider<DesktopNotificationsRepository>.value(
          value: repositories.desktopNotificationsRepository,
        ),
        RepositoryProvider<AppDependencies>.value(
          value: widget.dependencies,
        ),
      ],
      child: BlocProvider<IdeSessionCubit>.value(
        value: _session,
        child: router == null
            ? MaterialApp(
                localizationsDelegates: const [
                  ZetaShadcnLocalizations.delegate,
                  ...AppLocalizations.localizationsDelegates,
                ],
                locale: widget.dependencies.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              )
            : MaterialApp.router(
                theme: AppTheme.light,
                builder: (context, child) {
                  return Theme(
                    data: AppTheme.light,
                    child: child ?? const SizedBox.shrink(),
                  );
                },
                localizationsDelegates: const [
                  ZetaShadcnLocalizations.delegate,
                  ...AppLocalizations.localizationsDelegates,
                ],
                locale: widget.dependencies.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
      ),
    );
  }
}
