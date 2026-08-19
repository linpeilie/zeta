// Dependency parameter names intentionally differ from private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_management_client/src/agent_management_responses.dart';
import 'package:agent_management_client/src/cli_process_runner.dart';
import 'package:agent_management_client/src/managed_cli_data_source.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Whitelisted projection of `claude auth status --json`.
final class ClaudeCodeAuthStatusSnapshot {
  /// Creates a credential-free auth snapshot.
  const ClaudeCodeAuthStatusSnapshot({
    required this.loggedIn,
    this.authMethod,
    this.apiProvider,
    this.subscriptionType,
  });

  /// Explicit CLI login state.
  final bool loggedIn;

  /// Whitelisted authentication method.
  final String? authMethod;

  /// Whitelisted third-party API provider.
  final String? apiProvider;

  /// Whitelisted Claude subscription type.
  final String? subscriptionType;
}

/// Reads Claude auth evidence through an injected vendor-owned locator.
final class ClaudeCodeAuthStatusProbe {
  /// Creates a prompt-free auth status probe.
  const ClaudeCodeAuthStatusProbe({
    required AgentManagementCliLocator locate,
    CliProcessRunner processRunner = const CliProcessRunner(),
  }) : _locate = locate,
       _processRunner = processRunner;

  final AgentManagementCliLocator _locate;
  final CliProcessRunner _processRunner;

  /// Locates Claude and returns whitelisted evidence.
  ///
  /// Returns `null` when the command cannot provide reliable evidence.
  Future<ClaudeCodeAuthStatusSnapshot?> probe(
    AgentProviderConfig config,
  ) async {
    try {
      final command = await _locate(config);
      if (command == null) {
        return null;
      }
      return await probeCommand(command, config.environment);
    } on Object {
      return null;
    }
  }

  /// Reads auth evidence from an already resolved Claude [command].
  Future<ClaudeCodeAuthStatusSnapshot?> probeCommand(
    ResolvedCliProcessCommand command,
    Map<String, String> environment,
  ) async {
    try {
      final result = await _processRunner.run(
        command,
        const <String>['auth', 'status', '--json'],
        timeout: const Duration(seconds: 10),
        environment: environment,
      );
      if (result.exitCode != 0 && result.exitCode != 1) {
        return null;
      }
      return decodeClaudeCodeAuthStatus(result.stdout);
    } on TimeoutException {
      return null;
    } on ProcessException {
      return null;
    } on FileSystemException {
      return null;
    } on Object {
      return null;
    }
  }

  /// Adapter passed to a Claude Code management Data source.
  Future<AccountProbeResponse> accountProbe(
    ResolvedCliProcessCommand command,
    Map<String, String> environment,
  ) async {
    final snapshot = await probeCommand(command, environment);
    if (snapshot == null) {
      return const AccountProbeResponse(
        status: AgentAccountStatus.unavailable,
      );
    }
    if (!snapshot.loggedIn) {
      return const AccountProbeResponse(status: AgentAccountStatus.loggedOut);
    }
    return AccountProbeResponse(
      status: AgentAccountStatus.loggedIn,
      label: _accountLabel(snapshot),
    );
  }
}

/// Decodes only whitelisted Claude auth fields and retains no raw JSON.
ClaudeCodeAuthStatusSnapshot? decodeClaudeCodeAuthStatus(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) {
    return null;
  }
  final map = decoded.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value as Object?),
  );
  final loggedIn = map['loggedIn'];
  if (loggedIn is! bool) {
    return null;
  }
  return ClaudeCodeAuthStatusSnapshot(
    loggedIn: loggedIn,
    authMethod: _nonEmptyString(map['authMethod']),
    apiProvider: _nonEmptyString(map['apiProvider']),
    subscriptionType: _nonEmptyString(map['subscriptionType']),
  );
}

String _accountLabel(ClaudeCodeAuthStatusSnapshot snapshot) {
  final method = snapshot.authMethod?.toLowerCase();
  if (method == 'claude.ai') {
    return switch (snapshot.subscriptionType?.trim().toLowerCase()) {
      'pro' || 'claude pro' => 'Claude Pro',
      'max' || 'claude max' => 'Claude Max',
      'team' || 'claude team' => 'Claude Team',
      'enterprise' || 'claude enterprise' => 'Claude Enterprise',
      _ => 'Claude.ai',
    };
  }
  return switch (method) {
    'api_key' => 'API key',
    'api_key_helper' => 'API key helper',
    'oauth_token' => 'OAuth token',
    'third_party' => _thirdPartyLabel(snapshot.apiProvider),
    _ => 'Authenticated',
  };
}

String _thirdPartyLabel(String? provider) {
  return switch (provider?.trim().toLowerCase()) {
    'bedrock' => 'Amazon Bedrock',
    'vertex' => 'Google Vertex AI',
    'foundry' => 'Microsoft Foundry',
    'gemini' => 'Gemini',
    'grok' => 'Grok',
    'openai' => 'OpenAI',
    _ => 'Third-party provider',
  };
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
