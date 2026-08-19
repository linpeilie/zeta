import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'provider configuration copies, normalizes, serializes, and freezes',
    () {
      final updatedAt = DateTime.utc(2026);
      final preference = AgentModelPreference(
        modelId: 'model-a',
        reasoningEffort: 'high',
        fastEnabled: true,
        serviceTierId: 'priority',
        updatedAt: updatedAt,
      );
      final arguments = <String>['serve'];
      final environment = <String, String>{'TOKEN': 'secret'};
      final preferences = <String, AgentModelPreference>{'model-a': preference};
      final extra = <String, Object?>{
        'nested': <Object?>[1],
      };
      final config = AgentProviderConfig(
        id: 'custom',
        displayName: 'Custom',
        kind: AgentProviderKind.acp,
        command: 'custom',
        arguments: arguments,
        environment: environment,
        defaultModel: 'default',
        selectedModel: 'model-a',
        selectedReasoningEffort: 'high',
        selectedServiceTier: 'priority',
        modelPreferences: preferences,
        selectedPermissionOptionId: ' ask ',
        extra: extra,
      );
      arguments.clear();
      environment.clear();
      preferences.clear();
      (extra['nested']! as List<Object?>).clear();
      expect(config.arguments, <String>['serve']);
      expect(config.environment, <String, String>{'TOKEN': 'secret'});
      expect(config.modelPreferences, hasLength(1));
      expect(config.extra['nested'], <Object?>[1]);
      expect(config.resolvedPermissionOptionId, 'ask');
      expect(config.arguments.clear, throwsUnsupportedError);
      expect(config.extra.clear, throwsUnsupportedError);

      final copied = config.copyWith(
        id: 'copy',
        displayName: 'Copy',
        kind: AgentProviderKind.claudeCode,
        command: 'copy',
        arguments: <String>['copy'],
        environment: <String, String>{'A': 'B'},
        defaultModel: 'd2',
        selectedModel: 'm2',
        selectedReasoningEffort: 'low',
        selectedServiceTier: 'standard',
        modelPreferences: <String, AgentModelPreference>{},
        selectedPermissionOptionId: null,
        enabled: false,
        extra: <String, Object?>{'x': 1},
      );
      expect(copied.id, 'copy');
      expect(copied.resolvedPermissionOptionId, isNull);
      expect(config.copyWith().selectedPermissionOptionId, ' ask ');
      expect(
        config.withPermissionPreference('  ').resolvedPermissionOptionId,
        isNull,
      );
      expect(
        config.withPermissionPreference(' auto ').resolvedPermissionOptionId,
        'auto',
      );

      final reconfigured = config.withModelConfiguration(
        selection: const AgentModelSelection(
          modelId: 'model-b',
          reasoningEffort: 'medium',
        ),
        preferences: <String, AgentModelPreference>{'model-a': preference},
      );
      expect(reconfigured.selectedModel, 'model-b');
      expect(reconfigured.selectedServiceTier, isNull);
      expect(
        config.toJson(),
        containsPair('selectedPermissionOptionId', 'ask'),
      );
      expect(config.toJson()['modelPreferences'], isA<Map<String, Object?>>());

      expect(AgentProviderConfig.defaultCodex.command, 'codex');
      expect(AgentProviderConfig.defaultGrok.command, 'grok');
      expect(AgentProviderConfig.defaultClaudeCode.command, 'claude');
      expect(
        AgentProviderConfig.normalizeDisplayName(defaultAgentProviderId, 'old'),
        'Codex',
      );
      expect(
        AgentProviderConfig.normalizeDisplayName(grokAgentProviderId, 'old'),
        'Grok',
      );
      expect(
        AgentProviderConfig.normalizeDisplayName('custom', 'Name'),
        'Name',
      );

      final defaults = AgentProviderSettings();
      expect(defaults.activeProvider, AgentProviderConfig.defaultCodex);
      final settings = AgentProviderSettings(
        providers: <AgentProviderConfig>[config],
        activeProviderId: 'custom',
      );
      expect(settings.activeProvider, config);
      expect(
        settings.copyWith(activeProviderId: 'missing').activeProvider,
        AgentProviderConfig.defaultCodex,
      );
      expect(
        settings.toJson(),
        containsPair('version', AgentProviderSettings.currentVersion),
      );
      expect(settings.providers.clear, throwsUnsupportedError);
      expect(AgentProviderSettings.supportedVersions, <int>{1, 2});
      expect(
        const AgentProviderStatus.idle().state,
        AgentProviderConnectionState.idle,
      );
      expect(const AgentContext(projectPath: '/repo').projectPath, '/repo');
    },
  );

  test('model catalog values describe, copy, decode, and freeze', () {
    const effort = AgentModelReasoningEffort(
      effort: 'high',
      description: 'Deep',
    );
    const tier = AgentModelServiceTier(id: 'priority', name: 'Fast');
    final efforts = <AgentModelReasoningEffort>[effort];
    final tiers = <AgentModelServiceTier>[tier];
    final model = AgentModelInfo(
      id: 'id',
      model: 'wire-model',
      displayName: 'Display',
      hidden: true,
      supportedReasoningEfforts: efforts,
      defaultReasoningEffort: 'high',
      serviceTiers: tiers,
      defaultServiceTier: 'priority',
      isDefault: true,
      enabled: false,
      unavailableReason: 'offline',
      contextWindowTokens: 1000,
      raw: <String, Object?>{
        'x': <Object?>[1],
      },
    );
    efforts.clear();
    tiers.clear();
    expect(model.describeForLog(), contains('model=wire-model'));
    expect(model.describeForLog(), contains('name=Display'));
    expect(model.describeForLog(), contains('default'));
    expect(model.describeForLog(), contains('hidden'));
    expect(model.describeForLog(), contains('disabled'));
    expect(model.describeForLog(), contains('efforts=high'));
    expect(model.describeForLog(), contains('tiers=priority'));
    expect(model.describeForLog(), contains('ctx=1000'));
    expect(model.serviceTiers.clear, throwsUnsupportedError);

    expect(
      AgentModelList(models: <AgentModelInfo>[]).describeForLog(),
      '0 models',
    );
    final list = AgentModelList(
      models: <AgentModelInfo>[model],
      nextCursor: 'next',
    );
    expect(list.describeForLog(), contains('nextCursor=yes'));
    expect(list.models.clear, throwsUnsupportedError);
    expect(const AgentModelSelection().isEmpty, isTrue);
    expect(const AgentModelSelection(modelId: 'id').isEmpty, isFalse);
    expect(agentFastServiceTier(model), tier);
    expect(
      agentFastServiceTier(
        AgentModelInfo(id: 'x', model: 'x', displayName: 'x'),
      ),
      isNull,
    );
    const onlyTier = AgentModelServiceTier(
      id: 'standard',
      name: 'Standard',
    );
    expect(
      agentFastServiceTier(
        AgentModelInfo(
          id: 'x',
          model: 'x',
          displayName: 'x',
          serviceTiers: <AgentModelServiceTier>[onlyTier],
        ),
      ),
      onlyTier,
    );

    final preference = AgentModelPreference(
      modelId: ' model ',
      reasoningEffort: 'high',
      fastEnabled: true,
      serviceTierId: 'priority',
      updatedAt: DateTime.utc(2026),
    );
    expect(preference.selection.modelId, ' model ');
    expect(preference.toJson()['fastEnabled'], isTrue);
    final copy = preference.copyWith(
      reasoningEffort: 'low',
      fastEnabled: false,
      serviceTierId: null,
      updatedAt: DateTime.utc(2027),
      version: 2,
    );
    expect(copy.serviceTierId, isNull);
    expect(preference.copyWith().serviceTierId, 'priority');
    expect(AgentModelPreference.tryDecode(null), isNull);
    expect(AgentModelPreference.tryDecode(<String, Object?>{}), isNull);
    final decoded = AgentModelPreference.tryDecode(<Object?, Object?>{
      'modelId': ' decoded ',
      'reasoningEffort': 'medium',
      'fastEnabled': true,
      'serviceTierId': 'priority',
      'updatedAt': '2026-01-01T00:00:00Z',
      'version': 2,
      1: 'ignored',
    });
    expect(decoded?.modelId, 'decoded');
    expect(decoded?.version, 2);
    final tolerant = AgentModelPreference.tryDecode(<String, Object?>{
      'modelId': 'x',
      'version': -1,
    });
    expect(tolerant?.version, AgentModelPreference.currentVersion);
    expect(
      tolerant?.updatedAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );

    expect(
      orderedReasoningEffortsForDisplay(const <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'custom-a'),
        AgentModelReasoningEffort(effort: 'custom-b'),
      ]).map((item) => item.effort),
      <String>['custom-a', 'custom-b'],
    );
    final snapshot = AgentModelCatalogSnapshot(
      providerId: 'provider',
      configFingerprint: 'fingerprint',
      includeHidden: false,
      models: list,
      fetchedAt: DateTime.utc(2026),
      source: 'network',
    );
    expect(snapshot.source, 'network');
  });
}
