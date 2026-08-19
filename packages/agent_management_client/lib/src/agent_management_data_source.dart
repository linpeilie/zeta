import 'package:agent_management_client/src/agent_management_responses.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Vendor-neutral external IO boundary for one managed agent CLI.
abstract interface class AgentManagementDataSource {
  /// Detects the selected executable without sending a model prompt.
  Future<DetectResponse> detect({required String executablePath});

  /// Performs a user-requested, prompt-free protocol connection test.
  Future<ConnectionTestResponse> testConnection({
    required AgentProviderConfig config,
  });

  /// Reads the current provider configuration document.
  Future<ConfigurationDocumentResponse> readConfiguration();

  /// Validates and atomically saves current-schema configuration [contents].
  Future<ConfigurationSaveResponse> saveConfiguration({
    required String contents,
  });

  /// Discovers provider-owned log paths.
  Future<List<String>> discoverLogPaths();

  /// Reads a redacted tail from one discovered provider log [path].
  Future<List<LogEntryResponse>> readLogs(
    String path, {
    int maxLines = 1000,
  });
}
