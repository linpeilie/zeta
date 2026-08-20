import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:zeta/settings/cubit/settings_state.dart';

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required SettingsRepository settingsRepository,
    required AppLanguage processLanguage,
    required String fontLocaleName,
  }) : _settingsRepository = settingsRepository,
       _processLanguage = processLanguage,
       _fontLocaleName = fontLocaleName,
       super(const SettingsState()) {
    _settingsSubscription = _settingsRepository.settingsChanges.listen(
      _onSnapshot,
    );
  }

  final SettingsRepository _settingsRepository;
  final AppLanguage _processLanguage;
  final String _fontLocaleName;
  late final StreamSubscription<SettingsSnapshot> _settingsSubscription;
  Future<void> _writeQueue = Future<void>.value();
  AppearanceSettings? _pendingAppearance;
  var _appearanceFlushScheduled = false;

  Future<void> load() async {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(status: SettingsStatus.loading, clearFailure: true));
    try {
      await _settingsRepository.ready;
      if (isClosed) {
        return;
      }
      final uiFonts = await _settingsRepository.fontFamilies(
        localeName: _fontLocaleName,
      );
      final codeFonts = await _settingsRepository.fontFamilies(
        localeName: _fontLocaleName,
        monospaceOnly: true,
      );
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: SettingsStatus.ready,
          snapshot: _settingsRepository.settings,
          uiFontOptions: <AppearanceFontOption>[
            const AppearanceFontOption.systemDefault(),
            ...uiFonts.map(AppearanceFontOption.system),
          ],
          codeFontOptions: <AppearanceFontOption>[
            const AppearanceFontOption.bundledJetBrainsMono(),
            ...codeFonts.map(AppearanceFontOption.system),
          ],
          clearFailure: true,
        ),
      );
    } on SettingsRepositoryException catch (error) {
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          failure: error.failure,
        ),
      );
    }
  }

  Future<void> setMessageSendShortcut(MessageSendShortcut shortcut) {
    return _persistGeneral(
      state.general.copyWith(sendMessageShortcut: shortcut),
    );
  }

  Future<void> setNotificationsEnabled({required bool enabled}) {
    return _persistGeneral(
      state.general.copyWith(
        notifications: state.general.notifications.copyWith(enabled: enabled),
      ),
    );
  }

  Future<void> setTurnTerminalNotificationsEnabled({
    required bool enabled,
  }) {
    return _persistGeneral(
      state.general.copyWith(
        notifications: state.general.notifications.copyWith(
          turnTerminalEnabled: enabled,
        ),
      ),
    );
  }

  Future<void> setActionRequiredNotificationsEnabled({
    required bool enabled,
  }) {
    return _persistGeneral(
      state.general.copyWith(
        notifications: state.general.notifications.copyWith(
          actionRequiredEnabled: enabled,
        ),
      ),
    );
  }

  Future<void> setAppLanguage(AppLanguage language) {
    return _persistGeneral(
      state.general.copyWith(appLanguage: language),
      languageRestartRequired: language != _processLanguage,
    );
  }

  void setThemeMode(SettingsThemeMode themeMode) {
    _scheduleAppearance(state.appearance.copyWith(themeMode: themeMode));
  }

  void setUiFontChoice(SettingsFontChoice choice) {
    _scheduleAppearance(state.appearance.copyWith(uiFontChoice: choice));
  }

  void setCodeFontChoice(SettingsFontChoice choice) {
    _scheduleAppearance(state.appearance.copyWith(codeFontChoice: choice));
  }

  void setUiFontSize(double size) {
    _scheduleAppearance(state.appearance.copyWith(uiFontSize: size));
  }

  void setCodeFontSize(double size) {
    _scheduleAppearance(state.appearance.copyWith(codeFontSize: size));
  }

  Future<void> _persistGeneral(
    GeneralSettings value, {
    bool? languageRestartRequired,
  }) {
    return _enqueue(() async {
      if (isClosed) {
        return;
      }
      try {
        final result = await _settingsRepository.persist(
          GeneralSettingsUpdate(value),
        );
        if (isClosed) {
          return;
        }
        emit(
          state.copyWith(
            status: SettingsStatus.ready,
            snapshot: _settingsRepository.settings,
            languageRestartRequired:
                languageRestartRequired ?? state.languageRestartRequired,
            clearFailure: true,
          ),
        );
        if (result == SettingsPersistResult.unchanged &&
            languageRestartRequired != null) {
          emit(
            state.copyWith(
              languageRestartRequired: languageRestartRequired,
            ),
          );
        }
      } on SettingsRepositoryException catch (error) {
        if (isClosed) {
          return;
        }
        emit(
          state.copyWith(
            status: SettingsStatus.failure,
            failure: error.failure,
          ),
        );
      }
    });
  }

  void _scheduleAppearance(AppearanceSettings next) {
    if (isClosed) {
      return;
    }
    _pendingAppearance = next;
    emit(state.copyWith(appearanceDraft: next, clearFailure: true));
    if (_appearanceFlushScheduled) {
      return;
    }
    _appearanceFlushScheduled = true;
    unawaited(
      _enqueue(() async {
        _appearanceFlushScheduled = false;
        final pending = _pendingAppearance;
        if (pending == null || isClosed) {
          return;
        }
        _pendingAppearance = null;
        try {
          await _settingsRepository.persist(AppearanceSettingsUpdate(pending));
          if (isClosed) {
            return;
          }
          emit(
            state.copyWith(
              status: SettingsStatus.ready,
              snapshot: _settingsRepository.settings,
              clearAppearanceDraft: true,
              clearFailure: true,
            ),
          );
        } on SettingsRepositoryException catch (error) {
          if (isClosed) {
            return;
          }
          emit(
            state.copyWith(
              status: SettingsStatus.failure,
              failure: error.failure,
              clearAppearanceDraft: true,
            ),
          );
        }
        final leftover = _pendingAppearance;
        if (leftover != null) {
          _scheduleAppearance(leftover);
        }
      }),
    );
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        await action();
        completer.complete();
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _onSnapshot(SettingsSnapshot snapshot) {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(snapshot: snapshot, status: SettingsStatus.ready));
  }

  @override
  Future<void> close() async {
    await _settingsSubscription.cancel();
    return super.close();
  }
}
