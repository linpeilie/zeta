import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'agent_conversation_workspace_notifier.dart';

final agentConversationWorkspaceChangesProvider =
    Provider<void Function() Function(void Function())>(
      (ref) => (listener) {
        final subscription = ref.listen(
          agentConversationWorkspaceProvider,
          (_, _) => listener(),
        );
        return subscription.close;
      },
    );
