import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

import '../../../testing/ide_test_harness.dart';

void main() {
  testWidgets('disabled Agent keeps history visible and hides the composer', (
    tester,
  ) async {
    final provider = FakeAgentProvider();
    final providerController = ActiveAgentProviderController(
      providerFactory: FakeAgentProviderFactory(provider),
      configStore: MemoryAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex.copyWith(enabled: false),
          ],
        ),
      ),
    );
    final viewModel = AgentConversationViewModel(
      providerController: providerController,
    );
    addTearDown(() {
      viewModel.dispose();
      providerController.dispose();
    });

    await viewModel.loadSettings();
    viewModel.updateWorkspace(
      projectPath: 'C:/workspace',
      contextFilePath: null,
    );
    await viewModel.switchThread(
      agentThread(
        id: 'thread-disabled',
        projectPath: 'C:/workspace',
        title: 'Existing history',
      ),
    );
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
  await tester.pumpWidget(
    IdeThemeScope(
      themeMode: ThemeMode.light,
      lightTheme: ideTheme,
      darkTheme: buildIdeThemeData(
        brightness: Brightness.dark,
        codeFontFamily: 'JetBrainsMono',
      ),
      child: sf.ShadcnApp(
        theme: buildShadcnTheme(ideTheme),
        materialTheme: buildMaterialTheme(ideTheme),
        home: sf.Scaffold(child: AgentPane(viewModel: viewModel)),
      ),
    ),
  );
  await tester.pump();
}
