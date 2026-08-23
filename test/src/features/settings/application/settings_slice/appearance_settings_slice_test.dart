import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_intent.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_reducer.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

OperationId _id(int sequence, [String scope = 'settings.appearance.persist']) {
  return OperationId(scope: scope, sequence: sequence);
}

void main() {
  group('appearance reducer · 乐观语义（现状语义 A）', () {
    test('主题选择立即应用并产出 persist effect', () {
      final transition = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceThemeModeSelected(_id(1), ZetaThemeModePreference.dark),
      );

      expect(transition.state.value.themeMode, ZetaThemeModePreference.dark);
      final effect = transition.effects.single;
      expect(effect, isA<AppearanceSettingsPersistEffect>());
      expect(
        (effect as AppearanceSettingsPersistEffect).value.themeMode,
        ZetaThemeModePreference.dark,
      );
    });

    test('persist 失败回执不回滚状态', () {
      final applied = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceThemeModeSelected(_id(1), ZetaThemeModePreference.dark),
      ).state;

      final after = appearanceSettingsSliceReduce(
        applied,
        AppearanceSettingsPersistFailed(_id(1)),
      );

      expect(after.state.value.themeMode, ZetaThemeModePreference.dark);
      expect(after.effects, isEmpty);
    });

    test('相等选择早退：无状态变化、无 effect', () {
      final transition = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceThemeModeSelected(_id(1), ZetaThemeModePreference.system),
      );

      expect(transition.state, const AppearanceSettingsSliceState());
      expect(transition.effects, isEmpty);
    });
  });

  group('appearance reducer · 字号归一', () {
    test('四舍五入并夹取到领域范围', () {
      final transition = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceUiFontSizeAdjusted(_id(1), 13.6),
      );
      expect(transition.state.value.uiFontSize, 14);

      final clamped = appearanceSettingsSliceReduce(
        transition.state,
        AppearanceUiFontSizeAdjusted(_id(2), 99),
      );
      expect(clamped.state.value.uiFontSize, maxUiFontSize);
    });

    test('非有限值不产生任何转移', () {
      final transition = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceUiFontSizeAdjusted(_id(1), double.nan),
      );

      expect(transition.state, const AppearanceSettingsSliceState());
      expect(transition.effects, isEmpty);
    });
  });

  group('appearance reducer · 字体选择（先解析后应用）', () {
    const systemChoice = AppearanceFontChoice.system('MyFont');

    test('选择只登记在途身份并产出解析 effect，值不变', () {
      final transition = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceUiFontChoiceSelected(_id(1, 's.f'), systemChoice),
      );

      expect(transition.state.pendingUiFontChoiceOperationId, _id(1, 's.f'));
      expect(
        transition.state.value.uiFontChoice.kind,
        AppearanceFontChoiceKind.systemDefault,
      );
      expect(
        transition.effects.single,
        isA<AppearanceFontChoiceResolveEffect>(),
      );
    });

    test('解析成功才应用并持久化', () {
      const resolved = AppearanceFontChoice.system('MyFont-Resolved');
      final pending = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceUiFontChoiceSelected(_id(1, 's.f'), systemChoice),
      ).state;

      final transition = appearanceSettingsSliceReduce(
        pending,
        AppearanceFontChoiceResolved(
          operationId: _id(1, 's.f'),
          forCodeFont: false,
          resolved: resolved,
        ),
      );

      expect(transition.state.value.uiFontChoice, resolved);
      expect(transition.state.pendingUiFontChoiceOperationId, isNull);
      expect(transition.effects.single, isA<AppearanceSettingsPersistEffect>());
    });

    test('解析被拒绝：清在途、不应用', () {
      final pending = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceUiFontChoiceSelected(_id(1, 's.f'), systemChoice),
      ).state;

      final transition = appearanceSettingsSliceReduce(
        pending,
        AppearanceFontChoiceRejected(_id(1, 's.f')),
      );

      expect(transition.state.pendingUiFontChoiceOperationId, isNull);
      expect(
        transition.state.value.uiFontChoice.kind,
        AppearanceFontChoiceKind.systemDefault,
      );
      expect(transition.effects, isEmpty);
    });

    test('槽位在途身份对不上的结果是迟到：状态不变', () {
      final pending = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceUiFontChoiceSelected(_id(1, 's.f'), systemChoice),
      ).state;

      final stale = appearanceSettingsSliceReduce(
        pending,
        AppearanceFontChoiceResolved(
          operationId: _id(9, 's.f'),
          forCodeFont: false,
          resolved: systemChoice,
        ),
      );

      expect(stale.state, pending);
      expect(stale.effects, isEmpty);
    });

    test('界面 / 代码两个槽位的在途身份互不覆盖', () {
      var state = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        AppearanceUiFontChoiceSelected(_id(1, 's.f'), systemChoice),
      ).state;
      state = appearanceSettingsSliceReduce(
        state,
        AppearanceCodeFontChoiceSelected(_id(2, 's.f'), systemChoice),
      ).state;

      expect(state.pendingUiFontChoiceOperationId, _id(1, 's.f'));
      expect(state.pendingCodeFontChoiceOperationId, _id(2, 's.f'));
    });
  });

  group('appearance reducer · 载入', () {
    test('载入完成应用值；重复应用相同值无变化', () {
      const value = AppearanceSettingsSlice(
        themeMode: ZetaThemeModePreference.light,
      );
      final transition = appearanceSettingsSliceReduce(
        const AppearanceSettingsSliceState(),
        const AppearanceSettingsLoaded(value),
      );
      expect(transition.state.value, value);

      final again = appearanceSettingsSliceReduce(
        transition.state,
        const AppearanceSettingsLoaded(value),
      );
      expect(again.state, transition.state);
    });
  });
}
