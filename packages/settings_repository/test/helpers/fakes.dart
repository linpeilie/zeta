import 'dart:async';

import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:settings_client/settings_client.dart';

final class FakeGeneralSettingsStore implements GeneralSettingsStore {
  GeneralSettingsResponse response = const GeneralSettingsResponse();
  Object? loadError;
  Object? saveError;
  Object? closeError;
  Completer<GeneralSettingsResponse>? loadCompleter;
  Completer<void>? saveCompleter;
  int loadCount = 0;
  int closeCount = 0;
  final saves = <GeneralSettingsResponse>[];

  @override
  Future<GeneralSettingsResponse> load() async {
    loadCount += 1;
    final error = loadError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return loadCompleter?.future ?? response;
  }

  @override
  Future<void> save(GeneralSettingsResponse settings) async {
    saves.add(settings);
    final error = saveError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    await (saveCompleter?.future ?? Future<void>.value());
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    final error = closeError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }
}

final class FakeAppearanceSettingsStore implements AppearanceSettingsStore {
  AppearanceSettingsResponse response = const AppearanceSettingsResponse();
  Object? loadError;
  Object? saveError;
  Object? closeError;
  int loadCount = 0;
  int closeCount = 0;
  final saves = <AppearanceSettingsResponse>[];

  @override
  Future<AppearanceSettingsResponse> load() async {
    loadCount += 1;
    final error = loadError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return response;
  }

  @override
  Future<void> save(AppearanceSettingsResponse settings) async {
    saves.add(settings);
    final error = saveError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    final error = closeError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }
}

final class FakeSystemFontCatalogApi implements SystemFontCatalogApi {
  List<SystemFontFamily> families = <SystemFontFamily>[];
  Object? error;
  final localeNames = <String>[];

  @override
  Future<List<SystemFontFamily>> listFontFamilies({
    required String localeName,
  }) async {
    localeNames.add(localeName);
    final currentError = error;
    if (currentError != null) {
      Error.throwWithStackTrace(currentError, StackTrace.current);
    }
    return List<SystemFontFamily>.from(families);
  }
}
