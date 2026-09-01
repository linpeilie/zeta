import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// Phase 3 第 1 批步骤 4：general 面板改走切片。
///
/// 这里证明面板确实从唯一 slice owner 读取设置。
void main() {
  testWidgets('general 面板从唯一 slice owner 读取设置', (tester) async {
    final store = _store(
      const GeneralSettings(sendMessageShortcut: MessageSendShortcut.enter),
    );
    addTearDown(store.close);
    await _pumpPane(tester, store: store);
    expect(find.textContaining('按 Enter 发送消息'), findsOneWidget);

    // 直接推动唯一 owner。
    store.setMessageSendShortcut(MessageSendShortcut.primaryModifierEnter);
    store.persisted(store.state.pendingOperationId!, store.state.pendingValue!);
    await tester.pump();

    // 界面确实跟着切片走——这条才能区分"真的接上了"和"看起来接上了"。
    expect(find.textContaining('Enter 发送消息，按 Enter 换行'), findsOneWidget);
    expect(
      store.state.settings.sendMessageShortcut,
      MessageSendShortcut.primaryModifierEnter,
    );
  });
}

GeneralSettingsSliceStore _store(GeneralSettings initial) {
  return GeneralSettingsSliceStore(
    initialState: GeneralSettingsSliceState(settings: initial),
    effectRunnerFactory: (_) => _NoopRunner(),
  );
}

Future<void> _pumpPane(
  WidgetTester tester, {
  required GeneralSettingsSliceStore store,
}) async {
  final ideTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'CodeFont',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [generalSettingsSliceStoreProvider.overrideWithValue(store)],
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
              activeSection: SettingsSection.general,
              onSectionSelected: (_) {},
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
