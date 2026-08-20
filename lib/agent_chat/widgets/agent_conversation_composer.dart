import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_event.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';
import 'package:zeta/l10n/l10n.dart';

class AgentConversationComposer extends StatelessWidget {
  const AgentConversationComposer({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final composer = context.select<AgentConversationBloc, AgentComposerState>(
      (bloc) => bloc.state.composer,
    );
    return Wrap(
      children: <Widget>[
        TextButton(
          onPressed: composer.canSubmitMessage
              ? () {
                  context.read<AgentConversationBloc>().add(
                    const AgentMessageSubmitted(message: ''),
                  );
                }
              : null,
          child: Text(l10n.agentSend),
        ),
        TextButton(
          onPressed: composer.canCancelTurn
              ? () {
                  context.read<AgentConversationBloc>().add(
                    const AgentTurnCancelled(),
                  );
                }
              : null,
          child: Text(l10n.agentCancelTurn),
        ),
        if (composer.canAttachImages)
          TextButton(
            key: const Key('optional-capability-attachImages'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentImagesAttachRequested(),
              );
            },
            child: Text(l10n.agentAttachImage),
          ),
        if (composer.canMentionResources)
          TextButton(
            key: const Key('optional-capability-mentionFiles'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentFilesMentionRequested(),
              );
            },
            child: Text(l10n.agentMentionFile),
          ),
      ],
    );
  }
}
