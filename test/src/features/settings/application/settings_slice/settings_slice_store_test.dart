import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_effect.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

final class _RecordingGeneralRunner
    implements GeneralSettingsSliceEffectRunner {
  final List<GeneralSettingsSliceEffect> effects =
      <GeneralSettingsSliceEffect>[];

  @override
  void run(GeneralSettingsSliceEffect effect) => effects.add(effect);
}

void main() {
  group('general store', () {
    test('persist-first：提交不改变已应用值，回执才应用', () {
      final runner = _RecordingGeneralRunner();
      final store = GeneralSettingsSliceStore(
        initialState: const GeneralSettingsSliceState(),
        effectRunnerFactory: (_) => runner,
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
        effectRunnerFactory: (_) => runner,
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
        effectRunnerFactory: (_) => runner,
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
        effectRunnerFactory: (_) => runner,
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
        effectRunnerFactory: (_) => runner,
      );

      final first = store.setAppLanguage(AppLanguage.english);
      final second = store.setAppLanguage(AppLanguage.english);

      expect(first.scope, SettingsOperationScopes.generalPersist);
      expect(second.sequence, greaterThan(first.sequence));
    });
  });
}
