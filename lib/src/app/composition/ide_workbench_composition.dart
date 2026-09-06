import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';

/// App-only connection of a borrowed Shell fact source; no state owner is created.
/// This callback disappears when WP-3C moves Shell construction to the root.
typedef ManagementRuntimeFactsConnector =
    void Function() Function(AgentManagementRuntimeFactSource source);
