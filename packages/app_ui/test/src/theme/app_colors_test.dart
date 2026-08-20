import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors', () {
    final colors = AppColors.light;

    test('copyWith returns a new instance with updated values', () {
      final updated = colors.copyWith(success: const Color(0xFF000000));
      expect(updated.success, const Color(0xFF000000));
      expect(updated.onSuccess, colors.onSuccess);
      expect(updated.warning, colors.warning);
      expect(updated.onWarning, colors.onWarning);
      expect(updated.info, colors.info);
      expect(updated.onInfo, colors.onInfo);
    });

    test('copyWith returns identical instance when no values are provided', () {
      final copy = colors.copyWith();
      expect(copy.success, colors.success);
      expect(copy.onSuccess, colors.onSuccess);
      expect(copy.warning, colors.warning);
      expect(copy.onWarning, colors.onWarning);
      expect(copy.info, colors.info);
      expect(copy.onInfo, colors.onInfo);
    });

    test('lerp returns this when other is not AppColors', () {
      final result = colors.lerp(null, 0.5);
      expect(result, colors);
    });

    test('lerp interpolates between two AppColors', () {
      final other = AppColors.dark;

      final result = colors.lerp(other, 0.5);
      expect(result.success, isNotNull);
      expect(result.onSuccess, isNotNull);
      expect(result.warning, isNotNull);
      expect(result.onWarning, isNotNull);
      expect(result.info, isNotNull);
      expect(result.onInfo, isNotNull);
    });

    testWidgets('resolves configured and fallback palettes', (tester) async {
      late AppColors configured;
      late AppColors fallback;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              configured = AppColors.of(context);
              return Theme(
                data: ThemeData.dark(),
                child: Builder(
                  builder: (context) {
                    fallback = AppColors.of(context);
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );

      expect(configured, same(AppColors.light));
      expect(fallback, same(AppColors.dark));
      expect(colors.controlSurface, colors.surfaceElevated);
      expect(colors.popoverSurface, colors.surfaceOverlay);
    });
  });
}
