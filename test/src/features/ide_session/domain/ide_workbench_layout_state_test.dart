import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

void main() {
  group('IdeWorkbenchLayoutState', () {
    test('uses safe first-run defaults', () {
      const state = IdeWorkbenchLayoutState();

      expect(state.leftSidebarVisible, isTrue);
      expect(state.leftSidebarWidth, isNull);
      expect(state.selectedAgentUsageProviderId, isNull);
    });

    test(
      'copyWith updates fields and can explicitly clear nullable values',
      () {
        const initial = IdeWorkbenchLayoutState(
          leftSidebarWidth: 286,
          selectedAgentUsageProviderId: 'codex',
        );

        final updated = initial.copyWith(
          leftSidebarVisible: false,
          leftSidebarWidth: 320,
          selectedAgentUsageProviderId: '  Claude_Custom  ',
        );
        final cleared = updated.copyWith(
          leftSidebarWidth: null,
          selectedAgentUsageProviderId: null,
        );

        expect(
          updated,
          const IdeWorkbenchLayoutState(
            leftSidebarVisible: false,
            leftSidebarWidth: 320,
            selectedAgentUsageProviderId: 'Claude_Custom',
          ),
        );
        expect(cleared.leftSidebarVisible, isFalse);
        expect(cleared.leftSidebarWidth, isNull);
        expect(cleared.selectedAgentUsageProviderId, isNull);
      },
    );

    test('round-trips every persisted field', () {
      const state = IdeWorkbenchLayoutState(
        leftSidebarVisible: false,
        leftSidebarWidth: 312.5,
        selectedAgentUsageProviderId: 'grok',
      );

      final restored = IdeWorkbenchLayoutState.tryDecode(state.toJson());

      expect(restored, state);
      expect(restored.hashCode, state.hashCode);
    });

    test('defaults missing fields and ignores unknown fields', () {
      final restored = IdeWorkbenchLayoutState.tryDecode(<String, Object?>{
        'leftSidebarVisible': false,
        'unknownFutureField': <String, Object?>{'enabled': true},
      });

      expect(
        restored,
        const IdeWorkbenchLayoutState(leftSidebarVisible: false),
      );
    });

    test('falls back per field for wrong JSON types', () {
      final restored = IdeWorkbenchLayoutState.tryDecode(<String, Object?>{
        'leftSidebarVisible': 'false',
        'leftSidebarWidth': '300',
        'selectedAgentUsageProviderId': 42,
      });

      expect(restored, const IdeWorkbenchLayoutState());
      expect(
        IdeWorkbenchLayoutState.tryDecode(const <Object?>[]),
        const IdeWorkbenchLayoutState(),
      );
    });

    test('rejects non-finite and out-of-range numeric values', () {
      for (final invalidWidth in <num>[
        0,
        -1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final restored = IdeWorkbenchLayoutState.tryDecode(<String, Object?>{
          'leftSidebarWidth': invalidWidth,
        });

        expect(restored.leftSidebarWidth, isNull, reason: '$invalidWidth');
      }
    });

    test('accepts integer JSON numbers and normalizes blank provider ids', () {
      final restored = IdeWorkbenchLayoutState.tryDecode(<String, Object?>{
        'leftSidebarWidth': 300,
        'selectedAgentUsageProviderId': '   ',
      });

      expect(restored.leftSidebarWidth, 300.0);
      expect(restored.selectedAgentUsageProviderId, isNull);
    });
  });
}
