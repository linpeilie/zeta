import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_overrides.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';
import 'package:zeta/src/features/settings/domain/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta_ui/zeta_ui.dart';

import '../../../testing/memory_feature_stores.dart';

void main() {
  testWidgets('面板从唯一 Notifier owner 读取', (tester) async {
    final container = _container();
    addTearDown(container.dispose);

    await _pumpPane(tester, container: container);
    final sizeText = find.byKey(
      const ValueKey<String>('settings-ui-font-size-value'),
    );
    expect(sizeText, findsOneWidget);
    final before = tester.widget<Text>(sizeText).data;

    await container.read(appearanceSettingsProvider.notifier).setUiFontSize(18);
    await tester.pump();

    expect(tester.widget<Text>(sizeText).data, isNot(before));
    expect(tester.widget<Text>(sizeText).data, contains('18'));
    expect(
      container.read(appearanceSettingsValueProvider).themeMode,
      ZetaThemeModePreference.system,
    );
  });

  testWidgets('字体目录只请求一次，重建不重复加载', (tester) async {
    final container = _container();
    addTearDown(container.dispose);

    await _pumpPane(tester, container: container);
    for (var i = 0; i < 3; i += 1) {
      await container
          .read(appearanceSettingsProvider.notifier)
          .setUiFontSize(13 + i.toDouble());
      await tester.pump();
    }

    expect(
      container.read(appearanceSettingsProvider).catalog.uiOptions,
      isNull,
      reason: '没人打开下拉时不该请求字体目录',
    );
  });

  testWidgets('字体选择被拒绝时不应用候选值', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpPane(tester, container: container);

    const choice = AppearanceFontChoice.system('Broken UI');
    final applied = await container
        .read(appearanceSettingsProvider.notifier)
        .setUiFontChoice(choice);
    await tester.pump();

    expect(applied, isFalse);
    expect(
      container.read(appearanceSettingsValueProvider).uiFontChoice,
      isNot(choice),
      reason: '被拒绝要回滚到原值，面板据此弹错误 toast',
    );
  });
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      ...settingsSliceOverrides(),
      appearanceSettingsRepositoryProvider.overrideWithValue(
        MemoryAppearanceSettingsStore(),
      ),
      appearanceFontCatalogProvider.overrideWithValue(
        const _EmptyFontCatalog(),
      ),
    ],
  );
}

Future<void> _pumpPane(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  final ideTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'CodeFont',
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: IdeThemeScope(
        themeMode: ThemeMode.light,
        lightTheme: ideTheme,
        darkTheme: ideTheme,
        child: sf.ShadcnApp(
          locale: ZetaLocalization.simplifiedChinese,
          supportedLocales: ZetaLocalization.supportedLocales,
          localizationsDelegates: ZetaLocalization.delegates,
          theme: buildShadcnTheme(ideTheme),
          builder: (context, child) => IdeMaterialLayer(
            theme: buildMaterialTheme(ideTheme),
            child: child,
          ),
          home: sf.Scaffold(
            child: SettingsPage(
              activeSection: SettingsSection.appearance,
              onSectionSelected: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _EmptyFontCatalog implements SystemFontCatalogService {
  const _EmptyFontCatalog();

  @override
  Future<List<SystemFontFamily>> uiFontFamilies() async =>
      const <SystemFontFamily>[];

  @override
  Future<List<SystemFontFamily>> codeFontFamilies() async =>
      const <SystemFontFamily>[];

  @override
  Future<SystemFontFamily?> resolveFontFamily(String name) async => null;
}
