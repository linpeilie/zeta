import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_actions.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_owner_key.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_session_dependencies.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_notifier.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_ports.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'memory_agent_composer_attachment_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane_presentation_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane_retention.dart';

export 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_ports.dart';
export 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_notifier.dart';

/// Test composition: installs dependency ports before creating each real Notifier.
/// No Store, state mirror, Widget binding, or alternate command implementation.
final class ConversationTestScope {
  ConversationTestScope({List<Override> overrides = const []}) {
    container = ProviderContainer(
      overrides: [
        agentConversationSessionDependenciesProvider.overrideWith(
          (ref, key) => _inputs[key]!,
        ),
        agentConversationOwnerResolutionProvider.overrideWith((ref, key) {
          for (final input in _inputs.values) {
            if (_initialAliases[input.ownerKey] == key ||
                input.scopeSnapshot().bindingKey == key) {
              return AgentConversationOwnerLive(input.ownerKey);
            }
          }
          return const AgentConversationOwnerUnknown();
        }),
        memoryAgentComposerAttachmentOverride(),
        ...overrides,
      ],
    );
  }
  late final ProviderContainer container;
  final _inputs =
      <AgentConversationOwnerKey, AgentConversationSessionDependencies>{};
  final _initialAliases =
      <AgentConversationOwnerKey, AgentConversationBindingKey>{};
  final _owners = <AgentConversationSliceNotifier>[];
  bool _closed = false;

  AgentConversationSliceNotifier create({
    required AgentConversationRegionSource regions,
    required AgentConversationCommandPort commands,
    AgentConversationCommandScope Function()? scopeSnapshot,
    AgentConversationSliceEffectRunner? effectRunner,
    OperationIdGenerator Function(String)? operationIdGeneratorFactory,
  }) {
    final scope = scopeSnapshot ?? regions.currentCommandScope;
    final key = AgentConversationOwnerKey('test-entry-${_inputs.length}');
    _initialAliases[key] = scope().bindingKey;
    _inputs[key] = AgentConversationSessionDependencies(
      ownerKey: key,
      regions: regions,
      executor: commands,
      scopeSnapshot: scope,
      onProjectionUnobserved: (_) {},
      operationIdGeneratorFactory: operationIdGeneratorFactory,
      runnerFactory: effectRunner == null ? null : (_) => effectRunner,
    );
    final owner = container.read(
      agentConversationSliceOwnerProvider(key).notifier,
    );
    _owners.add(owner);
    return owner;
  }

  AgentConversationActions actionsFor(
    AgentConversationRuntimeController runtime,
  ) {
    for (final input in _inputs.values) {
      if (identical(input.executor, runtime)) {
        return container.read(
          agentConversationSliceOwnerProvider(input.ownerKey).notifier,
        );
      }
    }
    return create(regions: runtime, commands: runtime);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final owner in _owners) {
      owner.closeForEntryRelease();
    }
    if (container.exists(agentPaneRetentionProvider)) {
      final retention = container.read(agentPaneRetentionProvider);
      for (final input in _inputs.values) {
        await retention.closeEntry(input.executor);
      }
    }
    if (container.exists(agentPanePresentationStoreProvider)) {
      final store = container.read(agentPanePresentationStoreProvider);
      for (final input in _inputs.values) {
        store.closeEntry(input.executor);
      }
    }
    container.dispose();
  }
}

ConversationTestScope? _scope;
ConversationTestScope get conversationTestScope {
  final existing = _scope;
  if (existing != null) return existing;
  final created = ConversationTestScope();
  _scope = created;
  addTearDown(() async {
    await created.close();
    if (identical(_scope, created)) _scope = null;
  });
  return created;
}

AgentConversationSliceNotifier connectedConversationTestOwner({
  required AgentConversationRegionSource regions,
  required AgentConversationCommandPort commands,
  AgentConversationCommandScope Function()? scopeSnapshot,
  OperationIdGenerator Function(String)? operationIdGeneratorFactory,
}) => conversationTestScope.create(
  regions: regions,
  commands: commands,
  scopeSnapshot: scopeSnapshot,
  operationIdGeneratorFactory: operationIdGeneratorFactory,
);

AgentConversationSliceNotifier conversationTestOwner({
  required AgentConversationSliceState initialState,
  required AgentConversationSliceEffectRunner effectRunner,
  required AgentConversationCommandScope Function() scopeSnapshot,
  OperationIdGenerator Function(String)? operationIdGeneratorFactory,
}) => conversationTestScope.create(
  regions: _StateRegions(initialState, scopeSnapshot),
  commands: _UnusedCommands(),
  effectRunner: effectRunner,
  scopeSnapshot: scopeSnapshot,
  operationIdGeneratorFactory: operationIdGeneratorFactory,
);

void listenConversationTestOwner(
  AgentConversationSliceNotifier owner,
  void Function() listener,
) {
  conversationTestScope.container.listen(
    agentConversationSliceOwnerProvider(owner.ownerKey),
    (_, _) => listener(),
  );
}

final class _UnusedCommands implements AgentConversationCommandPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused command port');
}

final class _StateRegions implements AgentConversationRegionSource {
  _StateRegions(this.snapshot, this.scope);
  final AgentConversationSliceState snapshot;
  final AgentConversationCommandScope Function() scope;
  @override
  get headerState => snapshot.header;
  @override
  get composerState => snapshot.composer;
  @override
  get pendingInteractionState => snapshot.pendingInteractions;
  @override
  get expansionState => snapshot.expansion;
  @override
  get historyState => snapshot.history;
  @override
  AgentConversationCommandScope currentCommandScope() => scope();
  @override
  void addUiUpdateListener(void Function(AgentUiUpdateRequest) listener) {}
  @override
  void removeUiUpdateListener(void Function(AgentUiUpdateRequest) listener) {}
}

AgentConversationActions conversationTestActions(
  AgentConversationRuntimeController runtime,
) => conversationTestScope.actionsFor(runtime);
