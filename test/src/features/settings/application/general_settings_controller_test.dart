import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_update_result.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

void main() {
  test('loads persisted general settings', () async {
    final controller = GeneralSettingsController(
      store: MemoryGeneralSettingsStore(
        const GeneralSettings(
          sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
        ),
      ),
    );
    addTearDown(controller.dispose);

    expect(
      await controller.load(),
      const GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
      ),
    );
  });

  test('updates, persists and notifies the send shortcut', () async {
    final store = MemoryGeneralSettingsStore();
    final controller = GeneralSettingsController(store: store);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    await controller.setMessageSendShortcut(
      MessageSendShortcut.primaryModifierEnter,
    );

    const expected = GeneralSettings(
      sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
    );
    expect(controller.settings, expected);
    expect(await store.load(), expected);
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('updates and persists notification switches', () async {
    final store = MemoryGeneralSettingsStore();
    final controller = GeneralSettingsController(store: store);
    addTearDown(controller.dispose);

    await controller.setTurnTerminalNotificationsEnabled(false);
    await controller.setActionRequiredNotificationsEnabled(false);
    await controller.setNotificationsEnabled(false);

    const expected = GeneralSettings(
      notifications: AgentNotificationSettings(
        enabled: false,
        turnTerminalEnabled: false,
        actionRequiredEnabled: false,
      ),
    );
    expect(controller.settings, expected);
    expect(await store.load(), expected);
  });

  test('setAppLanguage is persist-first and reports failure', () async {
    final store = _ControllableGeneralSettingsStore();
    final controller = GeneralSettingsController(store: store);
    addTearDown(controller.dispose);

    store.failSaves = true;
    expect(
      await controller.setAppLanguage(AppLanguage.english),
      GeneralSettingsUpdateResult.persistenceFailed,
    );
    expect(controller.settings.appLanguage, AppLanguage.simplifiedChinese);

    store.failSaves = false;
    expect(
      await controller.setAppLanguage(AppLanguage.english),
      GeneralSettingsUpdateResult.applied,
    );
    expect(controller.settings.appLanguage, AppLanguage.english);
    expect(
      await controller.setAppLanguage(AppLanguage.english),
      GeneralSettingsUpdateResult.unchanged,
    );
  });

  test('serializes language, notification and shortcut writes', () async {
    final store = _ControllableGeneralSettingsStore(delaySaves: true);
    final controller = GeneralSettingsController(store: store);
    addTearDown(controller.dispose);

    final first = controller.setAppLanguage(AppLanguage.english);
    final second = controller.setNotificationsEnabled(false);
    final third = controller.setMessageSendShortcut(
      MessageSendShortcut.primaryModifierEnter,
    );
    await Future.wait(<Future<void>>[first, second, third]);

    expect(
      controller.settings,
      const GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
        notifications: AgentNotificationSettings(enabled: false),
        appLanguage: AppLanguage.english,
      ),
    );
    expect(await store.load(), controller.settings);
    expect(store.savedSnapshots, hasLength(3));
    expect(store.savedSnapshots.last, controller.settings);
  });
}

class _ControllableGeneralSettingsStore implements GeneralSettingsStore {
  _ControllableGeneralSettingsStore({this.delaySaves = false});

  var failSaves = false;
  final bool delaySaves;
  GeneralSettings _settings = const GeneralSettings();
  final savedSnapshots = <GeneralSettings>[];

  @override
  Future<GeneralSettings> load() async => _settings;

  @override
  Future<void> save(GeneralSettings settings) async {
    if (delaySaves) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (failSaves) {
      throw StateError('save failed');
    }
    _settings = settings;
    savedSnapshots.add(settings);
  }
}
