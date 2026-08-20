import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_bloc.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_event.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';
import 'package:zeta/l10n/l10n.dart';

class AgentConversationCapabilities extends StatelessWidget {
  const AgentConversationCapabilities({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final capabilities = context
        .select<AgentConversationBloc, AgentCapabilityPresence>(
          (bloc) => bloc.state.capabilities,
        );
    return Wrap(
      children: <Widget>[
        if (capabilities.threadCatalog)
          TextButton(
            key: const Key('optional-capability-threadCatalog'),
            onPressed: () {},
            child: Text(l10n.threadRunningStatus),
          ),
        if (capabilities.threadSubscription)
          TextButton(
            key: const Key('optional-capability-threadSubscription'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentThreadUnsubscribed(),
              );
            },
            child: Text(l10n.threadCompletedClickToDismiss),
          ),
        if (capabilities.threadNaming)
          TextButton(
            key: const Key('optional-capability-threadNaming'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentThreadRenamed(''),
              );
            },
            child: Text(l10n.agentRename),
          ),
        if (capabilities.threadArchival)
          TextButton(
            key: const Key('optional-capability-threadArchival'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentThreadArchived(),
              );
            },
            child: Text(l10n.agentArchive),
          ),
        if (capabilities.threadDeletion)
          TextButton(
            key: const Key('optional-capability-threadDeletion'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentThreadDeleted(),
              );
            },
            child: Text(l10n.threadDelete),
          ),
        if (capabilities.threadCompaction)
          TextButton(
            key: const Key('optional-capability-threadCompaction'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentThreadCompacted(),
              );
            },
            child: Text(l10n.agentContextCompacted),
          ),
        if (capabilities.threadBranching)
          TextButton(
            key: const Key('optional-capability-threadBranching'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentThreadForked(),
              );
            },
            child: Text(l10n.agentForkSession),
          ),
        if (capabilities.turnSteering)
          TextButton(
            key: const Key('optional-capability-turnSteering'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentTurnSteered(message: ''),
              );
            },
            child: Text(l10n.agentSubmit),
          ),
        if (capabilities.permissionResponses)
          TextButton(
            key: const Key('optional-capability-permissionResponses'),
            onPressed: () {},
            child: Text(l10n.agentAllow),
          ),
        if (capabilities.questions)
          TextButton(
            key: const Key('optional-capability-questions'),
            onPressed: () {},
            child: Text(l10n.agentSubmitAnswers),
          ),
        if (capabilities.deniedActionOverride)
          TextButton(
            key: const Key('optional-capability-deniedActionOverride'),
            onPressed: () {},
            child: Text(l10n.agentAllowSession),
          ),
        if (capabilities.modelCatalog)
          TextButton(
            key: const Key('optional-capability-modelCatalog'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentModelsRequested(),
              );
            },
            child: Text(l10n.agentModel),
          ),
        if (capabilities.conversationModes)
          TextButton(
            key: const Key('optional-capability-conversationModes'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentConversationModesRetried(),
              );
            },
            child: Text(l10n.agentConversationModeOptions),
          ),
        if (capabilities.skills)
          TextButton(
            key: const Key('optional-capability-skills'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentSkillsCatalogRequested(),
              );
            },
            child: Text(l10n.agentInsertSkill),
          ),
        if (capabilities.localThreadList)
          TextButton(
            key: const Key('optional-capability-localThreadList'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentThreadRemovedFromList(),
              );
            },
            child: Text(l10n.threadRemoveFromList),
          ),
        if (capabilities.sessionConfiguration)
          TextButton(
            key: const Key('optional-capability-sessionConfiguration'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentSessionConfigOptionSelected(''),
              );
            },
            child: Text(l10n.agentModelConfig),
          ),
        if (capabilities.planApproval)
          TextButton(
            key: const Key('optional-capability-planApproval'),
            onPressed: () {},
            child: Text(l10n.agentPlanApprovalTitle),
          ),
        if (capabilities.permissionPolicy)
          TextButton(
            key: const Key('optional-capability-permissionPolicy'),
            onPressed: () {},
            child: Text(l10n.agentPermissionMode),
          ),
        if (capabilities.usageQuota)
          TextButton(
            key: const Key('optional-capability-usageQuota'),
            onPressed: () {
              context.read<AgentConversationBloc>().add(
                const AgentQuotaRequested(),
              );
            },
            child: Text(l10n.agentPlanQuota),
          ),
      ],
    );
  }
}
