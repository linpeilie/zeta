import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
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
    // A different workspace entry is a different conversation: keying the
    // provider on the conversation identity gives that entry its own Bloc and
    // closes the previous one instead of silently reusing it.
    return BlocProvider(
      key: ValueKey<ConversationKey>(key),
      create: (context) =>
          AgentConversationBloc(
            agentProviderRepository: context.read<AgentProviderRepository>(),
            agentConversationRepository: context
                .read<AgentConversationRepository>(),
            desktopPlatformRepository: context
                .read<DesktopPlatformRepository>(),
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
