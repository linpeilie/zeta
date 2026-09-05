import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/app/plugins/agent_provider_icon_overrides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';

import '../../../../ui/core/ide_component_test_harness.dart';

void main() {
  testWidgets('renders bundled Codex, Grok, and Claude SVG assets', (
    tester,
  ) async {
    await _pumpIcons(
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
      'assets/icon.svg',
      'assets/icon.svg',
      'assets/icon.svg',
    ]);
    expect(
      pictures.map((p) => (p.bytesLoader as svg.SvgAssetLoader).packageName),
      [
        'zeta_agent_provider_codex',
        'zeta_agent_provider_grok',
        'zeta_agent_provider_claude_code',
      ],
    );
    expect(pictures[0].width, 20);
    expect(pictures[0].height, 20);
    expect(pictures[0].fit, BoxFit.contain);
    expect(pictures[0].colorFilter, isNotNull);
    expect(pictures[1].width, 24);
    expect(pictures[1].height, 24);
    expect(pictures[1].colorFilter, isNotNull);
    expect(pictures[2].width, 22);
    expect(pictures[2].height, 22);
    expect(
      pictures[2].colorFilter,
      isNull,
      reason: 'Claude SVG must preserve its bundled brand color',
    );
    expect(find.bySemanticsLabel('Codex Agent'), findsOneWidget);
    expect(find.bySemanticsLabel('Grok Agent'), findsOneWidget);
    expect(find.bySemanticsLabel('Claude Agent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every declared package icon is bundled and decodes as SVG', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final definition in zetaAgentProviderDefinitions) {
        final icon = definition.icon;
        if (icon == null) continue;
        final key = 'packages/${icon.packageName}/${icon.assetPath}';
        expect(manifest.listAssets(), contains(key));
        final bytes = await svg.SvgAssetLoader(
          icon.assetPath,
          packageName: icon.packageName,
        ).loadBytes(null);
        expect(bytes.lengthInBytes, greaterThan(0), reason: key);
      }
    });
  });

  testWidgets('a fourth definition renders through the same static catalog', (
    tester,
  ) async {
    // 测试目录复用已打包的资源；新增身份无需在 Widget 添加任何厂商映射。
    final icon = zetaAgentProviderDefinitions.first.icon!;
    await _pumpIcons(
      tester,
      catalog: AgentProviderDefinitionCatalog([
        ...zetaAgentProviderDefinitions,
        _definition('fourth', icon: icon),
        _definition('without-icon'),
      ]),
      child: const Row(
        children: [
          AgentProviderIcon(providerId: 'fourth'),
          AgentProviderIcon(providerId: 'without-icon'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final picture = tester.widget<svg.SvgPicture>(find.byType(svg.SvgPicture));
    final loader = picture.bytesLoader as svg.SvgAssetLoader;
    expect(loader.packageName, icon.packageName);
    expect(loader.assetName, icon.assetPath);
    expect(picture.excludeFromSemantics, isTrue);
    expect(
      find.byKey(const ValueKey('agent-provider-icon-svg-fourth')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-provider-icon-fallback-without-icon')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SVG error rendering retains the neutral fallback and semantics',
    (tester) async {
      await _pumpIcons(
        tester,
        child: const AgentProviderIcon(
          providerId: defaultAgentProviderId,
          size: 26,
          color: Colors.green,
          semanticLabel: 'Missing icon',
        ),
      );
      await tester.pumpAndSettle();
      final finder = find.byType(svg.SvgPicture);
      final picture = tester.widget<svg.SvgPicture>(finder);
      // 独立验证宿主错误渲染契约；真实资源加载和解码由上面的动态用例验证。
      final fallbackWidget = picture.errorBuilder!(
        tester.element(finder),
        StateError('Missing fixture asset'),
        StackTrace.current,
      );
      await _pumpIcons(tester, child: fallbackWidget);
      final fallback = tester.widget<Icon>(
        find.byKey(const ValueKey('agent-provider-icon-fallback-codex')),
      );
      expect(fallback.icon, Icons.extension_outlined);
      expect(fallback.size, 26);
      expect(fallback.color, Colors.green);
      expect(find.bySemanticsLabel('Missing icon'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uses a neutral fallback when no SVG is registered', (
    tester,
  ) async {
    await _pumpIcons(
      tester,
      child: const AgentProviderIcon(
        providerId: 'custom-claude-provider',
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
    expect(icon.icon, Icons.extension_outlined);
    expect(icon.size, 22);
    expect(icon.color, Colors.green);
    expect(find.bySemanticsLabel('Claude Agent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpIcons(
  WidgetTester tester, {
  required Widget child,
  AgentProviderDefinitionCatalog? catalog,
}) => pumpIdeComponent(
  tester,
  child: ProviderScope(
    overrides: [agentProviderIconsOverride(catalog: catalog)],
    child: child,
  ),
);

AgentProviderDefinition _definition(String id, {AgentProviderSvgIcon? icon}) =>
    AgentProviderDefinition(
      providerId: id,
      providerType: AgentProviderTypeId(id),
      defaultConfig: AgentProviderConfig(
        id: id,
        kind: AgentProviderTypeId(id),
        displayName: id,
        command: id,
      ),
      staticCapabilities: AgentProviderCapabilities.unsupported,
      modelCatalogSourceLabel: id,
      metricLabel: const ZetaMetricLabel.constant('fixture'),
      icon: icon,
    );
