import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_bloc.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_event.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_state.dart';
import 'package:zeta/ide_shell/view/ide_shell_view.dart';

class IdeShellPage extends StatelessWidget {
  const IdeShellPage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final projectId = GoRouterState.of(context).pathParameters['projectId'];
    final projectPath = projectId == null
        ? null
        : context.read<WorkspaceRepository>().resolveProjectPath(projectId);
    return BlocProvider(
      create: (context) => IdeShellBloc(
        workspaceRepository: context.read<WorkspaceRepository>(),
        projectSessionRepository: context.read<ProjectSessionRepository>(),
        desktopPlatformRepository: context.read<DesktopPlatformRepository>(),
      )..add(const IdeShellStarted()),
      child: _IdeShellListener(
        projectPath: projectPath,
        child: child,
      ),
    );
  }
}

class _IdeShellListener extends StatelessWidget {
  const _IdeShellListener({
    required this.projectPath,
    required this.child,
  });

  final String? projectPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<IdeShellBloc, IdeShellState>(
      listenWhen: (previous, current) {
        return current.pickedProjectPath != null &&
            current.pickedProjectPath != previous.pickedProjectPath;
      },
      listener: (context, state) {
        final path = state.pickedProjectPath;
        if (path == null) {
          return;
        }
        final projectId = context.read<WorkspaceRepository>().projectIdFor(
          path,
        );
        context.read<IdeShellBloc>().add(
          const IdeShellProjectPickedConsumed(),
        );
        context.goNamed(
          'project',
          pathParameters: <String, String>{'projectId': projectId},
        );
      },
      child: IdeShellView(
        projectPath: projectPath,
        child: child,
      ),
    );
  }
}
