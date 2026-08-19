import 'dart:io';

import 'package:settings_client/settings_client.dart';
import 'package:test/test.dart';
import 'package:zeta_storage/zeta_storage.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zeta-settings-client-');
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('fromFile reads missing files and persists atomic text', () async {
    final file = File('${root.path}${Platform.pathSeparator}general.json');
    final storage = AtomicSettingsDocumentStorage.fromFile(file);

    expect(await storage.read(), isNull);
    await storage.write('{"version":3}');
    expect(await storage.read(), '{"version":3}');
    await storage.close();
    await storage.close();
    expect(storage.storage.isClosed, isTrue);
    expect(storage.read, throwsA(isA<StorageClosedException>()));
    expect(
      () => storage.write('closed'),
      throwsA(isA<StorageClosedException>()),
    );
  });

  test('atomic replacement failure preserves the original document', () async {
    final file = File('${root.path}${Platform.pathSeparator}appearance.json');
    await file.writeAsString('original');
    final atomic = AtomicTextFile(
      file,
      replacer: (_, _) async => throw StateError('replace failed'),
    );
    final storage = AtomicSettingsDocumentStorage(atomic);

    await expectLater(
      storage.write('replacement'),
      throwsA(
        isA<StorageWriteException>().having(
          (error) => error.operation,
          'operation',
          StorageOperation.replace,
        ),
      ),
    );
    expect(await file.readAsString(), 'original');
    await storage.close();
  });
}
