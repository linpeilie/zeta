import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// Phase 3 第 1 批步骤 4：general 面板改走切片。
///
/// 这里只证明**面板确实从切片读、往切片写**——渲染细节由既有的
/// `ide_settings_widget_test` 覆盖，两条路径共用同一份 body，不重复断言。
void main() {
  testWidgets('切片开启时，general 面板从切片读取设置', (tester) async {
    final store = _store(
      const GeneralSettings(sendMessageShortcut: MessageSendShortcut.enter),
    );
    addTearDown(store.close);
    final controller = _controller();
    addTearDown(controller.dispose);

    await _pumpPane(tester, controller: controller, store: store);
    expect(find.textContaining('按 Enter 发送消息'), findsOneWidget);

    // 只往切片推、完全不碰旧 controller：走旧路径的话界面不会变。
    store.setMessageSendShortcut(MessageSendShortcut.primaryModifierEnter);
    store.persisted(store.state.pendingOperationId!, store.state.pendingValue!);
    await tester.pump();

    // 界面确实跟着切片走——这条才能区分"真的接上了"和"看起来接上了"。
    expect(find.textContaining('Enter 发送消息，按 Enter 换行'), findsOneWidget);
    expect(
      store.state.settings.sendMessageShortcut,
      MessageSendShortcut.primaryModifierEnter,
    );
    expect(
      controller.listenable.value.sendMessageShortcut,
      MessageSendShortcut.enter,
      reason: '切片路径不得回头去写旧 controller，否则就是双写',
    );
  });

  testWidgets('切片关闭时回退旧路径，仍然渲染', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await _pumpPane(tester, controller: controller, store: null);

    expect(find.byKey(const ValueKey('settings-language-row')), findsOneWidget);
  });
}

GeneralSettingsSliceStore _store(GeneralSettings initial) {
  return GeneralSettingsSliceStore(
    initialState: GeneralSettingsSliceState(settings: initial),
    effectRunner: _NoopRunner(),
  );
}

GeneralSettingsController _controller() {
  return GeneralSettingsController(
    store: MemoryGeneralSettingsStore(const GeneralSettings()),
  );
}

Future<void> _pumpPane(
  WidgetTester tester, {
  required GeneralSettingsController controller,
  required GeneralSettingsSliceStore? store,
}) async {
  final ideTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'CodeFont',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (store != null)
          generalSettingsSliceStoreProvider.overrideWithValue(store),
      ],
      child: IdeThemeScope(
        themeMode: ThemeMode.light,
        lightTheme: ideTheme,
        darkTheme: ideTheme,
        child: sf.ShadcnApp(
          locale: ZetaLocalization.simplifiedChinese,
          supportedLocales: ZetaLocalization.supportedLocales,
          localizationsDelegates: ZetaLocalization.delegates,
          theme: buildShadcnTheme(ideTheme),
          materialTheme: buildMaterialTheme(ideTheme),
          home: sf.Scaffold(
            child: SettingsPage(
              activeSection: SettingsSection.general,
              onSectionSelected: (_) {},
              generalSettingsController: controller,
              appearanceController: AppearanceSettingsController(
                store: MemoryAppearanceSettingsStore(),
                fontCatalog: const _StubFontCatalog(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _NoopRunner implements GeneralSettingsSliceEffectRunner {
  @override
  void run(GeneralSettingsSliceEffect effect) {}
}

/// 外观面板这批还没迁；这里只需要它能构造出来。
final class _StubFontCatalog implements SystemFontCatalogService {
  const _StubFontCatalog();

  @override
  Future<List<SystemFontFamily>> uiFontFamilies() async =>
      const <SystemFontFamily>[];

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() async =>
      const <SystemFontFamily>[];

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async => null;
}
