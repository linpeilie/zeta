import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_permission_mode_codec.dart';

void main() {
  group('GrokPermissionModeCodec', () {
    test('parses known wire ids and falls back to ask', () {
      expect(
        GrokPermissionModeCodec.parse('always-approve'),
        GrokPermissionMode.alwaysApprove,
      );
      expect(GrokPermissionModeCodec.parse('auto'), GrokPermissionMode.auto);
      expect(GrokPermissionModeCodec.parse(null), GrokPermissionMode.ask);
      expect(GrokPermissionModeCodec.parse('unknown'), GrokPermissionMode.ask);
    });

    test('session meta only sets yolo or auto flags', () {
      expect(
        GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.alwaysApprove),
        <String, Object?>{'yoloMode': true, 'clientIdentifier': 'zeta'},
      );
      expect(
        GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.auto),
        <String, Object?>{'autoMode': true, 'clientIdentifier': 'zeta'},
      );
      expect(
        GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.ask),
        <String, Object?>{'clientIdentifier': 'zeta'},
      );
    });

    test('catalog exposes four modes with Always approve last', () {
      final catalog = GrokPermissionModeCodec.catalogAsOptions();
      expect(catalog.map((item) => item.id).toList(), <String>[
        'default',
        'ask',
        'auto',
        'always-approve',
      ]);
      expect(catalog.last.displayName, 'Always approve');
    });
  });
}
