import 'package:test/test.dart';
import 'package:zeta_storage/zeta_storage.dart';

void main() {
  group(StorageException, () {
    test('exposes typed operations without rendering paths or cause text', () {
      final failures = <StorageException>[
        const StorageReadException(
          path: '/secret/read',
          cause: FormatException(),
        ),
        const StorageWriteException(
          operation: StorageOperation.replace,
          path: '/secret/write',
          cause: FormatException(),
        ),
        const StoragePathException(
          path: '/secret/path',
          cause: FormatException(),
        ),
        StorageClosedException('/secret/closed'),
      ];

      expect(failures.map((failure) => failure.operation), <StorageOperation>[
        StorageOperation.read,
        StorageOperation.replace,
        StorageOperation.resolvePath,
        StorageOperation.close,
      ]);
      for (final failure in failures) {
        expect(failure.toString(), contains(failure.operation.name));
        expect(failure.toString(), isNot(contains('/secret/')));
        expect(failure.toString(), isNot(contains('FormatException')));
      }
    });
  });
}
