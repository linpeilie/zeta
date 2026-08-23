import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_intent.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_reducer.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

OperationId _id(int sequence) => OperationId(
  scope: SettingsOperationScopes.generalPersist,
  sequence: sequence,
);

void main() {
  group('general reducer · persist-first（现状语义 B）', () {
    test('选择语言只登记在途，已应用值不变', () {
      final transition = generalSettingsSliceReduce(
        const GeneralSettingsSliceState(),
        AppLanguageSelected(_id(1), AppLanguage.english),
      );

      // 默认是简体中文：persist 成功前不得变更。
      expect(
        transition.state.settings.appLanguage,
        AppLanguage.simplifiedChinese,
      );
      expect(transition.state.pendingOperationId, _id(1));
      expect(transition.state.pendingValue?.appLanguage, AppLanguage.english);

      final effect = transition.effects.single;
      expect(effect, isA<GeneralSettingsPersistEffect>());
      expect(
        (effect as GeneralSettingsPersistEffect).value.appLanguage,
        AppLanguage.english,
      );
    });

    test('persist 成功回执才应用并清空在途', () {
      final submitted = generalSettingsSliceReduce(
        const GeneralSettingsSliceState(),
        AppLanguageSelected(_id(1), AppLanguage.english),
      ).state;
      final submittedValue = submitted.pendingValue!;

      final transition = generalSettingsSliceReduce(
        submitted,
        GeneralSettingsPersisted(_id(1), submittedValue),
      );

      expect(transition.state.settings, submittedValue);
      expect(transition.state.pendingOperationId, isNull);
      expect(transition.state.pendingValue, isNull);
      expect(transition.effects, isEmpty);
    });

    test('persist 失败：保持旧值、登记失败分类、确认后清除', () {
      final submitted = generalSettingsSliceReduce(
        const GeneralSettingsSliceState(),
        AppLanguageSelected(_id(1), AppLanguage.english),
      ).state;

      var state = generalSettingsSliceReduce(
        submitted,
        GeneralSettingsPersistFailed(
          _id(1),
          SettingsPersistFailureKind.persistence,
        ),
      ).state;
      expect(state.settings.appLanguage, AppLanguage.simplifiedChinese);
      expect(state.pendingOperationId, isNull);
      expect(
        state.lastPersistFailure,
        const GeneralSettingsSlicePersistFailure(
          kind: SettingsPersistFailureKind.persistence,
          operation: GeneralSettingsPersistOperation.language,
        ),
      );

      state = generalSettingsSliceReduce(
        state,
        const GeneralSettingsFailureAcknowledged(),
      ).state;
      expect(state.lastPersistFailure, isNull);
    });

    test('相等选择早退（对齐语言路径的 unchanged 分支）', () {
      final transition = generalSettingsSliceReduce(
        const GeneralSettingsSliceState(),
        AppLanguageSelected(_id(1), AppLanguage.simplifiedChinese),
      );

      expect(transition.state, const GeneralSettingsSliceState());
      expect(transition.effects, isEmpty);
    });

    test('通知开关相等时不提交', () {
      final transition = generalSettingsSliceReduce(
        const GeneralSettingsSliceState(),
        NotificationsEnabledToggled(_id(1), true),
      );

      expect(transition.state, const GeneralSettingsSliceState());
      expect(transition.effects, isEmpty);
    });
  });

  group('general reducer · pending 串行链', () {
    test('第二次修改基于在途值计算，不丢第一次的改动', () {
      var state = generalSettingsSliceReduce(
        const GeneralSettingsSliceState(),
        AppLanguageSelected(_id(1), AppLanguage.english),
      ).state;
      state = generalSettingsSliceReduce(
        state,
        MessageSendShortcutSelected(
          _id(2),
          MessageSendShortcut.primaryModifierEnter,
        ),
      ).state;

      // 第二次提交的完整值同时包含语言与快捷键。
      expect(state.pendingValue?.appLanguage, AppLanguage.english);
      expect(
        state.pendingValue?.sendMessageShortcut,
        MessageSendShortcut.primaryModifierEnter,
      );
      expect(state.pendingOperationId, _id(2));
    });

    test('被取代的回执按迟到丢弃，最终应用链上完整值', () {
      var state = generalSettingsSliceReduce(
        const GeneralSettingsSliceState(),
        AppLanguageSelected(_id(1), AppLanguage.english),
      ).state;
      final firstValue = state.pendingValue!;
      state = generalSettingsSliceReduce(
        state,
        MessageSendShortcutSelected(
          _id(2),
          MessageSendShortcut.primaryModifierEnter,
        ),
      ).state;

      // 第一次的回执先回来：在途已是第二次 → 丢弃。
      final stale = generalSettingsSliceReduce(
        state,
        GeneralSettingsPersisted(_id(1), firstValue),
      );
      expect(stale.state, state);
      expect(stale.effects, isEmpty);

      // 第二次回执应用链上完整值（含两次修改）。
      final finalTransition = generalSettingsSliceReduce(
        state,
        GeneralSettingsPersisted(_id(2), state.pendingValue!),
      );
      expect(finalTransition.state.settings.appLanguage, AppLanguage.english);
      expect(
        finalTransition.state.settings.sendMessageShortcut,
        MessageSendShortcut.primaryModifierEnter,
      );
    });
  });

  group('general reducer · 载入', () {
    test('载入完成应用；相同值无变化', () {
      const settings = GeneralSettings(appLanguage: AppLanguage.english);
      final transition = generalSettingsSliceReduce(
        const GeneralSettingsSliceState(),
        const GeneralSettingsLoaded(settings),
      );
      expect(transition.state.settings, settings);

      final again = generalSettingsSliceReduce(
        transition.state,
        const GeneralSettingsLoaded(settings),
      );
      expect(again.state, transition.state);
    });
  });
}
