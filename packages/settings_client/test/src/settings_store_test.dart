import 'dart:convert';

import 'package:settings_client/settings_client.dart';
import 'package:test/test.dart';
import 'package:zeta_storage/zeta_storage.dart';

void main() {
  group('FileGeneralSettingsStore', () {
    test(
      'uses the injected clean-install value for absent or blank files',
      () async {
        const missing = GeneralSettingsResponse(
          appLanguage: AppLanguageResponse.english,
        );
        for (final source in <String?>[null, '', '  \n']) {
          final store = FileGeneralSettingsStore(
            storage: FakeSettingsDocumentStorage(source: source),
            missingValue: missing,
          );
          expect(await store.load(), missing);
        }
      },
    );

    test('loads and atomically saves current-schema JSON', () async {
      const settings = GeneralSettingsResponse(
        sendMessageShortcut: MessageSendShortcutResponse.primaryModifierEnter,
        appLanguage: AppLanguageResponse.english,
      );
      final storage = FakeSettingsDocumentStorage(
        source: jsonEncode(const GeneralSettingsCodec().encode(settings)),
      );
      final store = FileGeneralSettingsStore(storage: storage);

      expect(await store.load(), settings);
      await store.save(settings);
      expect(storage.writes, hasLength(1));
      expect(
        const GeneralSettingsCodec().decode(jsonDecode(storage.writes.single)),
        settings,
      );
    });

    test('reports malformed and corrupt current-schema documents', () async {
      final malformed = FileGeneralSettingsStore(
        storage: FakeSettingsDocumentStorage(source: '{'),
      );
      final corrupt = FileGeneralSettingsStore(
        storage: FakeSettingsDocumentStorage(source: '{"version":2}'),
      );

      await expectLater(
        malformed.load(),
        throwsA(
          isA<SettingsDecodeException>().having(
            (error) => error.code,
            'code',
            SettingsDecodeFailureCode.malformedJson,
          ),
        ),
      );
      await expectLater(
        corrupt.load(),
        throwsA(
          isA<SettingsDecodeException>().having(
            (error) => error.code,
            'code',
            SettingsDecodeFailureCode.unsupportedVersion,
          ),
        ),
      );
    });

    test('propagates permission failures and delegates close', () async {
      const readFailure = StorageReadException(
        path: 'general.json',
        cause: FileSystemExceptionFixture('permission denied'),
      );
      const writeFailure = StorageWriteException(
        operation: StorageOperation.replace,
        path: 'general.json',
        cause: FileSystemExceptionFixture('permission denied'),
      );
      final readStorage = FakeSettingsDocumentStorage(readError: readFailure);
      final writeStorage = FakeSettingsDocumentStorage(
        writeError: writeFailure,
      );

      await expectLater(
        FileGeneralSettingsStore(storage: readStorage).load(),
        throwsA(same(readFailure)),
      );
      final store = FileGeneralSettingsStore(storage: writeStorage);
      await expectLater(
        store.save(const GeneralSettingsResponse()),
        throwsA(same(writeFailure)),
      );
      await store.close();
      expect(writeStorage.closed, isTrue);
    });
  });

  group('FileAppearanceSettingsStore', () {
    test(
      'uses the injected clean-install value for absent or blank files',
      () async {
        const missing = AppearanceSettingsResponse(
          themeMode: AppearanceThemeModeResponse.dark,
        );
        for (final source in <String?>[null, '', '\t']) {
          final store = FileAppearanceSettingsStore(
            storage: FakeSettingsDocumentStorage(source: source),
            missingValue: missing,
          );
          expect(await store.load(), missing);
        }
      },
    );

    test('loads and atomically saves current-schema JSON', () async {
      const settings = AppearanceSettingsResponse(
        themeMode: AppearanceThemeModeResponse.light,
      );
      final storage = FakeSettingsDocumentStorage(
        source: jsonEncode(const AppearanceSettingsCodec().encode(settings)),
      );
      final store = FileAppearanceSettingsStore(storage: storage);

      expect(await store.load(), settings);
      await store.save(settings);
      expect(storage.writes, hasLength(1));
      expect(
        const AppearanceSettingsCodec().decode(
          jsonDecode(storage.writes.single),
        ),
        settings,
      );
    });

    test('reports malformed and corrupt current-schema documents', () async {
      final malformed = FileAppearanceSettingsStore(
        storage: FakeSettingsDocumentStorage(source: '{'),
      );
      final corrupt = FileAppearanceSettingsStore(
        storage: FakeSettingsDocumentStorage(source: '{"version":2}'),
      );

      await expectLater(
        malformed.load(),
        throwsA(
          isA<SettingsDecodeException>().having(
            (error) => error.code,
            'code',
            SettingsDecodeFailureCode.malformedJson,
          ),
        ),
      );
      await expectLater(
        corrupt.load(),
        throwsA(
          isA<SettingsDecodeException>().having(
            (error) => error.code,
            'code',
            SettingsDecodeFailureCode.unsupportedVersion,
          ),
        ),
      );
    });

    test('propagates permission failures and delegates close', () async {
      const readFailure = StorageReadException(
        path: 'appearance.json',
        cause: FileSystemExceptionFixture('permission denied'),
      );
      const writeFailure = StorageWriteException(
        operation: StorageOperation.replace,
        path: 'appearance.json',
        cause: FileSystemExceptionFixture('permission denied'),
      );
      final readStorage = FakeSettingsDocumentStorage(readError: readFailure);
      final writeStorage = FakeSettingsDocumentStorage(
        writeError: writeFailure,
      );

      await expectLater(
        FileAppearanceSettingsStore(storage: readStorage).load(),
        throwsA(same(readFailure)),
      );
      final store = FileAppearanceSettingsStore(storage: writeStorage);
      await expectLater(
        store.save(const AppearanceSettingsResponse()),
        throwsA(same(writeFailure)),
      );
      await store.close();
      expect(writeStorage.closed, isTrue);
    });
  });
}

final class FakeSettingsDocumentStorage implements SettingsDocumentStorage {
  FakeSettingsDocumentStorage({this.source, this.readError, this.writeError});

  final String? source;
  final Exception? readError;
  final Exception? writeError;
  final List<String> writes = <String>[];
  bool closed = false;

  @override
  Future<String?> read() async {
    if (readError case final error?) {
      throw error;
    }
    return source;
  }

  @override
  Future<void> write(String contents) async {
    if (writeError case final error?) {
      throw error;
    }
    writes.add(contents);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class FileSystemExceptionFixture implements Exception {
  const FileSystemExceptionFixture(this.message);

  final String message;
}
