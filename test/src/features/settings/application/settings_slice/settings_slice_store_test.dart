import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 记录 effect 并按测试意图手动回执的假 runner。
final class _RecordingAppearanceRunner
    implements AppearanceSettingsSliceEffectRunner {
  final List<AppearanceSettingsSliceEffect> effects =
      <AppearanceSettingsSliceEffect>[];

  @override
  void run(AppearanceSettingsSliceEffect effect) => effects.add(effect);
}

final class _RecordingGeneralRunner
    implements GeneralSettingsSliceEffectRunner {
  final List<GeneralSettingsSliceEffect> effects =
      <GeneralSettingsSliceEffect>[];

  @override
  void run(GeneralSettingsSliceEffect effect) => effects.add(effect);
}

void main() {
  group('appearance store', () {
    test('状态未变不发布；变化才通知订阅者', () {
      final runner = _RecordingAppearanceRunner();
      final store = AppearanceSettingsSliceStore(
        initialState: const AppearanceSettingsSliceState(),
        effectRunner: runner,
      );
      var notifications = 0;
      store.subscribe(() => notifications += 1);

      store.selectThemeMode(ZetaThemeModePreference.dark);
      expect(notifications, 1);

      // 相等选择：reducer 无转移，不发布。
      store.selectThemeMode(ZetaThemeModePreference.dark);
      expect(notifications, 1);

      expect(store.diagnostics.publishCount, 1);
      expect(store.diagnostics.effectCount, 1);
    });

    test('load 幂等：重复调用只发起一次', () {
      final runner = _RecordingAppearanceRunner();
      final store = AppearanceSettingsSliceStore(
        initialState: const AppearanceSettingsSliceState(),
        effectRunner: runner,
      );

      store.load();
      store.load();

      expect(
        runner.effects.whereType<AppearanceSettingsLoadEffect>().length,
        1,
      );
    });

    test('迟到解析结果计入 staleResultCount', () {
      final runner = _RecordingAppearanceRunner();
      final store = AppearanceSettingsSliceStore(
        initialState: const AppearanceSettingsSliceState(),
        effectRunner: runner,
      );

      final first = store.selectUiFontChoice(
        const AppearanceFontChoice.system('MyFont'),
      );
      // 第二次选择取代第一次的在途身份。
      store.selectUiFontChoice(const AppearanceFontChoice.system('MyFont2'));
      // 第一次的解析结果迟到回流。
      store.fontChoiceRejected(first);

      expect(store.diagnostics.staleResultCount, 1);
      expect(store.state.pendingUiFontChoiceOperationId, isNotNull);
    });

    test('close 后拒绝一切写入并摘掉监听', () {
      final runner = _RecordingAppearanceRunner();
      final store = AppearanceSettingsSliceStore(
        initialState: const AppearanceSettingsSliceState(),
        effectRunner: runner,
      );
      var notifications = 0;
      store.subscribe(() => notifications += 1);

      store.close();
      store.selectThemeMode(ZetaThemeModePreference.dark);

      expect(store.isClosed, isTrue);
      expect(notifications, 0);
      expect(runner.effects, isEmpty);
    });
  });

  group('general store', () {
    test('persist-first：提交不改变已应用值，回执才应用', () {
      final runner = _RecordingGeneralRunner();
      final store = GeneralSettingsSliceStore(
        initialState: const GeneralSettingsSliceState(),
        effectRunner: runner,
      );

      final id = store.setAppLanguage(AppLanguage.english);
      expect(store.state.settings.appLanguage, AppLanguage.simplifiedChinese);

      final effect = runner.effects
          .whereType<GeneralSettingsPersistEffect>()
          .single;
      store.persisted(id, effect.value);

      expect(store.state.settings.appLanguage, AppLanguage.english);
      expect(store.state.pendingOperationId, isNull);
    });

    test('迟到 persist 回执丢弃并计数', () {
      final runner = _RecordingGeneralRunner();
      final store = GeneralSettingsSliceStore(
        initialState: const GeneralSettingsSliceState(),
        effectRunner: runner,
      );

      final first = store.setAppLanguage(AppLanguage.english);
      final queued = store.setMessageSendShortcut(
        MessageSendShortcut.primaryModifierEnter,
      );
      store.persistFailed(queued, SettingsPersistFailureKind.persistence);

      // 队列中的第二次尚未提交，用其 id 回执必然是迟到结果。
      expect(store.state.lastPersistFailure, isNull);
      expect(store.diagnostics.staleResultCount, 1);
      expect(store.state.pendingOperationId, first);
    });

    test('首次 load 结算前命令排队，并从持久化快照计算', () {
      final runner = _RecordingGeneralRunner();
      final store = GeneralSettingsSliceStore(
        initialState: const GeneralSettingsSliceState(),
        effectRunner: runner,
        initiallyLoaded: false,
      );

      store.load();
      final language = store.setAppLanguage(AppLanguage.english);

      expect(
        runner.effects.whereType<GeneralSettingsLoadEffect>(),
        hasLength(1),
      );
      expect(runner.effects.whereType<GeneralSettingsPersistEffect>(), isEmpty);

      const persisted = GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
        notifications: AgentNotificationSettings(enabled: false),
      );
      store.loaded(persisted);

      final effect = runner.effects
          .whereType<GeneralSettingsPersistEffect>()
          .single;
      expect(effect.operationId, language);
      expect(
        effect.value,
        const GeneralSettings(
          sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
          notifications: AgentNotificationSettings(enabled: false),
          appLanguage: AppLanguage.english,
        ),
      );
    });

    test('前一次失败后，后一次成功不夹带失败修改', () {
      final runner = _RecordingGeneralRunner();
      final store = GeneralSettingsSliceStore(
        initialState: const GeneralSettingsSliceState(),
        effectRunner: runner,
      );

      final language = store.setAppLanguage(AppLanguage.english);
      final shortcut = store.setMessageSendShortcut(
        MessageSendShortcut.primaryModifierEnter,
      );
      expect(
        runner.effects.whereType<GeneralSettingsPersistEffect>(),
        hasLength(1),
      );

      store.persistFailed(language, SettingsPersistFailureKind.persistence);

      final effects = runner.effects
          .whereType<GeneralSettingsPersistEffect>()
          .toList();
      expect(effects, hasLength(2));
      expect(effects.last.operationId, shortcut);
      expect(effects.last.value.appLanguage, AppLanguage.simplifiedChinese);
      expect(
        effects.last.value.sendMessageShortcut,
        MessageSendShortcut.primaryModifierEnter,
      );
      expect(
        store.state.lastPersistFailure,
        const GeneralSettingsSlicePersistFailure(
          kind: SettingsPersistFailureKind.persistence,
          operation: GeneralSettingsPersistOperation.language,
        ),
        reason: '失败必须先成为可观察状态，不能因后续 operationId 被吞掉',
      );

      store.persisted(shortcut, effects.last.value);

      expect(store.state.settings.appLanguage, AppLanguage.simplifiedChinese);
      expect(
        store.state.settings.sendMessageShortcut,
        MessageSendShortcut.primaryModifierEnter,
      );
    });

    test('OperationId 作用域是常量、序号单调', () {
      final runner = _RecordingGeneralRunner();
      final store = GeneralSettingsSliceStore(
        initialState: const GeneralSettingsSliceState(),
        effectRunner: runner,
      );

      final first = store.setAppLanguage(AppLanguage.english);
      final second = store.setAppLanguage(AppLanguage.english);

      expect(first.scope, SettingsOperationScopes.generalPersist);
      expect(second.sequence, greaterThan(first.sequence));
    });
  });
}
