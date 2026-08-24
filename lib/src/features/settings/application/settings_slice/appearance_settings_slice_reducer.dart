import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_intent.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// appearance 切片的 reducer。
///
/// **纯同步、无副作用**（G3）：不碰时钟、不查字体目录、不铸造 id、不做 IO。
/// 字号取整与夹取是纯函数；系统字体的异步解析被建模为 effect + result intent，
/// 由 runner 回流。状态语义保持 Phase 3 前的 appearance 行为：
///
/// - 主题 / 字号：乐观应用（语义 A），persist 失败不回滚；
/// - 字体：先解析后应用（现状如此——解析失败既不应用也不落盘）；
/// - 相等早退：与现状一致，不产生 effect。
Transition<AppearanceSettingsSliceState, AppearanceSettingsSliceEffect>
appearanceSettingsSliceReduce(
  AppearanceSettingsSliceState state,
  AppearanceSettingsSliceIntent intent,
) {
  switch (intent) {
    case AppearanceSettingsLoadRequested():
      return Transition(state, const <AppearanceSettingsSliceEffect>[
        AppearanceSettingsLoadEffect(),
      ]);

    case AppearanceSettingsLoaded():
      if (intent.value == state.value) {
        return Transition.none(state);
      }
      return Transition.stateOnly(state.copyWith(value: intent.value));

    case AppearanceThemeModeSelected():
      if (state.value.themeMode == intent.mode) {
        return Transition.none(state);
      }
      return _applyOptimistically(
        state,
        intent.operationId,
        state.value.copyWith(themeMode: intent.mode),
      );

    case AppearanceUiFontSizeAdjusted():
      final normalized = normalizeSettingsFontSize(
        intent.value,
        min: minUiFontSize,
        max: maxUiFontSize,
      );
      if (normalized == null || normalized == state.value.uiFontSize) {
        return Transition.none(state);
      }
      return _applyOptimistically(
        state,
        intent.operationId,
        state.value.copyWith(uiFontSize: normalized),
      );

    case AppearanceCodeFontSizeAdjusted():
      final normalized = normalizeSettingsFontSize(
        intent.value,
        min: minCodeFontSize,
        max: maxCodeFontSize,
      );
      if (normalized == null || normalized == state.value.codeFontSize) {
        return Transition.none(state);
      }
      return _applyOptimistically(
        state,
        intent.operationId,
        state.value.copyWith(codeFontSize: normalized),
      );

    case AppearanceUiFontChoiceSelected():
      if (state.value.uiFontChoice == intent.choice) {
        return Transition.none(state);
      }
      return Transition(
        state.copyWith(pendingUiFontChoiceOperationId: intent.operationId),
        <AppearanceSettingsSliceEffect>[
          AppearanceFontChoiceResolveEffect(
            operationId: intent.operationId,
            forCodeFont: false,
            choice: intent.choice,
          ),
        ],
      );

    case AppearanceCodeFontChoiceSelected():
      if (state.value.codeFontChoice == intent.choice) {
        return Transition.none(state);
      }
      return Transition(
        state.copyWith(pendingCodeFontChoiceOperationId: intent.operationId),
        <AppearanceSettingsSliceEffect>[
          AppearanceFontChoiceResolveEffect(
            operationId: intent.operationId,
            forCodeFont: true,
            choice: intent.choice,
          ),
        ],
      );

    case AppearanceFontChoiceResolved():
      final pending = intent.forCodeFont
          ? state.pendingCodeFontChoiceOperationId
          : state.pendingUiFontChoiceOperationId;
      if (pending != intent.operationId) {
        return Transition.none(state);
      }
      final nextValue = intent.forCodeFont
          ? state.value.copyWith(codeFontChoice: intent.resolved)
          : state.value.copyWith(uiFontChoice: intent.resolved);
      final nextState = intent.forCodeFont
          ? state.copyWith(
              value: nextValue,
              pendingCodeFontChoiceOperationId: null,
            )
          : state.copyWith(
              value: nextValue,
              pendingUiFontChoiceOperationId: null,
            );
      // 解析成功即应用并持久化（语义 A）。
      return Transition(nextState, <AppearanceSettingsSliceEffect>[
        AppearanceSettingsPersistEffect(
          operationId: intent.operationId,
          previousValue: state.value,
          value: nextValue,
        ),
      ]);

    case AppearanceFontChoiceRejected():
      // 对不上任一槽位的在途身份即为迟到；匹配则只清 pending，不应用值。
      if (state.pendingUiFontChoiceOperationId == intent.operationId) {
        return Transition.stateOnly(
          state.copyWith(pendingUiFontChoiceOperationId: null),
        );
      }
      if (state.pendingCodeFontChoiceOperationId == intent.operationId) {
        return Transition.stateOnly(
          state.copyWith(pendingCodeFontChoiceOperationId: null),
        );
      }
      return Transition.none(state);

    case AppearanceFontCatalogRequested():
      return Transition(state, <AppearanceSettingsSliceEffect>[
        AppearanceFontCatalogLoadEffect(forCodeFont: intent.forCodeFont),
      ]);

    case AppearanceFontCatalogLoaded():
      final nextCatalog = intent.forCodeFont
          ? state.catalog.copyWith(codeOptions: intent.options)
          : state.catalog.copyWith(uiOptions: intent.options);
      final mergedDisplayNames = <String, String>{...nextCatalog.displayNames}
        ..addAll(intent.displayNames);
      return Transition.stateOnly(
        state.copyWith(
          catalog: nextCatalog.copyWith(displayNames: mergedDisplayNames),
        ),
      );

    case AppearanceSettingsPersisted():
    case AppearanceSettingsPersistFailed():
      // 语义 A：值在发起时已应用，回执不改变状态。
      return Transition.none(state);
  }
}

Transition<AppearanceSettingsSliceState, AppearanceSettingsSliceEffect>
_applyOptimistically(
  AppearanceSettingsSliceState state,
  OperationId operationId,
  AppearanceSettingsSlice nextValue,
) {
  return Transition(
    state.copyWith(value: nextValue),
    <AppearanceSettingsSliceEffect>[
      AppearanceSettingsPersistEffect(
        operationId: operationId,
        previousValue: state.value,
        value: nextValue,
      ),
    ],
  );
}

/// 字号归一化：四舍五入到整数并夹取到领域范围。
///
/// 与现有 controller 的私有实现逐行为一致：非有限值返回 null（调用方据此
/// 不产生任何转移）。
double? normalizeSettingsFontSize(
  double value, {
  required double min,
  required double max,
}) {
  if (!value.isFinite) {
    return null;
  }
  return value.roundToDouble().clamp(min, max);
}
