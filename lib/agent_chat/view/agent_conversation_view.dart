import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';
import 'package:zeta/agent_chat/widgets/agent_conversation_capabilities.dart';
import 'package:zeta/agent_chat/widgets/agent_conversation_composer.dart';
import 'package:zeta/agent_chat/widgets/agent_conversation_header.dart';
import 'package:zeta/agent_chat/widgets/agent_conversation_history.dart';
import 'package:zeta/agent_chat/widgets/agent_conversation_pending.dart';
import 'package:zeta/l10n/l10n.dart';

class AgentConversationView extends StatelessWidget {
  const AgentConversationView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = context
        .select<AgentConversationBloc, AgentConversationFailure?>(
          (bloc) => bloc.state.failure,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AgentConversationHeader(),
        if (failure != null)
          EmptyState(
            text: FailureMessages(l10n).agentConversationFailure(failure.code),
          ),
        const AgentConversationHistory(),
        const AgentConversationPending(),
        const AgentConversationCapabilities(),
        const AgentConversationComposer(),
      ],
    );
  }
}
