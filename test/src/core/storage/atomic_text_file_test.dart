import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/core/storage/atomic_text_file.dart';

void main() {
  group('AtomicTextFile', () {
    late Directory directory;
    late File target;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('zeta_atomic_file_');
      target = File(
        '${directory.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}state.json',
      );
    });

    tearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    test(
      'returns null for a missing file and creates parent directories',
      () async {
        final storage = AtomicTextFile(target);

        expect(await storage.read(), isNull);
        await storage.write('{"version":1}');

        expect(await storage.read(), '{"version":1}');
        expect(target.parent.existsSync(), isTrue);
      },
    );

    test(
      'serializes concurrent replacements without leaving temp files',
      () async {
        final storage = AtomicTextFile(target);

        final first = storage.write('first');
        final second = storage.write('second');
        await Future.wait(<Future<void>>[first, second]);

        expect(await target.readAsString(), 'second');
        expect(
          target.parent.listSync().whereType<File>().map((file) => file.path),
          <String>[target.path],
        );
      },
    );
  });
}
