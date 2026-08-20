import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';
import 'package:zeta/agent_chat/view/agent_timeline_projection.dart';

class AgentConversationHistory extends StatelessWidget {
  const AgentConversationHistory({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context
        .select<AgentConversationBloc, AgentConversationHistoryState>(
          (bloc) => bloc.state.history,
        );
    final items = projectTimelineItems(history);
    return Expanded(
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          return IdeListRow(title: items[index].id);
        },
      ),
    );
  }
}
