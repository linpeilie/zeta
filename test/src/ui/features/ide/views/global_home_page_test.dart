import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/features/ide/views/global_home_page.dart';

import '../../../core/ide_component_test_harness.dart';

void main() {
  testWidgets('stacks title, subtitle and open action into one column', (
    tester,
  ) async {
    var openProjectCount = 0;

    await pumpIdeComponent(
      tester,
      size: const Size(1100, 900),
      child: GlobalHomePage(
        installedProviders: const <HomeProviderSummary>[],
        onOpenProject: () {
          openProjectCount += 1;
        },
      ),
    );

    expect(find.text('欢迎使用 Zeta'), findsOneWidget);
    // 近期项目 / 近期会话已从首页移除，入口只剩左侧 Projects 栏。
    expect(find.text('近期项目'), findsNothing);
    expect(find.text('近期会话'), findsNothing);

    final title = tester.getRect(
      find.byKey(const ValueKey<String>('global-home-title')),
    );
    final subtitle = tester.getRect(
      find.byKey(const ValueKey<String>('global-home-subtitle')),
    );
    final button = tester.getRect(
      find.byKey(const ValueKey<String>('global-home-open-project')),
    );
    // 打开项目压在副标题正下方，而不是与标题并排在右端。
    expect(subtitle.top, greaterThan(title.top));
    expect(button.top, greaterThan(subtitle.bottom - 0.5));
    expect(button.left, closeTo(title.left, 0.5));
    // 标题必须明显大于副标题，才撑得住「绝对视觉中心」。
    expect(title.height, greaterThan(subtitle.height));

    await tester.tap(
      find.byKey(const ValueKey<String>('global-home-open-project')),
    );
    await tester.pump();

    expect(openProjectCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders providers as one flat list with indented dividers', (
    tester,
  ) async {
    await pumpIdeComponent(
      tester,
      size: const Size(1100, 900),
      child: GlobalHomePage(
        installedProviders: const <HomeProviderSummary>[
          HomeProviderSummary(
            id: defaultAgentProviderId,
            displayName: 'Codex',
            vendor: 'OpenAI',
            version: '0.42.0',
            status: HomeProviderStatus.available,
          ),
          HomeProviderSummary(
            id: grokAgentProviderId,
            displayName: 'Grok',
            vendor: 'xAI',
            status: HomeProviderStatus.needsLogin,
          ),
        ],
        onOpenProject: () {},
      ),
    );

    final codexProvider = find.byKey(
      const ValueKey<String>('global-home-provider-codex'),
    );
    final grokProvider = find.byKey(
      const ValueKey<String>('global-home-provider-grok'),
    );
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('可用'), findsOneWidget);
    expect(find.text('需登录'), findsOneWidget);
    expect(
      find.descendant(
        of: codexProvider,
        matching: find.byKey(
          const ValueKey<String>('agent-provider-icon-svg-codex'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: grokProvider,
        matching: find.byKey(
          const ValueKey<String>('agent-provider-icon-svg-grok'),
        ),
      ),
      findsOneWidget,
    );

    // 最后一行不画线，行间那条线缩进到标题左边缘。
    expect(
      find.descendant(of: grokProvider, matching: find.byType(IdeRowDivider)),
      findsNothing,
    );
    // 量的是线本身，不是 IdeRowDivider 那层带缩进 padding 的盒子。
    final line = tester.getRect(
      find.descendant(
        of: find.descendant(
          of: codexProvider,
          matching: find.byType(IdeRowDivider),
        ),
        matching: find.byType(ColoredBox),
      ),
    );
    final codexTitle = tester.getRect(
      find.descendant(of: codexProvider, matching: find.text('Codex')),
    );
    expect(line.left, closeTo(codexTitle.left, 0.5));
    expect(line.height, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps cached providers while reporting detection failures', (
    tester,
  ) async {
    await pumpIdeComponent(
      tester,
      size: const Size(900, 760),
      child: GlobalHomePage(
        installedProviders: const <HomeProviderSummary>[
          HomeProviderSummary(
            id: defaultAgentProviderId,
            displayName: 'Codex',
            vendor: 'OpenAI',
            status: HomeProviderStatus.available,
          ),
        ],
        providerError: 'provider refresh failed',
        onOpenProject: () {},
      ),
    );

    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('检测失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the detecting placeholder before providers arrive', (
    tester,
  ) async {
    await pumpIdeComponent(
      tester,
      size: const Size(700, 760),
      child: GlobalHomePage(
        installedProviders: const <HomeProviderSummary>[],
        isLoadingProviders: true,
        onOpenProject: () {},
      ),
    );

    expect(find.text('正在检测 Provider…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('global-home-providers-loading')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a narrow large-text viewport', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(520, 760),
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: GlobalHomePage(
          installedProviders: const <HomeProviderSummary>[
            HomeProviderSummary(
              id: defaultAgentProviderId,
              displayName: 'Codex With A Very Long Display Name',
              vendor: 'OpenAI',
              version: '0.42.0',
              status: HomeProviderStatus.available,
            ),
          ],
          onOpenProject: () {},
        ),
      ),
    );

    expect(find.text('欢迎使用 Zeta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('maps managed Agent state to homepage Provider status', () {
    final installed = ManagedAgent.forDefinition(
      definition: AgentDefinition.codex,
      enabled: true,
    ).copyWith(installationState: AgentInstallationState.installed);

    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(runtimeState: AgentRuntimeState.running),
      ).status,
      HomeProviderStatus.running,
    );
    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(runtimeState: AgentRuntimeState.disabled),
      ).status,
      HomeProviderStatus.disabled,
    );
    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(accountState: AgentAccountState.loggedOut),
      ).status,
      HomeProviderStatus.needsLogin,
    );
    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(runtimeState: AgentRuntimeState.error),
      ).status,
      HomeProviderStatus.error,
    );
    // 「可更新」不再是首页状态：能用就是能用，升级归 Agent 管理页管。
    expect(
      HomeProviderSummary.fromManagedAgent(
        installed.copyWith(versionState: AgentVersionState.updateAvailable),
      ).status,
      HomeProviderStatus.available,
    );
  });
}
