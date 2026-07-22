import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/ide_session/domain/recent_project_summary.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/features/ide/views/global_home_page.dart';

@Preview(
  name: '全局首页 · 宽屏亮色',
  group: 'Global Home',
  size: Size(1200, 800),
  brightness: Brightness.light,
)
Widget globalHomeWideLightPreview() => _preview(Brightness.light);

@Preview(
  name: '全局首页 · 宽屏暗色',
  group: 'Global Home',
  size: Size(1200, 800),
  brightness: Brightness.dark,
)
Widget globalHomeWideDarkPreview() => _preview(Brightness.dark);

@Preview(
  name: '全局首页 · 窄屏亮色',
  group: 'Global Home',
  size: Size(520, 760),
  brightness: Brightness.light,
)
Widget globalHomeCompactLightPreview() => _preview(Brightness.light);

@Preview(
  name: '全局首页 · 窄屏暗色',
  group: 'Global Home',
  size: Size(520, 760),
  brightness: Brightness.dark,
)
Widget globalHomeCompactDarkPreview() => _preview(Brightness.dark);

Widget _preview(Brightness brightness) {
  final lightTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'JetBrainsMono',
  );
  final darkTheme = buildIdeThemeData(
    brightness: Brightness.dark,
    codeFontFamily: 'JetBrainsMono',
  );
  final currentTheme = brightness == Brightness.dark ? darkTheme : lightTheme;
  final themeMode = brightness == Brightness.dark
      ? ThemeMode.dark
      : ThemeMode.light;
  final now = DateTime.utc(2026, 7, 21, 15);
  final projects = <RecentProjectSummary>[
    RecentProjectSummary(
      path: '/Users/example/Development/zeta',
      lastOpenedAt: now.subtract(const Duration(minutes: 12)),
    ),
    RecentProjectSummary(
      path: '/Users/example/Development/design-system',
      lastOpenedAt: now.subtract(const Duration(hours: 3)),
    ),
    RecentProjectSummary(
      path: '/Users/example/Development/agent-tools',
      lastOpenedAt: now.subtract(const Duration(days: 1)),
    ),
  ];
  final threads = <AgentThreadSummary>[
    for (var index = 0; index < 4; index += 1)
      AgentThreadSummary(
        id: 'preview-thread-$index',
        providerId: index.isEven ? defaultAgentProviderId : grokAgentProviderId,
        projectPath: projects[index % projects.length].path,
        title: <String>[
          '设计全局软件首页',
          '修复 Provider 连接状态',
          '整理工作台响应式布局',
          '补齐会话恢复测试',
        ][index],
        preview: 'Preview $index',
        createdAt: now.subtract(Duration(days: index + 1)),
        updatedAt: now.subtract(Duration(hours: index + 1)),
        recencyAt: now.subtract(Duration(hours: index + 1)),
        status: index == 1
            ? AgentThreadRuntimeStatus.active
            : AgentThreadRuntimeStatus.idle,
      ),
  ];

  return IdeThemeScope(
    themeMode: themeMode,
    lightTheme: lightTheme,
    darkTheme: darkTheme,
    child: sf.ShadcnApp(
      debugShowCheckedModeBanner: false,
      theme: buildShadcnTheme(lightTheme),
      darkTheme: buildShadcnTheme(darkTheme),
      materialTheme: buildMaterialTheme(currentTheme),
      themeMode: resolveShadcnThemeMode(themeMode),
      home: sf.Scaffold(
        child: GlobalHomePage(
          recentProjects: projects,
          recentThreads: threads,
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
              version: '1.8.2',
              status: HomeProviderStatus.needsLogin,
            ),
          ],
          now: now,
          onOpenProject: previewOpenProject,
          onSelectProject: previewSelectProject,
          onSelectThread: previewSelectThread,
        ),
      ),
    ),
  );
}

void previewOpenProject() {}

void previewSelectProject(String _) {}

void previewSelectThread(AgentThreadSummary _) {}
