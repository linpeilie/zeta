import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta_ui/zeta_ui.dart';

import '../../../testing/provider_settings_test_store.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_composer_state_owner.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store_registry.dart';
import 'package:zeta/src/app/conversation_slice/agent_conversation_slice_composition.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';

import '../../../testing/ide_test_harness.dart';
import '../../../testing/agent_conversation_binding_test_harness.dart';

void main() {
  testWidgets('disabled Agent keeps history visible and hides the composer', (
    tester,
  ) async {
    final provider = FakeAgentProvider();
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
    );
    final providerController = createProviderSettingsTestStore(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            defaultCodexAgentProviderConfig.copyWith(enabled: false),
          ],
        ),
      ),
    );
    final bindingHarness = AgentConversationBindingTestHarness(
      registry: registry,
      settings: providerController,
    );
    final thread = agentThread(
      id: 'thread-disabled',
      projectPath: 'C:/workspace',
      title: 'Existing history',
    );
    final disabledConfig = defaultCodexAgentProviderConfig.copyWith(
      enabled: false,
    );
    final bindingLease = bindingHarness.acquireThread(
      config: disabledConfig,
      threadId: thread.id,
    );
    final viewModel = AgentConversationViewModel(
      providerController: providerController,
      conversationBinding: bindingLease.binding,
      globalRuntime: bindingHarness.globalRuntime,
      composerStateOwner: AgentConversationComposerStateOwner.create(
        providerController: providerController,
      ),
      initialProjectPath: thread.projectPath,
      initialThread: thread,
    );
    addTearDown(() {
      viewModel.dispose();
      unawaited(bindingHarness.close());
      providerController.dispose();
      unawaited(registry.close());
    });

    await viewModel.loadSettings();
    await viewModel.initialization;
    await _pumpAgentPane(tester, viewModel);

    expect(find.text('Existing history'), findsWidgets);
    expect(
      find.byKey(const ValueKey('agent-read-only-notice')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent-message-input')), findsNothing);
    expect(viewModel.canSubmitMessage, isFalse);

    await viewModel.sendMessage('must not be sent');
    expect(provider.sentMessages, isEmpty);

    await providerController.setProviderEnabled(defaultAgentProviderId, true);
    await tester.pump();

    expect(find.byKey(const ValueKey('agent-read-only-notice')), findsNothing);
    expect(find.byKey(const ValueKey('agent-message-input')), findsOneWidget);
  });

  testWidgets('disabling a Provider does not rebind an existing draft', (
    tester,
  ) async {
    // Arrange
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: FakeAgentProviderBundleBuilder.fromFake(
        FakeAgentProvider(),
      ),
    );
    final providerController = createProviderSettingsTestStore(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(builtInAgentProviderSettings),
    );
    final bindingHarness = AgentConversationBindingTestHarness(
      registry: registry,
      settings: providerController,
    );
    final bindingLease = bindingHarness.acquireDraft(
      defaultCodexAgentProviderConfig,
    );
    final viewModel = AgentConversationViewModel(
      providerController: providerController,
      conversationBinding: bindingLease.binding,
      globalRuntime: bindingHarness.globalRuntime,
      composerStateOwner: AgentConversationComposerStateOwner.create(
        providerController: providerController,
      ),
    );
    addTearDown(() {
      viewModel.dispose();
      unawaited(bindingHarness.close());
      providerController.dispose();
      unawaited(registry.close());
    });
    await viewModel.loadSettings();
    viewModel.updateContext(projectPath: 'C:/workspace', contextFilePath: null);
    await _pumpAgentPane(tester, viewModel);

    // Act
    await providerController.setProviderEnabled(defaultAgentProviderId, false);
    await tester.pump();

    // Assert
    expect(viewModel.activeProviderId, defaultAgentProviderId);
    expect(viewModel.activeProviderName, 'Codex');
    expect(
      find.byKey(const ValueKey('agent-read-only-notice')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agent-message-input')), findsNothing);
  });
}

Future<void> _pumpAgentPane(
  WidgetTester tester,
  AgentConversationViewModel viewModel,
) async {
  tester.view
    ..physicalSize = const Size(1000, 800)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  final ideTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'JetBrainsMono',
  );
  final sliceBinding = AgentConversationSliceComposition(
    regions: viewModel,
    commands: viewModel,
  );
  final sliceRegistry = AgentConversationSliceStoreRegistry()
    ..bind((requestedKey) {
      if (requestedKey == viewModel.conversationBinding.key) {
        return sliceBinding.store;
      }
      throw StateError('No test conversation slice for $requestedKey');
    });
  addTearDown(() {
    sliceRegistry.unbind();
    sliceBinding.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentConversationSliceStoreRegistryProvider.overrideWithValue(
          sliceRegistry,
        ),
      ],
      child: IdeThemeScope(
        themeMode: ThemeMode.light,
        lightTheme: ideTheme,
        darkTheme: buildIdeThemeData(
          brightness: Brightness.dark,
          codeFontFamily: 'JetBrainsMono',
        ),
        child: sf.ShadcnApp(
          locale: ZetaLocalization.simplifiedChinese,
          supportedLocales: ZetaLocalization.supportedLocales,
          localizationsDelegates: ZetaLocalization.delegates,
          theme: buildShadcnTheme(ideTheme),
          builder: (context, child) => IdeMaterialLayer(
            theme: buildMaterialTheme(ideTheme),
            child: child,
          ),
          home: sf.Scaffold(child: AgentPane(viewModel: viewModel)),
        ),
      ),
    ),
  );
  await tester.pump();
}
