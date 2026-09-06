import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';

typedef AgentBindingSweepTimerFactory =
    Timer Function(Duration, void Function(Timer));

/// Injectable scheduler; session resource ownership remains with the app.
final agentBindingSweepTimerFactoryProvider =
    Provider<AgentBindingSweepTimerFactory>(
      (ref) => Timer.periodic,
      name: 'agentBindingSweepTimerFactory',
    );

/// App owns these resources; Workspace, Shell and runners only borrow them.
/// No onDispose close: shutdown must drain runners before releasing bindings.
final agentConversationBindingManagerProvider =
    Provider<AgentConversationBindingManager>(
      (ref) => AgentConversationBindingManager(
        runtimeRegistry: ref.read(agentProviderRuntimeRegistryProvider),
        textCatalog: ref.read(agentUiTextCatalogProvider),
        timerFactory: ref.read(agentBindingSweepTimerFactoryProvider),
      )..start(),
      name: 'agentConversationBindingManager',
    );

final agentProviderGlobalRuntimeProvider = Provider<AgentProviderGlobalRuntime>(
  (ref) => AgentProviderGlobalRuntime(
    runtimeRegistry: ref.read(agentProviderRuntimeRegistryProvider),
  ),
  name: 'agentProviderGlobalRuntime',
);
