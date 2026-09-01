import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:window_manager/window_manager.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/composition/zeta_app_composition.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_mapping.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/presentation/appearance_theme_mode_mapper.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

/// 应用根组件。
///
/// **只负责 Widget 那一半**：窗口与生命周期监听、主题构建、把 [ZetaAppComposition]
/// 里已经装好的东西接到 `IdeHome` 上。容器、插件目录、Provider 运行时池与三个切片
/// 组合都在 composition 里，由调用方创建——这正是 Riverpod 官方的形状：测试自己建
/// 容器、用 overrides 换掉任何依赖，`MainApp` 因此不需要一个注入参数。
///
/// **不拥有 composition**：谁创建谁 `dispose`。
class MainApp extends StatefulWidget {
  const MainApp({super.key, required this.composition});

  /// 组合根。容器与所有跨层依赖都在这里。
  final ZetaAppComposition composition;

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp>
    with WidgetsBindingObserver, WindowListener {
  AppLifecycleState? _appLifecycleState;
  bool _nativeWindowSuspended = false;

  ZetaAppComposition get _composition => widget.composition;

  /// 当前窗口宿主；测试里通常是一份什么都不做的 [HeadlessWindowHost]。
  ///
  /// 在 `initState` 解析一次并留住：`dispose()` 里还要退订窗口事件，而组合根
  /// 的容器可能已经先一步关掉了。
  late ZetaWindowHost _windowHost;

  @override
  void initState() {
    super.initState();
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _windowHost = _composition.container.read(zetaWindowHostProvider);
    _windowHost.addListener(this);
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
  void didUpdateWidget(covariant MainApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousHost = _windowHost;
    final currentHost = _composition.container.read(zetaWindowHostProvider);
    if (identical(previousHost, currentHost)) {
      return;
    }
    previousHost.removeListener(this);
    _windowHost = currentHost;
    currentHost.addListener(this);
    _nativeWindowSuspended = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _windowHost.removeListener(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_appLifecycleState == state) {
      return;
    }
    setState(() => _appLifecycleState = state);
  }

  @override
  void onWindowMinimize() => _setNativeWindowSuspended(true);

  @override
  void onWindowRestore() => _resumeNativeWindowTickers();

  @override
  void onWindowMaximize() => _resumeNativeWindowTickers();

  @override
  void onWindowFocus() => _resumeNativeWindowTickers();

  @override
  void onWindowEnterFullScreen() => _resumeNativeWindowTickers();

  @override
  void onWindowEvent(String eventName) {
    // window_manager 0.5.x 会从 Windows WM_SHOWWINDOW 发出 show，
    // 但 WindowListener 尚无对应的强类型回调。
    if (eventName == 'show') {
      _resumeNativeWindowTickers();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 容器归 composition 所有，这里只把它挂到树上。用 `UncontrolledProviderScope`
    // 而不是 `ProviderScope`：生命周期不归 Widget 管，组合根还要在树之外读切片状态
    // （见 `ZetaAppComposition.takeStateSnapshot`）。
    return UncontrolledProviderScope(
      container: _composition.container,
      child: _buildApp(context),
    );
  }

  Widget _buildApp(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => _buildThemedApp(
        appearanceSettingsFromSlice(ref.watch(appearanceSettingsValueProvider)),
      ),
    );
  }

  Widget _buildThemedApp(AppearanceSettings settings) {
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
    return TickerMode(
      enabled: _tickersEnabled,
      // 设计系统自有文案（无障碍标签、滚动条提示等）不经 generated l10n，
      // 由组合层在这里注入一次；未注入时 zeta_ui 回退英文。
      child: IdeUiTextScope(
        catalog: _composition.zetaUiTextCatalog,
        child: IdeThemeScope(
          themeMode: flutterThemeMode,
          lightTheme: lightIdeTheme,
          darkTheme: darkIdeTheme,
          child: sf.ShadcnApp(
            debugShowCheckedModeBanner: false,
            title: appTitle,
            locale: _composition.frozenDisplayLocale,
            supportedLocales: ZetaLocalization.supportedLocales,
            localizationsDelegates: ZetaLocalization.delegates,
            theme: buildShadcnTheme(lightIdeTheme),
            darkTheme: buildShadcnTheme(darkIdeTheme),
            themeMode: resolveShadcnThemeMode(flutterThemeMode),
            // 0.0.54 起 ShadcnApp 不再安装 Material 祖先，改由这一层补齐。
            builder: (context, child) => IdeMaterialLayer(
              theme: buildMaterialTheme(materialIdeTheme),
              child: child,
            ),
            home: _composition.isReady
                ? _buildHome()
                : ColoredBox(
                    key: const ValueKey<String>('zeta.localization-loading'),
                    color: materialIdeTheme.colors.frame,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildHome() {
    final composition = _composition;
    // 这一支只在语言冻结之后走到（见 build 里的 isReady 分支），因此 `IdeHome`
    // 自己从容器读文本目录与插件链上的 provider 时都已经有值。
    //
    // 这里只补**容器里还没有的东西**：组合根手工持有的三个切片组合、状态快照桥
    // 与工作台工厂。凡是已经装进 Riverpod 的依赖一律不经这里下钻——那只是把
    // `container.read` 换个地方写，还会让 `IdeHome` 的构造函数继续膨胀。
    return IdeHome(
      key: const ValueKey<String>('zeta.ide-home'),
      shellStateSnapshotRelay: composition.shellStateSnapshotRelay,
      desktopAttentionSliceComposition: composition.desktopAttentionComposition,
      desktopAttentionTargetActivatorRelay:
          composition.desktopAttentionTargetActivatorRelay,
      activeModelCatalogLoader: () =>
          composition.providerSettingsComposition.loadActiveModelCatalog(),
      usageStatisticsSliceComposition: composition.usageStatisticsComposition,
      workbenchCompositionFactory: composition.createWorkbenchComposition,
      providerMetricLabel: AgentMetricLabels.forProviderId,
    );
  }

  bool get _tickersEnabled {
    final state = _appLifecycleState;
    final lifecycleAllowsTickers =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    return lifecycleAllowsTickers && !_nativeWindowSuspended;
  }

  void _resumeNativeWindowTickers() {
    // Windows 从“最小化前为最大化/全屏”恢复时，平台事件
    // 可能是 maximize/enter-full-screen 而不是 restore。
    _setNativeWindowSuspended(false);
  }

  void _setNativeWindowSuspended(bool suspended) {
    if (_nativeWindowSuspended == suspended || !mounted) {
      return;
    }
    setState(() => _nativeWindowSuspended = suspended);
  }
}
