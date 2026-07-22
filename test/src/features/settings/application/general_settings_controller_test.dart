import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
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
}
