import 'package:shared_preferences/shared_preferences.dart';

import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';

const String sessionStorageKey = 'zeta.ide.session.v1';

abstract class IdeSessionStore {
  Future<IdeSessionState?> load();

  Future<void> save(IdeSessionState state);
}

class SharedPreferencesIdeSessionStore implements IdeSessionStore {
  SharedPreferencesIdeSessionStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<IdeSessionState?> load() async {
    final value = await _preferences.getString(sessionStorageKey);
    return IdeSessionState.tryDecode(value);
  }

  @override
  Future<void> save(IdeSessionState state) async {
    await _preferences.setString(sessionStorageKey, state.encode());
  }
}

class CallbackIdeSessionStore implements IdeSessionStore {
  const CallbackIdeSessionStore({
    required this.loadJson,
    required this.saveJson,
  });

  final Future<String?> Function() loadJson;
  final Future<void> Function(String value) saveJson;

  @override
  Future<IdeSessionState?> load() async {
    return IdeSessionState.tryDecode(await loadJson());
  }

  @override
  Future<void> save(IdeSessionState state) {
    return saveJson(state.encode());
  }
}
