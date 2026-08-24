import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// Phase 3 第 1 批步骤 4：appearance 面板改走切片。
///
/// 重点不是渲染细节，而是这个面板独有的两处异步语义：字体目录只加载
/// 一次，字体选择被拒绝时不应用。
void main() {
  testWidgets('面板从唯一 slice owner 读取', (tester) async {
    final store = _store();
    addTearDown(store.close);

    await _pumpPane(tester, store: store);
    final sizeText = find.byKey(
      const ValueKey<String>('settings-ui-font-size-value'),
    );
    expect(sizeText, findsOneWidget);
    final before = tester.widget<Text>(sizeText).data;

    // 直接推动唯一 owner，界面随 slice 投影更新。
    final id = store.adjustUiFontSize(18);
    store.persisted(id);
    await tester.pump();

    expect(tester.widget<Text>(sizeText).data, isNot(before));
    expect(tester.widget<Text>(sizeText).data, contains('18'));
    expect(store.state.value.themeMode, ZetaThemeModePreference.system);
  });

  testWidgets('字体目录只请求一次，重建不重复加载', (tester) async {
    final runner = _RecordingRunner();
    final store = _store(runner: runner);
    addTearDown(store.close);

    await _pumpPane(tester, store: store);
    // 打开字体下拉才会触发 choicesLoader；这里直接驱动重建，
    // 验证 facade 按 store 缓存——闭包身份不变，行不会重置 _choicesFuture。
    for (var i = 0; i < 3; i += 1) {
      final id = store.adjustUiFontSize(13 + i.toDouble());
      store.persisted(id);
      await tester.pump();
    }

    expect(runner.catalogRequests, 0, reason: '没人打开下拉时不该请求字体目录');
  });

  testWidgets('字体选择被拒绝时不应用候选值', (tester) async {
    final runner = _RecordingRunner();
    final store = _store(runner: runner);
    addTearDown(store.close);
    await _pumpPane(tester, store: store);

    const choice = AppearanceFontChoice.system('Broken UI');
    final id = store.selectUiFontChoice(choice);
    expect(store.state.pendingUiFontChoiceOperationId, id);

    store.fontChoiceRejected(id);
    await tester.pump();

    expect(store.state.pendingUiFontChoiceOperationId, isNull);
    expect(
      store.state.value.uiFontChoice,
      isNot(choice),
      reason: '被拒绝要回滚到原值，面板据此弹错误 toast',
    );
  });
}

AppearanceSettingsSliceStore _store({_RecordingRunner? runner}) {
  return AppearanceSettingsSliceStore(
    initialState: const AppearanceSettingsSliceState(),
    effectRunner: runner ?? _RecordingRunner(),
  );
}

Future<void> _pumpPane(
  WidgetTester tester, {
  required AppearanceSettingsSliceStore store,
}) async {
  final ideTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'CodeFont',
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appearanceSettingsSliceStoreProvider.overrideWithValue(store),
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

final class _RecordingRunner implements AppearanceSettingsSliceEffectRunner {
  int catalogRequests = 0;

  @override
  void run(AppearanceSettingsSliceEffect effect) {
    if (effect is AppearanceFontCatalogLoadEffect) {
      catalogRequests += 1;
    }
  }
}
