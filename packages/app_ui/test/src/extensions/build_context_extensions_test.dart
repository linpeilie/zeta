import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('AppThemeBuildContext', () {
    testWidgets('appColors returns AppColors from theme', (tester) async {
      late AppColors colors;
      await tester.pumpApp(
        Builder(
          builder: (context) {
            colors = context.appColors;
            return const SizedBox();
          },
        ),
      );

      expect(colors, isA<AppColors>());
    });

    testWidgets('appSpacing returns AppSpacing from theme', (tester) async {
      late AppSpacing spacing;
      await tester.pumpApp(
        Builder(
          builder: (context) {
            spacing = context.appSpacing;
            return const SizedBox();
          },
        ),
      );

      expect(spacing, isA<AppSpacing>());
    });

    testWidgets('appTextStyles returns AppTextStyles from theme', (
      tester,
    ) async {
      late AppTextStyles textStyles;
      await tester.pumpApp(
        Builder(
          builder: (context) {
            textStyles = context.appTextStyles;
            return const SizedBox();
          },
        ),
      );

      expect(textStyles, isA<AppTextStyles>());
    });

    testWidgets('returns every migrated desktop token', (tester) async {
      late AppMetrics metrics;
      late AppRadii radii;
      late AppEffects effects;
      late AppMotion motion;
      late AppTypography typography;
      await tester.pumpApp(
        Builder(
          builder: (context) {
            metrics = context.appMetrics;
            radii = context.appRadii;
            effects = context.appEffects;
            motion = context.appMotion;
            typography = context.appTypography;
            return const SizedBox();
          },
        ),
      );

      expect(metrics, isA<AppMetrics>());
      expect(radii, isA<AppRadii>());
      expect(effects, isA<AppEffects>());
      expect(motion, isA<AppMotion>());
      expect(typography, isA<AppTypography>());
    });
  });
}
