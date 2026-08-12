import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';

import '../../../../ui/core/ide_component_test_harness.dart';

void main() {
  testWidgets('renders bundled Codex, Grok, and Claude SVG assets', (
    tester,
  ) async {
    await pumpIdeComponent(
      tester,
      child: const Row(
        children: <Widget>[
          AgentProviderIcon(
            providerId: defaultAgentProviderId,
            size: 20,
            color: Colors.red,
            semanticLabel: 'Codex Agent',
          ),
          AgentProviderIcon(
            providerId: grokAgentProviderId,
            size: 24,
            color: Colors.blue,
            semanticLabel: 'Grok Agent',
          ),
          AgentProviderIcon(
            providerId: defaultClaudeCodeProviderId,
            size: 22,
            color: Colors.green,
            semanticLabel: 'Claude Agent',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final pictures = tester
        .widgetList<svg.SvgPicture>(find.byType(svg.SvgPicture))
        .toList(growable: false);
    final assetNames = pictures
        .map((picture) => picture.bytesLoader)
        .whereType<svg.SvgAssetLoader>()
        .map((loader) => loader.assetName)
        .toList(growable: false);

    expect(pictures, hasLength(3));
    expect(assetNames, <String>[
      'assets/icons/agents/codex.svg',
      'assets/icons/agents/grok.svg',
      'assets/icons/agents/claude.svg',
    ]);
    expect(pictures[0].width, 20);
    expect(pictures[0].height, 20);
    expect(pictures[0].fit, BoxFit.contain);
    expect(pictures[0].colorFilter, isNotNull);
    expect(pictures[1].width, 24);
    expect(pictures[1].height, 24);
    expect(pictures[2].width, 22);
    expect(pictures[2].height, 22);
    expect(find.bySemanticsLabel('Codex Agent'), findsOneWidget);
    expect(find.bySemanticsLabel('Grok Agent'), findsOneWidget);
    expect(find.bySemanticsLabel('Claude Agent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back by provider kind when no SVG is registered', (
    tester,
  ) async {
    await pumpIdeComponent(
      tester,
      child: const AgentProviderIcon(
        providerId: 'custom-claude-provider',
        kind: AgentProviderKind.claudeCode,
        size: 22,
        color: Colors.green,
        semanticLabel: 'Claude Agent',
      ),
    );

    final fallback = find.byKey(
      const ValueKey<String>(
        'agent-provider-icon-fallback-custom-claude-provider',
      ),
    );
    final icon = tester.widget<Icon>(fallback);

    expect(fallback, findsOneWidget);
    expect(find.byType(svg.SvgPicture), findsNothing);
    expect(icon.icon, Icons.terminal_rounded);
    expect(icon.size, 22);
    expect(icon.color, Colors.green);
    expect(find.bySemanticsLabel('Claude Agent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
