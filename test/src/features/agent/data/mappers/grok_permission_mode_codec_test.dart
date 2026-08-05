import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_permission_mode_codec.dart';

void main() {
  group('GrokPermissionModeCodec', () {
    test('parses aliases and fail-closes default/empty/unknown to ask', () {
      expect(GrokPermissionModeCodec.parse(null), GrokPermissionMode.ask);
      expect(GrokPermissionModeCodec.parse(''), GrokPermissionMode.ask);
      expect(GrokPermissionModeCodec.parse('   '), GrokPermissionMode.ask);
      expect(GrokPermissionModeCodec.parse('default'), GrokPermissionMode.ask);
      expect(GrokPermissionModeCodec.parse('DEFAULT'), GrokPermissionMode.ask);
      expect(GrokPermissionModeCodec.parse('ask'), GrokPermissionMode.ask);
      expect(GrokPermissionModeCodec.parse('auto'), GrokPermissionMode.auto);
      expect(
        GrokPermissionModeCodec.parse('always-approve'),
        GrokPermissionMode.alwaysApprove,
      );
      expect(
        GrokPermissionModeCodec.parse('bypassPermissions'),
        GrokPermissionMode.alwaysApprove,
      );
      expect(GrokPermissionModeCodec.parse('unknown'), GrokPermissionMode.ask);
      expect(
        GrokPermissionModeCodec.parse('yolo'),
        GrokPermissionMode.alwaysApprove,
      );
    });

    test('wire ids are the three stable product modes only', () {
      expect(GrokPermissionModeCodec.wireId(GrokPermissionMode.ask), 'ask');
      expect(GrokPermissionModeCodec.wireId(GrokPermissionMode.auto), 'auto');
      expect(
        GrokPermissionModeCodec.wireId(GrokPermissionMode.alwaysApprove),
        'always-approve',
      );
      // 不再有独立 default wire id。
      expect(
        GrokPermissionMode.values.map(GrokPermissionModeCodec.wireId),
        isNot(contains('default')),
      );
    });

    test(
      'session meta is consistent for new/load and only opens elevated modes',
      () {
        expect(
          GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.alwaysApprove),
          <String, Object?>{'yoloMode': true, 'clientIdentifier': 'zeta'},
        );
        expect(
          GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.auto),
          <String, Object?>{'autoMode': true, 'clientIdentifier': 'zeta'},
        );
        // Ask：不发明 yoloMode/autoMode false；依赖 process Ask 基线。
        expect(
          GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.ask),
          <String, Object?>{'clientIdentifier': 'zeta'},
        );
        expect(
          GrokPermissionModeCodec.sessionMeta(
            GrokPermissionMode.ask,
          ).containsKey('yoloMode'),
          isFalse,
        );
        expect(
          GrokPermissionModeCodec.sessionMeta(
            GrokPermissionMode.ask,
          ).containsKey('autoMode'),
          isFalse,
        );
      },
    );

    test(
      'live notification params cover all three modes and clear elevated on ask',
      () {
        expect(
          GrokPermissionModeCodec.yoloModeChangedParams(
            GrokPermissionMode.alwaysApprove,
          ),
          <String, Object?>{
            'permission_mode': 'always-approve',
            'yolo_mode': true,
            'auto_mode': false,
            'clientIdentifier': 'zeta',
          },
        );
        expect(
          GrokPermissionModeCodec.yoloModeChangedParams(
            GrokPermissionMode.auto,
          ),
          <String, Object?>{
            'permission_mode': 'auto',
            'yolo_mode': false,
            'auto_mode': true,
            'clientIdentifier': 'zeta',
          },
        );
        // Always approve → Ask 后必须显式关闭自动批准。
        expect(
          GrokPermissionModeCodec.yoloModeChangedParams(GrokPermissionMode.ask),
          <String, Object?>{
            'permission_mode': 'ask',
            'yolo_mode': false,
            'auto_mode': false,
            'clientIdentifier': 'zeta',
          },
        );
      },
    );

    test('catalog exposes exactly three modes in stable order', () {
      final catalog = GrokPermissionModeCodec.catalog().options;
      expect(catalog.map((item) => item.id).toList(), <String>[
        'ask',
        'auto',
        'always-approve',
      ]);
      expect(catalog.map((item) => item.label).toList(), <String>[
        'Ask',
        'Auto',
        'Always approve',
      ]);
      expect(catalog, hasLength(3));
      expect(catalog.every((item) => item.allowed), isTrue);
    });

    test('live notification method is the verified single _x.ai/ method', () {
      expect(
        GrokPermissionModeCodec.yoloModeChangedMethod,
        '_x.ai/yolo_mode_changed',
      );
    });
  });
}
