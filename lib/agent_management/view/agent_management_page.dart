import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_management/bloc/agent_management_bloc.dart';
import 'package:zeta/agent_management/bloc/agent_management_event.dart';
import 'package:zeta/agent_management/view/agent_management_view.dart';

class AgentManagementPage extends StatelessWidget {
  const AgentManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AgentManagementBloc(
        agentManagementRepository: context.read<AgentManagementRepository>(),
      )..add(const AgentManagementStarted()),
      child: const AgentManagementView(),
    );
  }
}
