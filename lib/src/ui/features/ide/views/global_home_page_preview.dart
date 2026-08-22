import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_ui/zeta_ui.dart';
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
          onOpenProject: previewOpenProject,
        ),
      ),
    ),
  );
}

void previewOpenProject() {}
