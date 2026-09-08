import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/composition/zeta_app_composition.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/router/app_router.dart';
import 'package:zeta/src/app/window/zeta_ticker_gate.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_mapping.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/presentation/appearance_theme_mode_mapper.dart';

/// 应用根组件。
///
/// **只负责 Widget 那一半**：把 [ZetaAppComposition] 挂到树上、按外观建主题、
/// 就绪后把 `GoRouter` 接到 `ShadcnApp.router`。窗口监听与 ticker 闸门在
/// [ZetaTickerGate]。 `IdeHome` 由 ShellRoute 挂载，不在这里直接构造。
/// 容器、插件目录、Provider 运行时池与三个切片组合都在 composition 里，由调用方
/// 创建——这正是 Riverpod 官方的形状：测试自己建容器、用 overrides 换掉任何依赖，
/// `MainApp` 因此不需要一个注入参数。
///
/// **不拥有 composition**：谁创建谁 `dispose`。
class MainApp extends StatefulWidget {
  const MainApp({super.key, required this.composition});

  /// 组合根。容器与所有跨层依赖都在这里。
  final ZetaAppComposition composition;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  ZetaAppComposition get _composition => widget.composition;

  @override
  void initState() {
    super.initState();
    if (!_composition.isReady) {
      // 组合根还在等常规设置定显示语言；就绪后重挂有文字的 UI。
      _composition.ready.then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 容器归 composition 所有，这里只把它挂到树上。用 `UncontrolledProviderScope`
    // 而不是 `ProviderScope`：生命周期不归 Widget 管，组合根还要在树之外读切片状态
    // （见 `ZetaAppComposition.takeStateSnapshot`）。
    return UncontrolledProviderScope(
      container: _composition.container,
      child: ZetaTickerGate(child: _buildApp(context)),
    );
  }

  Widget _buildApp(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => _buildThemedApp(
        ref,
        appearanceSettingsFromSlice(ref.watch(appearanceSettingsValueProvider)),
      ),
    );
  }

  Widget _buildThemedApp(WidgetRef ref, AppearanceSettings settings) {
    final lightIdeTheme = buildIdeThemeData(
      brightness: Brightness.light,
      uiFontFamily: settings.uiFontFamily,
      codeFontFamily: settings.codeFontFamily,
      uiFontSize: settings.uiFontSize,
      codeFontSize: settings.codeFontSize,
    );
    final darkIdeTheme = buildIdeThemeData(
      brightness: Brightness.dark,
      uiFontFamily: settings.uiFontFamily,
      codeFontFamily: settings.codeFontFamily,
      uiFontSize: settings.uiFontSize,
      codeFontSize: settings.codeFontSize,
    );
    final flutterThemeMode = themeModeForPreference(settings.themeMode);
    final materialBrightness = resolveBrightnessForThemeMode(flutterThemeMode);
    final materialIdeTheme = materialBrightness == Brightness.dark
        ? darkIdeTheme
        : lightIdeTheme;
    return IdeUiTextScope(
      catalog: _composition.zetaUiTextCatalog,
      child: IdeThemeScope(
        themeMode: flutterThemeMode,
        lightTheme: lightIdeTheme,
        darkTheme: darkIdeTheme,
        child: _composition.isReady
            ? sf.ShadcnApp.router(
                debugShowCheckedModeBanner: false,
                title: appTitle,
                locale: _composition.frozenDisplayLocale,
                supportedLocales: ZetaLocalization.supportedLocales,
                localizationsDelegates: ZetaLocalization.delegates,
                theme: buildShadcnTheme(lightIdeTheme),
                darkTheme: buildShadcnTheme(darkIdeTheme),
                themeMode: resolveShadcnThemeMode(flutterThemeMode),
                builder: (context, child) => IdeMaterialLayer(
                  theme: buildMaterialTheme(materialIdeTheme),
                  child: child,
                ),
                routerConfig: ref.watch(appRouterProvider),
              )
            : sf.ShadcnApp(
                debugShowCheckedModeBanner: false,
                title: appTitle,
                locale: _composition.frozenDisplayLocale,
                supportedLocales: ZetaLocalization.supportedLocales,
                localizationsDelegates: ZetaLocalization.delegates,
                theme: buildShadcnTheme(lightIdeTheme),
                darkTheme: buildShadcnTheme(darkIdeTheme),
                themeMode: resolveShadcnThemeMode(flutterThemeMode),
                builder: (context, child) => IdeMaterialLayer(
                  theme: buildMaterialTheme(materialIdeTheme),
                  child: child,
                ),
                home: ColoredBox(
                  key: const ValueKey<String>('zeta.localization-loading'),
                  color: materialIdeTheme.colors.frame,
                ),
              ),
      ),
    );
  }
}
