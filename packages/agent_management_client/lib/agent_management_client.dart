/// Vendor-neutral agent management data client for Zeta.
library;

export 'src/agent_management_data_source.dart';
export 'src/agent_management_file_system.dart';
export 'src/agent_management_responses.dart';
export 'src/claude_code_auth_status_probe.dart';
export 'src/cli_process_runner.dart';
export 'src/managed_cli_data_source.dart'
    show
        AccountProbeResponse,
        AgentManagementAccountProbe,
        AgentManagementCliLocator,
        AgentManagementCliPathResolver,
        AgentManagementProtocolProbe,
        AgentProtocolProbeResponse,
        ClaudeCodeAgentManagementDataSource,
        CodexAgentManagementDataSource,
        GrokAgentManagementDataSource,
        validateConfiguration;
