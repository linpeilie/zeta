import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_event.dart';
import 'package:zeta/agent_chat/view/agent_conversation_view.dart';

class AgentConversationPage extends StatelessWidget {
  const AgentConversationPage({
    required this.providerId,
    this.threadId,
    this.entryId,
    this.projectPath,
    super.key,
  });

  final String providerId;
  final String? threadId;
  final String? entryId;
  final String? projectPath;

  @override
  Widget build(BuildContext context) {
    final threadId = this.threadId;
    final key = threadId == null
        ? ConversationKey.draft(
            providerId: providerId,
            entryId: entryId ?? providerId,
          )
        : ConversationKey.thread(
            providerId: providerId,
            threadId: threadId,
          );
    return BlocProvider(
      create: (context) =>
          AgentConversationBloc(
            agentProviderRepository: context.read<AgentProviderRepository>(),
            agentConversationRepository: context
                .read<AgentConversationRepository>(),
          )..add(
            AgentConversationOpened(
              key: key,
              context: AgentContext(projectPath: projectPath),
            ),
          ),
      child: const AgentConversationView(),
    );
  }
}
