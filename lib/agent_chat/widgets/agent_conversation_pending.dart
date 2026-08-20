import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_event.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';
import 'package:zeta/l10n/l10n.dart';

class AgentConversationPending extends StatelessWidget {
  const AgentConversationPending({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pending = context
        .select<AgentConversationBloc, AgentPendingInteractionState>(
          (bloc) => bloc.state.pending,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final permission in pending.permissions)
          IdeListRow(
            title: permission.title,
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                AgentPermissionResponded(
                  AgentPermissionDecision(
                    requestId: permission.id,
                    approved: true,
                  ),
                ),
              );
            },
          ),
        for (final question in pending.questions)
          IdeListRow(
            title: question.title ?? l10n.agentSubmitAnswers,
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                AgentQuestionResponded(
                  AgentQuestionResponse(requestId: question.id),
                ),
              );
            },
          ),
        for (final plan in pending.planApprovals)
          IdeListRow(
            title: plan.title ?? l10n.agentPlanApprovalTitle,
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                AgentPlanApprovalResponded(
                  AgentPlanApprovalDecision(
                    requestId: plan.id,
                    kind: AgentPlanApprovalDecisionKind.accepted,
                  ),
                ),
              );
            },
          ),
        if (pending.planExecutionHandoff != null)
          TextButton(
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentPlanExecutionStarted(),
              );
            },
            child: Text(l10n.agentSubmit),
          ),
      ],
    );
  }
}
