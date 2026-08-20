import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_bloc.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_event.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_state.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/project_threads/project_threads.dart';
import 'package:zeta/workspace/workspace.dart';

class IdeShellView extends StatelessWidget {
  const IdeShellView({
    required this.child,
    this.projectPath,
    super.key,
  });

  final String? projectPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final workbench = context.select<IdeShellBloc, ProjectWorkbenchSnapshot>(
      (bloc) => bloc.state.workbench,
    );
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            children: <Widget>[
              TextButton(
                key: const Key('ide-shell-home'),
                onPressed: () => context.goNamed('home'),
                child: Text(l10n.homeOpenProject),
              ),
              TextButton(
                key: const Key('ide-shell-open-project'),
                onPressed: () {
                  context.read<IdeShellBloc>().add(
                    const IdeShellOpenProjectRequested(),
                  );
                },
                child: Text(l10n.homeOpenProjectFolder),
              ),
              TextButton(
                key: const Key('ide-shell-settings'),
                onPressed: () => context.goNamed('settings'),
                child: Text(l10n.settingsNavGeneral),
              ),
              TextButton(
                key: const Key('ide-shell-agents'),
                onPressed: () => context.goNamed('agents'),
                child: Text(l10n.settingsNavAgents),
              ),
              TextButton(
                key: const Key('ide-shell-usage'),
                onPressed: () => context.goNamed('usage-statistics'),
                child: Text(l10n.usagePageTitle),
              ),
              TextButton(
                key: const Key('ide-shell-toggle-sidebar'),
                onPressed: () {
                  context.read<IdeShellBloc>().add(
                    const IdeShellSidebarVisibilityToggled(),
                  );
                },
                child: Text(
                  workbench.leftSidebarVisible
                      ? l10n.workbenchHideLeftSidebar
                      : l10n.workbenchShowLeftSidebar,
                ),
              ),
              TextButton(
                key: const Key('ide-shell-toggle-usage'),
                onPressed: () {
                  context.read<IdeShellBloc>().add(
                    const IdeShellUsageExpandedToggled(),
                  );
                },
                child: Text(
                  workbench.agentUsageExpanded
                      ? l10n.usageCollapseAgentStats
                      : l10n.usageExpandAgentStats,
                ),
              ),
            ],
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (workbench.leftSidebarVisible && projectPath != null)
                  SizedBox(
                    key: const Key('ide-shell-sidebar'),
                    width: workbench.leftSidebarWidth ?? 280,
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: WorkspacePage(
                            key: ValueKey<String>(projectPath!),
                            initialRootPath: projectPath,
                          ),
                        ),
                        Expanded(
                          child: ProjectThreadsPage(
                            key: ValueKey<String>('threads-$projectPath'),
                            projectPath: projectPath,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
