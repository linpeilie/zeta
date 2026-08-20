import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';
import 'package:zeta/l10n/l10n.dart';

class AgentConversationHeader extends StatelessWidget {
  const AgentConversationHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final header = context.select<AgentConversationBloc, AgentHeaderState>(
      (bloc) => bloc.state.header,
    );
    final title = header.title.isEmpty
        ? l10n.agentDefaultThreadTitle
        : header.title;
    return IdePageHeader(title: title);
  }
}
