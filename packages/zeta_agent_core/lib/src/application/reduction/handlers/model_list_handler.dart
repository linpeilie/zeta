import 'package:zeta_agent_core/src/application/agent_conversation_effect.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_mutation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_reducer_context.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_session_state.dart';
import 'package:zeta_agent_core/src/application/reduction/agent_event_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/_support/reduction_result.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

final class ModelListHandler implements AgentEventHandler<AgentModelListEvent> {
  const ModelListHandler();

  @override
  AgentConversationReduction handle(
    AgentModelListEvent event,
    AgentConversationSessionState state,
    AgentConversationReducerContext context,
    AgentReducerScratch scratch,
  ) {
    return acceptedReduction(
      state,
      effects: <AgentConversationEffect>[
        AgentApplyModelListEffect(
          scope: context.effectScope,
          models: event.models,
        ),
        if (!context.modelsRefreshing)
          AgentRecordModelCatalogEffect(
            scope: context.effectScope,
            config: context.activeProviderConfig,
            models: event.models,
            source: '${context.activeProviderName} runtime',
          ),
      ],
    );
  }
}
