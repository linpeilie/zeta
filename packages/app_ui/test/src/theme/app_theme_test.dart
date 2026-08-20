import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    group('light', () {
      test('returns a ThemeData', () {
        expect(AppTheme.light, isA<ThemeData>());
      });

      test('has AppColors extension', () {
        expect(AppTheme.light.extension<AppColors>(), isNotNull);
      });

      test('has AppSpacing extension', () {
        expect(AppTheme.light.extension<AppSpacing>(), isNotNull);
      });

      test('has AppTextStyles extension', () {
        expect(AppTheme.light.extension<AppTextStyles>(), isNotNull);
      });

      test('has migrated desktop token extensions', () {
        expect(AppTheme.light.extension<AppTypography>(), isNotNull);
        expect(AppTheme.light.extension<AppMetrics>(), isNotNull);
        expect(AppTheme.light.extension<AppRadii>(), isNotNull);
        expect(AppTheme.light.extension<AppEffects>(), isNotNull);
        expect(AppTheme.light.extension<AppMotion>(), isNotNull);
      });

      test('has light brightness', () {
        expect(AppTheme.light.brightness, Brightness.light);
      });
    });

    group('dark', () {
      test('returns a ThemeData', () {
        expect(AppTheme.dark, isA<ThemeData>());
      });

      test('has AppColors extension', () {
        expect(AppTheme.dark.extension<AppColors>(), isNotNull);
      });

      test('has AppSpacing extension', () {
        expect(AppTheme.dark.extension<AppSpacing>(), isNotNull);
      });

      test('has AppTextStyles extension', () {
        expect(AppTheme.dark.extension<AppTextStyles>(), isNotNull);
      });

      test('has migrated desktop token extensions', () {
        expect(AppTheme.dark.extension<AppTypography>(), isNotNull);
        expect(AppTheme.dark.extension<AppMetrics>(), isNotNull);
        expect(AppTheme.dark.extension<AppRadii>(), isNotNull);
        expect(AppTheme.dark.extension<AppEffects>(), isNotNull);
        expect(AppTheme.dark.extension<AppMotion>(), isNotNull);
      });

      test('has dark brightness', () {
        expect(AppTheme.dark.brightness, Brightness.dark);
      });
    });

    test('builds custom Material projection', () {
      final theme = AppTheme.material(
        brightness: Brightness.light,
        uiFontFamily: 'Example UI',
        uiFontFamilyFallback: const <String>['Fallback'],
        codeFontFamily: 'Example Mono',
        uiFontSize: 14,
        codeFontSize: 16,
      );

      expect(theme.textTheme.bodyMedium?.fontFamily, 'Example UI');
      expect(
        theme.extension<AppTypography>()?.codeMedium.fontFamily,
        'Example Mono',
      );
    });

    test('builds and resolves light shadcn projection', () {
      final theme = AppTheme.shadcnLight;
      final colors = theme.colorScheme;
      final typography = theme.typography;

      expect(colors.background, isA<Color>());
      expect(colors.foreground, isA<Color>());
      expect(colors.card, isA<Color>());
      expect(colors.cardForeground, isA<Color>());
      expect(colors.popover, isA<Color>());
      expect(colors.popoverForeground, isA<Color>());
      expect(colors.primary, isA<Color>());
      expect(colors.primaryForeground, isA<Color>());
      expect(colors.secondary, isA<Color>());
      expect(colors.secondaryForeground, isA<Color>());
      expect(colors.muted, isA<Color>());
      expect(colors.mutedForeground, isA<Color>());
      expect(colors.accent, isA<Color>());
      expect(colors.accentForeground, isA<Color>());
      expect(colors.destructive, isA<Color>());
      // The legacy shadcn field is still required by the pinned package API.
      // ignore: deprecated_member_use
      expect(colors.destructiveForeground, isA<Color>());
      expect(colors.border, isA<Color>());
      expect(colors.input, isA<Color>());
      expect(colors.ring, isA<Color>());
      expect(colors.chart1, isA<Color>());
      expect(colors.chart2, isA<Color>());
      expect(colors.chart3, isA<Color>());
      expect(colors.chart4, isA<Color>());
      expect(colors.chart5, isA<Color>());
      expect(typography.sans, isA<TextStyle>());
      expect(typography.mono, isA<TextStyle>());
      expect(typography.xSmall, isA<TextStyle>());
      expect(typography.small, isA<TextStyle>());
      expect(typography.base, isA<TextStyle>());
      expect(typography.inlineCode, isA<TextStyle>());
    });

    test('builds custom dark shadcn projection', () {
      final theme = AppTheme.shadcn(
        brightness: Brightness.dark,
        uiFontFamily: 'Example UI',
        uiFontFamilyFallback: const <String>['Fallback'],
        codeFontFamily: 'Example Mono',
        uiFontSize: 14,
        codeFontSize: 16,
      );

      expect(AppTheme.shadcnDark.colorScheme.background, isA<Color>());
      expect(theme.colorScheme.background, AppColors.dark.frameSurface);
      expect(theme.typography.mono.fontFamily, endsWith('Example Mono'));
    });
  });
}
