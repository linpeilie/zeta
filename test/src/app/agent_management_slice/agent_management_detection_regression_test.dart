import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import '../../testing/agent_management_test_container.dart';

// 只用迁移前后共有的公开操作入口；同一文件可在前置提交验证旧行为确实失败。
void main() {
  test(
    'one provider failure must not prevent the next provider being confirmed',
    () async {
      final h = _Harness();
      h.a.failure = true;
      await h.owner.detect();
      expect(h.b.calls, 1);
      expect(
        h.owner.agents
            .singleWhere((a) => a.definition.id == 'b')
            .currentVersion,
        'new-b',
      );
    },
  );
  test(
    'partial progress must not replace previously confirmed version',
    () async {
      final h = _Harness();
      h.a.gate = Completer<void>();
      await h.owner.initialize();
      final detecting = h.owner.detect();
      await Future<void>.delayed(Duration.zero);
      final visibleDuringProgress = h.owner.agent.currentVersion;
      h.a.gate!.complete();
      await detecting;
      expect(visibleDuringProgress, 'old-a');
      expect(h.owner.agent.currentVersion, 'new-a');
    },
  );
  test(
    'detection completion must preserve settings edited during repository await',
    () async {
      final h = _Harness();
      h.a.gate = Completer<void>();
      final detecting = h.owner.detect();
      await Future<void>.delayed(Duration.zero);
      h.settings.replace(
        h.settings.settings.providers.first.copyWith(
          enabled: false,
          arguments: ['new-user-argument'],
          extra: {'unrelated': 'new-user-value'},
        ),
      );
      h.a.gate!.complete();
      await detecting;
      final current = h.settings.settings.providers.first;
      expect(current.enabled, isFalse);
      expect(current.arguments, ['new-user-argument']);
      expect(current.extra['unrelated'], 'new-user-value');
    },
  );
}

final class _Harness {
  _Harness() {
    final container = managementAppTestContainer(
      AgentManagementCompositionInputs(
        repositories: {'a': a, 'b': b},
        definitions: {'a': a.definition, 'b': b.definition},
        providerSettings: settings,
        textCatalog: const FallbackAgentManagementTextCatalog(),
      ),
    );
    owner = container.read(agentManagementSliceProvider.notifier);
    addTearDown(() async {
      if (a.gate != null && !a.gate!.isCompleted) a.gate!.complete();
      await closeManagementTestContainer(container);
    });
  }
  final a = _Repository('a');
  final b = _Repository('b');
  final settings = _Settings();
  late final AgentManagementSliceNotifier owner;
}

final class _Repository implements AgentCliManagementRepository {
  _Repository(String id)
    : definition = AgentDefinition(
        id: id,
        displayName: id,
        vendor: 'test',
        commandName: id,
        protocol: 'test',
        transport: 'test',
        configFormat: 'test',
        defaultConfigRelativePath: '',
        npmPackage: '',
      );
  final AgentDefinition definition;
  Completer<void>? gate;
  bool failure = false;
  int calls = 0;
  @override
  String get agentId => definition.id;
  @override
  String get configPath => '/private/config';
  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    calls++;
    final partial =
        ManagedAgent.forDefinition(
          definition: definition,
          enabled: enabled,
        ).copyWith(
          installationState: AgentInstallationState.installed,
          currentVersion: 'partial',
          executablePath: '/private/$agentId',
        );
    onProgress?.call(
      const AgentDetectionProgress(completed: 1, total: 2, message: 'progress'),
      partial,
    );
    await gate?.future;
    if (failure) throw StateError('test detection failure');
    return partial.copyWith(currentVersion: 'new-$agentId');
  }

  @override
  Future<AgentProviderConfig> providerConfigForPath({
    required AgentProviderConfig current,
    required String path,
  }) async => current;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Settings implements AgentProviderSettingsPort {
  @override
  AgentProviderSettings settings = AgentProviderSettings(
    providers: [
      for (final id in ['a', 'b'])
        AgentProviderConfig(
          id: id,
          displayName: id,
          kind: const AgentProviderTypeId('test'),
          command: id,
          extra: {
            'cliPath': '/private/$id',
            'detectedCurrentVersion': 'old-$id',
          },
        ),
    ],
    activeProviderId: 'a',
  );
  final listeners = <void Function()>[];
  void replace(AgentProviderConfig p) {
    settings = settings.copyWith(
      providers: [
        for (final old in settings.providers) old.id == p.id ? p : old,
      ],
    );
    for (final f in List.of(listeners)) {
      f();
    }
  }

  @override
  String get activeProviderId => 'a';
  @override
  Future<void> updateProviderConfig(
    AgentProviderConfig updated, {
    bool restartProvider = false,
  }) async => replace(updated);
  @override
  Future<AgentProviderSettings> loadSettings() async => settings;
  @override
  bool isProviderEnabled(String id) =>
      settings.providers.firstWhere((p) => p.id == id).enabled;
  @override
  void Function() subscribe(void Function() listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
