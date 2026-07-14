import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_diagnostics_store.dart';

void main() {
  group('CursorDiagnosticsStore', () {
    test('redacts secrets, bounds lines, and evicts oldest records', () {
      // Arrange
      var tick = 0;
      final store = CursorDiagnosticsStore(
        maxRecords: 2,
        maxLineLength: 48,
        clock: () => DateTime.utc(2026, 7, 14, 0, 0, tick++),
      );

      // Act
      store.recordStderr('first');
      store.recordStderr('token=super-secret-token\nsecond line');
      store.recordStderr('third ${List<String>.filled(100, 'x').join()}');

      // Assert
      final records = store.snapshot.records;
      expect(records, hasLength(2));
      expect(records.first.message, isNot(contains('super-secret-token')));
      expect(records.first.message, isNot(contains('\n')));
      expect(records.last.message.length, lessThanOrEqualTo(49));
      expect(records.any((record) => record.message == 'first'), isFalse);
    });

    test('keeps only handshake whitelist and capability names', () {
      // Arrange
      final store = CursorDiagnosticsStore();

      // Act
      store.recordHandshake(
        protocolVersion: 1,
        cliVersion: '2.0.0',
        agentInfo: <String, Object?>{
          'title': 'Cursor Agent',
          'version': '2.0.0',
          'token': 'must-not-survive',
        },
        capabilities: <String, Object?>{
          'loadSession': true,
          'promptCapabilities': <String, Object?>{'image': true},
          'prompt': 'must-not-survive',
        },
      );

      // Assert
      final handshake = store.snapshot.handshake!;
      expect(handshake.protocolVersion, '1');
      expect(handshake.agentName, 'Cursor Agent');
      expect(handshake.capabilities, contains('loadSession'));
      expect(handshake.capabilities, contains('promptCapabilities.image'));
      expect(
        store.snapshot.records.single.message,
        isNot(contains('must-not-survive')),
      );
    });
  });
}
