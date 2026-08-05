import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_permission_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_permission_state_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_permission_migration.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/grok_permission_policy_adapter.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_permission_mode_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

import '../../../testing/fixture_reader.dart';
import '../../../testing/fake_agent_frame_scheduler.dart';
import '../../../testing/recording_json_rpc_peer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('phase A permission runtime architecture contracts', () {
    test(
      'Codex create resume fork and send encode independent request snapshots',
      () async {
        final peer = RecordingJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
          permissionSnapshot: const AgentPermissionRequestSnapshot.resolved(
            selection: AgentPermissionSelection(optionId: ':read-only'),
            source: AgentPermissionRequestSource.catalogDefault,
          ),
        );
        await provider.resumeSession(
          'resume-thread',
          context: const AgentContext(projectPath: '/repo'),
          permissionSnapshot: const AgentPermissionRequestSnapshot.resolved(
            selection: AgentPermissionSelection(
              optionId: ':danger-full-access',
            ),
            source: AgentPermissionRequestSource.providerDefault,
          ),
        );
        await provider.forkThread(
          threadId: 'source-thread',
          context: const AgentContext(projectPath: '/repo'),
          permissionSnapshot: const AgentPermissionRequestSnapshot.resolved(
            selection: AgentPermissionSelection(optionId: ':workspace'),
            source: AgentPermissionRequestSource.threadEffective,
          ),
        );
        await provider.sendMessage(
          session: const AgentSession(
            id: 'send-thread',
            providerId: defaultAgentProviderId,
          ),
          message: 'verify request-scoped permission',
          context: const AgentContext(projectPath: '/repo'),
          configuration: const AgentTurnConfiguration(
            permissionSnapshot: AgentPermissionRequestSnapshot.resolved(
              selection: AgentPermissionSelection(optionId: 'team-safe'),
              source: AgentPermissionRequestSource.threadEffective,
            ),
          ),
        );

        _expectCodexPermissionParams(
          peer.callsFor('thread/start').single.paramsMap,
          approvalPolicy: 'on-request',
          permissionProfileId: ':read-only',
        );
        _expectCodexPermissionParams(
          peer.callForThread('thread/resume', 'resume-thread').paramsMap,
          approvalPolicy: 'never',
          permissionProfileId: ':danger-full-access',
        );
        _expectCodexPermissionParams(
          peer.callForThread('thread/fork', 'source-thread').paramsMap,
          approvalPolicy: 'on-request',
          permissionProfileId: ':workspace',
        );
        _expectCodexPermissionParams(
          peer.callForThread('turn/start', 'send-thread').paramsMap,
          approvalPolicy: 'on-request',
          permissionProfileId: 'team-safe',
        );
      },
    );

    test('provider default and thread effective remain separate', () async {
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {
          fail('settings feedback must not persist the provider default');
        },
      );
      addTearDown(controller.dispose);
      controller.bind(port: null, persistedOptionId: ':workspace');
      controller.bindThread('thread-a');

      await controller.applyThreadSettings(
        threadId: 'thread-a',
        permissionSelection: const AgentPermissionSelection(
          optionId: ':read-only',
        ),
      );

      expect(controller.defaultOptionId, ':workspace');
      expect(controller.selectedOptionId, ':read-only');
      controller.bindThread('thread-b');
      expect(controller.selectedOptionId, ':workspace');
      controller.bindThread('thread-a');
      expect(controller.selectedOptionId, ':read-only');
    });

    test('Grok runtime scope broadcasts to every controller', () async {
      var runtimeMode = GrokPermissionMode.ask;
      final notifications = <({String method, Map<String, Object?> params})>[];
      final adapter = GrokPermissionPolicyAdapter(
        isInitialized: () => true,
        isDisposed: () => false,
        currentMode: () => runtimeMode,
        onModeApplied: (next) => runtimeMode = next,
        notifyLive: (method, params) {
          notifications.add((method: method, params: params));
        },
      );
      final stateStore = AgentPermissionStateStore();
      const runtimeIdentity = AgentProviderRuntimeIdentity(
        providerId: grokAgentProviderId,
        generation: 1,
      );
      stateStore.activateRuntime(
        runtimeIdentity,
        initialProviderDefault: const AgentPermissionSelection(optionId: 'ask'),
      );
      final first = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
        stateStore: stateStore,
      );
      final second = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
        stateStore: stateStore,
      );
      addTearDown(() {
        first.dispose();
        second.dispose();
        stateStore.dispose();
      });
      first.bind(
        port: adapter,
        persistedOptionId: 'ask',
        runtimeIdentity: runtimeIdentity,
      );
      first.bindThread('thread-a');
      second.bind(
        port: adapter,
        persistedOptionId: 'ask',
        runtimeIdentity: runtimeIdentity,
      );
      second.bindThread('thread-b');

      await first.selectOption(
        const AgentPermissionOption(
          id: 'always-approve',
          label: 'Always approve',
        ),
      );

      expect(runtimeMode, GrokPermissionMode.alwaysApprove);
      expect(notifications, hasLength(1));
      expect(notifications.single.method, '_x.ai/yolo_mode_changed');
      expect(notifications.single.params, <String, Object?>{
        'permission_mode': 'always-approve',
        'yolo_mode': true,
        'auto_mode': false,
        'clientIdentifier': 'zeta',
      });
      expect(first.selectedOptionId, 'always-approve');
      expect(
        second.selectedOptionId,
        'always-approve',
        reason:
            'runtime-global Grok state needs an explicit shared runtime signal',
      );
    });

    test(
      'two ViewModels sharing Codex keep real resume and turn params isolated',
      () async {
        final peer = RecordingJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final providerController = ActiveAgentProviderController(
          providerFactory: FixedAgentProviderFactory(provider),
          configStore: MemoryAgentProviderConfigStore(),
        );
        addTearDown(providerController.dispose);

        final first = AgentConversationViewModel(
          providerController: providerController,
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        final second = AgentConversationViewModel(
          providerController: providerController,
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        first.updateWorkspace(
          projectPath: '/repo',
          contextFilePath: null,
          restoredSessionId: 'thread-a',
          restoredProviderId: defaultAgentProviderId,
          resetConversation: true,
        );
        second.updateWorkspace(
          projectPath: '/repo',
          contextFilePath: null,
          restoredSessionId: 'thread-b',
          restoredProviderId: defaultAgentProviderId,
          resetConversation: true,
        );
        await Future.wait(<Future<void>>[
          first.loadModels(),
          second.loadModels(),
        ]);
        final runtimeIdentity =
            providerController.activeProviderRuntimeIdentity!;
        providerController.permissionStateStore.commitApplyResult(
          identity: runtimeIdentity,
          threadId: 'thread-a',
          result: const AgentPermissionApplyResult(
            normalizedSelection: AgentPermissionSelection(
              optionId: ':read-only',
            ),
            scope: AgentPermissionApplyScope.currentSession,
          ),
          source: AgentPermissionStateSource.serverSettings,
          updateDefault: false,
        );
        providerController.permissionStateStore.commitApplyResult(
          identity: runtimeIdentity,
          threadId: 'thread-b',
          result: const AgentPermissionApplyResult(
            normalizedSelection: AgentPermissionSelection(
              optionId: ':danger-full-access',
            ),
            scope: AgentPermissionApplyScope.currentSession,
          ),
          source: AgentPermissionStateSource.serverSettings,
          updateDefault: false,
        );
        expect(
          first.permissionSnapshotForThread('thread-a').source,
          AgentPermissionRequestSource.threadEffective,
        );
        expect(
          second.permissionSnapshotForThread('thread-b').source,
          AgentPermissionRequestSource.threadEffective,
        );

        await Future.wait(<Future<void>>[
          first.sendMessage('first canvas'),
          second.sendMessage('second canvas'),
        ]);

        expect(await providerController.activeProvider(), same(provider));
        _expectCodexPermissionParams(
          peer.callForThread('thread/resume', 'thread-a').paramsMap,
          approvalPolicy: 'on-request',
          permissionProfileId: ':read-only',
        );
        _expectCodexPermissionParams(
          peer.callForThread('turn/start', 'thread-a').paramsMap,
          approvalPolicy: 'on-request',
          permissionProfileId: ':read-only',
        );
        _expectCodexPermissionParams(
          peer.callForThread('thread/resume', 'thread-b').paramsMap,
          approvalPolicy: 'never',
          permissionProfileId: ':danger-full-access',
        );
        _expectCodexPermissionParams(
          peer.callForThread('turn/start', 'thread-b').paramsMap,
          approvalPolicy: 'never',
          permissionProfileId: ':danger-full-access',
        );
      },
    );

    test(
      'settings feedback updates only its thread across two ViewModels',
      () async {
        final peer = RecordingJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        final providerController = ActiveAgentProviderController(
          providerFactory: FixedAgentProviderFactory(provider),
          configStore: MemoryAgentProviderConfigStore(),
        );
        addTearDown(providerController.dispose);

        final first = AgentConversationViewModel(
          providerController: providerController,
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        final second = AgentConversationViewModel(
          providerController: providerController,
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        first.updateWorkspace(
          projectPath: '/repo',
          contextFilePath: null,
          restoredSessionId: 'thread-a',
          restoredProviderId: defaultAgentProviderId,
          resetConversation: true,
        );
        second.updateWorkspace(
          projectPath: '/repo',
          contextFilePath: null,
          restoredSessionId: 'thread-b',
          restoredProviderId: defaultAgentProviderId,
          resetConversation: true,
        );
        await Future.wait(<Future<void>>[
          first.loadModels(),
          second.loadModels(),
        ]);
        final runtimeIdentity =
            providerController.activeProviderRuntimeIdentity!;
        final defaultBefore = providerController.permissionStateStore
            .stateFor(runtimeIdentity)
            .providerDefaultPreference;
        final secondBefore = second.permissionSelection;
        final callsBefore = peer.calls.length;

        peer.emitNotification('thread/settings/updated', <String, Object?>{
          'threadId': 'thread-a',
          'threadSettings': <String, Object?>{
            'approvalPolicy': 'on-request',
            'sandboxPolicy': <String, Object?>{'type': 'readOnly'},
          },
        });
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final permissionState = providerController.permissionStateStore
            .stateFor(runtimeIdentity);
        expect(
          permissionState.threadStates['thread-a']?.selection.optionId,
          ':read-only',
        );
        expect(
          permissionState.threadStates['thread-a']?.source,
          AgentPermissionStateSource.serverSettings,
        );
        expect(permissionState.threadStates['thread-b'], isNull);
        expect(permissionState.providerDefaultPreference, defaultBefore);
        expect(first.permissionSelection?.optionId, ':read-only');
        expect(second.permissionSelection, secondBefore);
        expect(
          peer.calls.length,
          callsBefore,
          reason: 'settings feedback must not trigger a second provider apply',
        );
      },
    );

    test(
      'current thread effective wins over provider default for fork',
      () async {
        final peer = RecordingJsonRpcPeer();
        final config = AgentProviderConfig.defaultCodex
            .withPermissionPreference(':workspace');
        final provider = CodexAppServerAgentProvider(
          config: config,
          peer: peer,
        );
        final providerController = ActiveAgentProviderController(
          providerFactory: FixedAgentProviderFactory(provider),
          configStore: MemoryAgentProviderConfigStore(
            AgentProviderSettings(
              providers: <AgentProviderConfig>[
                config,
                AgentProviderConfig.defaultGrok,
              ],
              activeProviderId: config.id,
            ),
          ),
        );
        addTearDown(providerController.dispose);
        final permissions = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {},
        );
        final viewModel = AgentConversationViewModel(
          providerController: providerController,
          permissionSelectionController: permissions,
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        addTearDown(viewModel.dispose);
        viewModel.updateWorkspace(
          projectPath: '/repo',
          contextFilePath: null,
          restoredSessionId: 'source-thread',
          restoredProviderId: defaultAgentProviderId,
          resetConversation: true,
        );
        await permissions.applyThreadSettings(
          threadId: 'source-thread',
          permissionSelection: const AgentPermissionSelection(
            optionId: ':read-only',
          ),
        );
        final forkSnapshot = permissions.snapshotForRequest(
          threadId: 'source-thread',
        );
        expect(forkSnapshot.selection?.optionId, ':read-only');
        expect(
          forkSnapshot.source,
          AgentPermissionRequestSource.threadEffective,
        );

        await viewModel.forkCurrentThread();

        _expectCodexPermissionParams(
          peer.callForThread('thread/fork', 'source-thread').paramsMap,
          approvalPolicy: 'on-request',
          permissionProfileId: ':read-only',
        );
      },
    );

    test('thread settings domain event exposes neutral permission only', () {
      final source = File(
        'lib/src/features/agent/domain/agent_event_models.dart',
      ).readAsStringSync();
      final classStart = source.indexOf(
        'class AgentThreadSettingsUpdatedEvent',
      );
      final nextClass = source.indexOf('\nclass ', classStart + 1);
      expect(classStart, isNonNegative);
      expect(nextClass, greaterThan(classStart));
      final declaration = source.substring(classStart, nextClass);

      expect(
        declaration,
        contains('AgentPermissionSelection? permissionSelection'),
      );
      for (final forbidden in const <String>[
        'approvalPolicy',
        'sandboxPolicy',
        'activePermissionProfileId',
      ]) {
        expect(declaration, isNot(contains(forbidden)));
      }
    });

    test(
      'shared application and presentation do not decode Codex settings',
      () {
        for (final rootPath in const <String>[
          'lib/src/features/agent/application',
          'lib/src/features/agent/presentation',
        ]) {
          final files = Directory(rootPath)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'));
          for (final file in files) {
            final source = file.readAsStringSync();
            expect(
              source,
              isNot(contains('CodexPermissionPolicyCodec')),
              reason: file.path,
            );
            for (final protocolField in const <String>[
              'approvalPolicy',
              'sandboxPolicy',
              'activePermissionProfile',
            ]) {
              expect(
                source,
                isNot(contains(protocolField)),
                reason: '${file.path}: $protocolField',
              );
            }
          }
        }
      },
    );

    test('V2 priority and provider migrator fixture table stays executable', () {
      final fixture = readFixtureJsonMap(
        'agent_permission_runtime_architecture/permission_migration_cases.json',
      );
      expect(fixture['schemaVersion'], 1);
      final cases = fixture['cases']! as List<Object?>;
      expect(cases, isNotEmpty);

      for (final value in cases) {
        final row = (value! as Map<Object?, Object?>).map(
          (key, item) => MapEntry(key.toString(), item),
        );
        final input = row['input']! as Map<Object?, Object?>;
        final config = _permissionConfigCodec().decodeProvider(input);
        expect(config, isNotNull, reason: row['id']!.toString());
        expect(
          config!.selectedPermissionOptionId,
          row['expectedOptionId'],
          reason: row['id']!.toString(),
        );
      }

      final migrators = cases
          .map((value) => value! as Map<Object?, Object?>)
          .map((row) => row['expectedMigrator'])
          .toSet();
      expect(
        migrators,
        containsAll(<Object?>['v2-short-circuit', 'codex', 'grok', 'generic']),
      );
    });

    test('provider-specific permission migration is data-owned and registered', () {
      final providerModelSource = File(
        'lib/src/features/agent/domain/agent_provider_models.dart',
      ).readAsStringSync();
      final legacyDomainMigration = File(
        'lib/src/features/agent/domain/agent_permission_preference_migration.dart',
      );
      final dataMigration = File(
        'lib/src/features/agent/data/agent_provider_permission_migration.dart',
      );
      final appSource = File('lib/src/app/app.dart').readAsStringSync();

      expect(
        providerModelSource.contains(
          'AgentPermissionPreferenceMigration.resolveOptionId',
        ),
        isFalse,
        reason:
            'domain config decoding must delegate legacy fields to a data migrator registry',
      );
      expect(
        legacyDomainMigration.existsSync(),
        isFalse,
        reason:
            'Codex/Grok legacy protocol strings must leave the shared domain',
      );
      expect(dataMigration.existsSync(), isTrue);
      expect(appSource, contains('CodexPermissionPreferenceMigrator'));
      expect(appSource, contains('GrokPermissionPreferenceMigrator'));
    });

    test('domain contains no provider permission protocol strings', () {
      final domainFiles = Directory('lib/src/features/agent/domain')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in domainFiles) {
        final source = file.readAsStringSync();
        for (final forbidden in const <String>[
          ':workspace',
          ':read-only',
          ':danger-full-access',
          'approvalPolicy',
          'sandboxPolicy',
          'selectedPermissionProfileId',
          'selectedPermissionMode',
          'yolo',
          'always-approve',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason: '${file.path}: $forbidden',
          );
        }
      }
    });
  });
}

AgentProviderSettingsCodec _permissionConfigCodec() {
  return AgentProviderSettingsCodec(
    migrationRegistry: AgentProviderPermissionMigrationRegistry(
      <AgentProviderKind, AgentProviderPermissionPreferenceMigrator>{
        AgentProviderKind.codexAppServer:
            const CodexPermissionPreferenceMigrator(),
        AgentProviderKind.acp: const GrokPermissionPreferenceMigrator(),
      },
    ),
  );
}

void _expectCodexPermissionParams(
  Map<String, Object?> params, {
  required String approvalPolicy,
  required String permissionProfileId,
}) {
  expect(params['approvalPolicy'], approvalPolicy);
  expect(params['permissions'], permissionProfileId);
  expect(params.containsKey('sandbox'), isFalse);
  expect(params.containsKey('sandboxPolicy'), isFalse);
}
