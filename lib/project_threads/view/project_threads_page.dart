import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:zeta/project_threads/bloc/project_threads_bloc.dart';
import 'package:zeta/project_threads/bloc/project_threads_event.dart';
import 'package:zeta/project_threads/view/project_threads_view.dart';

class ProjectThreadsPage extends StatelessWidget {
  const ProjectThreadsPage({this.projectPath, super.key});

  final String? projectPath;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final bloc = ProjectThreadsBloc(
          projectSessionRepository: context.read<ProjectSessionRepository>(),
          agentProviderRepository: context.read<AgentProviderRepository>(),
        )..add(const ProjectThreadsSubscriptionRequested());
        final path = projectPath;
        if (path != null) {
          bloc.add(ProjectThreadsProjectActivated(path));
        }
        return bloc;
      },
      child: const ProjectThreadsView(),
    );
  }
}
