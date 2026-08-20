import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_event.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';
import 'package:zeta/l10n/l10n.dart';

class AgentConversationView extends StatelessWidget {
  const AgentConversationView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AgentConversationBloc, AgentConversationState>(
      builder: (context, state) {
        final title = state.header.title.isEmpty
            ? l10n.agentDefaultThreadTitle
            : state.header.title;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IdePageHeader(title: title),
            Expanded(
              child: IdePageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (state.failure != null)
                      EmptyState(
                        text: FailureMessages(
                          l10n,
                        ).agentConversationFailure(state.failure!.code),
                      ),
                    for (final turn in state.history.visibleTurns)
                      IdeListRow(title: turn.id),
                    for (final permission in state.pending.permissions)
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
                    for (final question in state.pending.questions)
                      IdeListRow(
                        title: question.title ?? l10n.agentSubmitAnswers,
                        onPressed: () {
                          context.read<AgentConversationBloc>().add(
                            AgentQuestionResponded(
                              AgentQuestionResponse(
                                requestId: question.id,
                              ),
                            ),
                          );
                        },
                      ),
                    for (final plan in state.pending.planApprovals)
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
                    if (state.pending.planExecutionHandoff != null)
                      TextButton(
                        onPressed: () {
                          context.read<AgentConversationBloc>().add(
                            const AgentPlanExecutionStarted(),
                          );
                        },
                        child: Text(l10n.agentSubmit),
                      ),
                    Wrap(
                      children: <Widget>[
                        TextButton(
                          onPressed: state.composer.canSubmitMessage
                              ? () {
                                  context.read<AgentConversationBloc>().add(
                                    const AgentMessageSubmitted(
                                      message: '',
                                    ),
                                  );
                                }
                              : null,
                          child: Text(l10n.agentSend),
                        ),
                        TextButton(
                          onPressed: state.composer.canCancelTurn
                              ? () {
                                  context.read<AgentConversationBloc>().add(
                                    const AgentTurnCancelled(),
                                  );
                                }
                              : null,
                          child: Text(l10n.agentCancelTurn),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
