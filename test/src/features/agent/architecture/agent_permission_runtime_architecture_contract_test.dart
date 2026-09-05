import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import '../../../testing/agent_provider_implementations.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import '../../../testing/provider_settings_test_store.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_composer_state_owner.dart';

import '../../../testing/agent_conversation_binding_test_harness.dart';
import '../../../testing/fake_agent_frame_scheduler.dart';
import '../../../testing/recording_json_rpc_peer.dart';
import '../../../testing/memory_feature_stores.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('permission runtime architecture contracts', () {
    test(
      'Codex create resume fork and send encode independent request snapshots',
      () async {
        final peer = RecordingJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: defaultCodexAgentProviderConfig,
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
      final first = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {
          fail('settings feedback must not persist the provider default');
        },
      );
      final second = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {
          fail('settings feedback must not persist the provider default');
        },
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      first.bind(
        port: null,
        persistedOptionId: ':workspace',
        runtimeIdentity: const AgentProviderRuntimeIdentity(
          providerId: defaultAgentProviderId,
          generation: 1,
        ),
      );
      second.bind(
        port: null,
        persistedOptionId: ':workspace',
        runtimeIdentity: const AgentProviderRuntimeIdentity(
          providerId: defaultAgentProviderId,
          generation: 2,
        ),
      );
      first.bindThread('thread-a');
      second.bindThread('thread-b');

      await first.applyThreadSettings(
        threadId: 'thread-a',
        permissionSelection: const AgentPermissionSelection(
          optionId: ':read-only',
        ),
      );

      expect(first.defaultOptionId, ':workspace');
      expect(first.selectedOptionId, ':read-only');
      expect(second.defaultOptionId, ':workspace');
      expect(second.selectedOptionId, ':workspace');
    });

    test('Grok runtime scope stays inside its owning Binding', () async {
      var firstRuntimeMode = GrokPermissionMode.ask;
      var secondRuntimeMode = GrokPermissionMode.ask;
      final notifications = <({String method, Map<String, Object?> params})>[];
      final firstAdapter = GrokPermissionPolicyAdapter(
        isInitialized: () => true,
        isDisposed: () => false,
        currentMode: () => firstRuntimeMode,
        onModeApplied: (next) => firstRuntimeMode = next,
        notifyLive: (method, params) {
          notifications.add((method: method, params: params));
        },
      );
      final secondAdapter = GrokPermissionPolicyAdapter(
        isInitialized: () => true,
        isDisposed: () => false,
        currentMode: () => secondRuntimeMode,
        onModeApplied: (next) => secondRuntimeMode = next,
        notifyLive: (_, _) {},
      );
      final first = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      final second = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      addTearDown(() {
        first.dispose();
        second.dispose();
      });
      first.bind(
        port: firstAdapter,
        persistedOptionId: 'ask',
        runtimeIdentity: const AgentProviderRuntimeIdentity(
          providerId: grokAgentProviderId,
          generation: 1,
        ),
      );
      first.bindThread('thread-a');
      second.bind(
        port: secondAdapter,
        persistedOptionId: 'ask',
        runtimeIdentity: const AgentProviderRuntimeIdentity(
          providerId: grokAgentProviderId,
          generation: 2,
        ),
      );
      second.bindThread('thread-b');

      await first.selectOption(
        const AgentPermissionOption(
          id: 'always-approve',
          label: 'Always approve',
        ),
      );

      expect(firstRuntimeMode, GrokPermissionMode.alwaysApprove);
      expect(secondRuntimeMode, GrokPermissionMode.ask);
      expect(notifications, hasLength(1));
      expect(notifications.single.method, '_x.ai/yolo_mode_changed');
      expect(notifications.single.params, <String, Object?>{
        'permission_mode': 'always-approve',
        'yolo_mode': true,
        'auto_mode': false,
        'clientIdentifier': 'zeta',
      });
      expect(first.selectedOptionId, 'always-approve');
      expect(second.selectedOptionId, 'ask');
    });

    test(
      'two ViewModels sharing Codex keep real resume and turn params isolated',
      () async {
        final peer = RecordingJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: defaultCodexAgentProviderConfig,
          peer: peer,
        );
        final registry = AgentProviderRuntimeRegistry(
          providerFactory: FixedAgentProviderBundleFactory(provider),
        );
        final providerController = createProviderSettingsTestStore(
          runtimeRegistry: registry,
          configStore: MemoryAgentProviderConfigStore(),
        );
        addTearDown(providerController.dispose);
        addTearDown(registry.close);
        final bindingHarness = AgentConversationBindingTestHarness(
          registry: registry,
          settings: providerController,
        );
        addTearDown(bindingHarness.close);
        final firstThread = _threadSummary('thread-a');
        final secondThread = _threadSummary('thread-b');
        final firstBinding = bindingHarness.acquireThread(
          config: provider.config,
          threadId: firstThread.id,
        );
        final secondBinding = bindingHarness.acquireThread(
          config: provider.config,
          threadId: secondThread.id,
        );

        final first = AgentConversationRuntimeController(
          providerController: providerController,
          conversationBinding: firstBinding.binding,
          globalRuntime: bindingHarness.globalRuntime,
          composerStateOwner: AgentConversationComposerStateOwner.create(
            providerController: providerController,
          ),
          initialProjectPath: '/repo',
          initialThread: firstThread,
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        final second = AgentConversationRuntimeController(
          providerController: providerController,
          conversationBinding: secondBinding.binding,
          globalRuntime: bindingHarness.globalRuntime,
          composerStateOwner: AgentConversationComposerStateOwner.create(
            providerController: providerController,
          ),
          initialProjectPath: '/repo',
          initialThread: secondThread,
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        await Future.wait(<Future<void>>[
          first.initialization,
          second.initialization,
          first.loadModels(),
          second.loadModels(),
        ]);
        await firstBinding.binding.permissions.applyThreadSettings(
          threadId: 'thread-a',
          permissionSelection: const AgentPermissionSelection(
            optionId: ':read-only',
          ),
        );
        await secondBinding.binding.permissions.applyThreadSettings(
          threadId: 'thread-b',
          permissionSelection: const AgentPermissionSelection(
            optionId: ':danger-full-access',
          ),
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
          config: defaultCodexAgentProviderConfig,
          peer: peer,
        );
        final registry = AgentProviderRuntimeRegistry(
          providerFactory: FixedAgentProviderBundleFactory(provider),
        );
        final providerController = createProviderSettingsTestStore(
          runtimeRegistry: registry,
          configStore: MemoryAgentProviderConfigStore(),
        );
        addTearDown(providerController.dispose);
        addTearDown(registry.close);
        final bindingHarness = AgentConversationBindingTestHarness(
          registry: registry,
          settings: providerController,
        );
        addTearDown(bindingHarness.close);
        final firstThread = _threadSummary('thread-a');
        final secondThread = _threadSummary('thread-b');
        final firstBinding = bindingHarness.acquireThread(
          config: provider.config,
          threadId: firstThread.id,
        );
        final secondBinding = bindingHarness.acquireThread(
          config: provider.config,
          threadId: secondThread.id,
        );

        final first = AgentConversationRuntimeController(
          providerController: providerController,
          conversationBinding: firstBinding.binding,
          globalRuntime: bindingHarness.globalRuntime,
          composerStateOwner: AgentConversationComposerStateOwner.create(
            providerController: providerController,
          ),
          initialProjectPath: '/repo',
          initialThread: firstThread,
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        final second = AgentConversationRuntimeController(
          providerController: providerController,
          conversationBinding: secondBinding.binding,
          globalRuntime: bindingHarness.globalRuntime,
          composerStateOwner: AgentConversationComposerStateOwner.create(
            providerController: providerController,
          ),
          initialProjectPath: '/repo',
          initialThread: secondThread,
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        await Future.wait(<Future<void>>[
          first.initialization,
          second.initialization,
          first.loadModels(),
          second.loadModels(),
        ]);
        // 打开历史只走 global runtime；首次提交后才建立 session 事件流。
        await first.sendMessage('bind first canvas runtime');
        final defaultBefore =
            firstBinding.binding.permissions.defaultPreference;
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

        final permissionState = firstBinding.binding.permissions.state;
        expect(
          permissionState.sessionEffective?.selection.optionId,
          ':read-only',
        );
        expect(
          permissionState.sessionEffective?.source,
          AgentPermissionStateSource.serverSettings,
        );
        expect(
          secondBinding.binding.permissions.state.sessionEffective,
          isNull,
        );
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
        final config = defaultCodexAgentProviderConfig.withPermissionPreference(
          ':workspace',
        );
        final provider = CodexAppServerAgentProvider(
          config: config,
          peer: peer,
        );
        final registry = AgentProviderRuntimeRegistry(
          providerFactory: FixedAgentProviderBundleFactory(provider),
        );
        final providerController = createProviderSettingsTestStore(
          runtimeRegistry: registry,
          configStore: MemoryAgentProviderConfigStore(
            AgentProviderSettings(
              providers: <AgentProviderConfig>[
                config,
                defaultGrokAgentProviderConfig,
              ],
              activeProviderId: config.id,
            ),
          ),
        );
        addTearDown(providerController.dispose);
        addTearDown(registry.close);
        final bindingHarness = AgentConversationBindingTestHarness(
          registry: registry,
          settings: providerController,
        );
        addTearDown(bindingHarness.close);
        final thread = _threadSummary('source-thread');
        final bindingLease = bindingHarness.acquireThread(
          config: config,
          threadId: thread.id,
        );
        final permissions = bindingLease.binding.permissions;
        final viewModel = AgentConversationRuntimeController(
          providerController: providerController,
          conversationBinding: bindingLease.binding,
          globalRuntime: bindingHarness.globalRuntime,
          composerStateOwner: AgentConversationComposerStateOwner.create(
            providerController: providerController,
          ),
          initialProjectPath: '/repo',
          initialThread: thread,
          onCreatedThread:
              ({
                required session,
                required context,
                String? initialMessage,
              }) async {},
          uiFrameScheduler: FakeAgentFrameScheduler(),
        );
        addTearDown(viewModel.dispose);
        await viewModel.initialization;
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
        'packages/zeta_agent_core/lib/src/domain/agent_event_models.dart',
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
          'packages/zeta_agent_core/lib/src/application',
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

    test('provider definitions have no legacy permission migration surface', () {
      final providerModelSource = File(
        'packages/zeta_agent_core/lib/src/domain/agent_provider_models.dart',
      ).readAsStringSync();
      final dataMigration = File(
        'packages/zeta_agent_provider_api/lib/src/agent_provider_permission_migration.dart',
      );
      final codexPluginSource = File(
        'packages/zeta_agent_provider_codex/lib/codex_plugin.dart',
      ).readAsStringSync();
      final grokPluginSource = File(
        'packages/zeta_agent_provider_grok/lib/grok_plugin.dart',
      ).readAsStringSync();
      final appSource = File('lib/src/app/app.dart').readAsStringSync();

      expect(providerModelSource, isNot(contains('supportedVersions')));
      expect(dataMigration.existsSync(), isFalse);
      expect(
        codexPluginSource,
        isNot(contains('PermissionPreferenceMigrator')),
      );
      expect(grokPluginSource, isNot(contains('PermissionPreferenceMigrator')));
      expect(appSource, isNot(contains('PermissionPreferenceMigrator')));
    });

    test('legacy permission facades and domain config decoders are absent', () {
      expect(
        File(
          'packages/zeta_agent_core/lib/src/domain/agent_provider.dart',
        ).existsSync(),
        isFalse,
      );
      final turnConfiguration = File(
        'packages/zeta_agent_core/lib/src/domain/agent_conversation_mode_models.dart',
      ).readAsStringSync();
      final providerModels = File(
        'packages/zeta_agent_core/lib/src/domain/agent_provider_models.dart',
      ).readAsStringSync();
      final codexProvider = File(
        'packages/zeta_agent_provider_codex/lib/src/datasources/app_server/'
        'codex_app_server_agent_provider.dart',
      ).readAsStringSync();

      expect(
        turnConfiguration,
        isNot(contains('AgentTurnConfiguration.permissionSelection')),
      );
      expect(codexProvider, isNot(contains('_withLegacyPermissionSelection')));
      expect(
        providerModels,
        isNot(contains('static AgentProviderConfig? tryDecode')),
      );
      expect(
        providerModels,
        isNot(contains('static AgentProviderSettings tryDecode')),
      );
      expect(
        File(
          'test/src/features/agent/agent_permission_review_regression_test.dart',
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          'test/fixtures/agent_permission_runtime_architecture/'
          'expected_api_changes.md',
        ).existsSync(),
        isFalse,
      );
    });

    test('shared application domain and presentation contain no provider '
        'permission protocol', () {
      final sharedFiles =
          <String>[
            'packages/zeta_agent_core/lib/src/application',
            'packages/zeta_agent_core/lib/src/domain',
            'lib/src/features/agent/presentation',
            'lib/src/features/project_threads/application',
            'lib/src/features/project_threads/domain',
            'lib/src/features/project_threads/presentation',
            'lib/src/ui',
          ].expand(
            (root) => Directory(root)
                .listSync(recursive: true)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart')),
          );

      for (final file in sharedFiles) {
        final source = file.readAsStringSync();
        for (final forbidden in const <String>[
          ':workspace',
          ':read-only',
          ':danger-full-access',
          'permissionProfile/list',
          'approvalPolicy',
          'sandboxPolicy',
          'activePermissionProfile',
          'selectedPermissionProfileId',
          'selectedPermissionMode',
          "'permission_mode'",
          '"permission_mode"',
          'yoloMode',
          'always-approve',
          'workspace-write',
          'danger-full-access',
          'on-request',
          'on-failure',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason: '${file.path}: $forbidden',
          );
        }
        for (final parserShape in const <String>[
          'optionId.split(',
          'optionId.startsWith(',
          'optionId.endsWith(',
          'optionId.contains(',
          'optionId.substring(',
        ]) {
          expect(
            source,
            isNot(contains(parserShape)),
            reason: '${file.path}: provider-specific $parserShape',
          );
        }
      }
    });
  });
}

AgentThreadSummary _threadSummary(String id) {
  final timestamp = DateTime(2025);
  return AgentThreadSummary(
    id: id,
    providerId: defaultAgentProviderId,
    projectPath: '/repo',
    title: id,
    preview: id,
    createdAt: timestamp,
    updatedAt: timestamp,
    recencyAt: timestamp,
    status: AgentThreadRuntimeStatus.idle,
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
