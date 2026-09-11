import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_notifier.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// Phase 3 第 1 批步骤 4：general 面板改走切片。
///
/// 这里证明面板确实从唯一 slice owner 读取设置。
void main() {
  testWidgets('general 面板从唯一 slice owner 读取设置', (tester) async {
    final container = _container(
      const GeneralSettings(sendMessageShortcut: MessageSendShortcut.enter),
    );
    final store = container.read(generalSettingsSliceProvider.notifier);
    await _pumpPane(tester, container: container);
    expect(find.textContaining('按 Enter 发送消息'), findsOneWidget);

    // 直接推动唯一 owner。
    store.setMessageSendShortcut(MessageSendShortcut.primaryModifierEnter);
    store.persisted(store.state.pendingOperationId!, store.state.pendingValue!);
    // 切片把同一 microtask 内的多次提交合并成一次广播，先让它落地再验帧。
    await tester.pumpAndSettle();

    // 界面确实跟着切片走——这条才能区分"真的接上了"和"看起来接上了"。
    expect(find.textContaining('Enter 发送消息，按 Enter 换行'), findsOneWidget);
    expect(
      store.state.settings.sendMessageShortcut,
      MessageSendShortcut.primaryModifierEnter,
    );
  });
}

/// 切片状态由容器拥有；初值经 runner 的 `loaded` 回流，与生产同一条路径。
ProviderContainer _container(GeneralSettings initial) {
  final container = ProviderContainer(
    overrides: <Override>[
      generalSettingsSliceEffectRunnerFactoryProvider.overrideWithValue(
        (_) => _NoopRunner(),
      ),
      generalSettingsSliceProvider.overrideWith(
        () => GeneralSettingsSliceNotifier(initiallyLoaded: true),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(generalSettingsSliceProvider.notifier).loaded(initial);
  return container;
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
