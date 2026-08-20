import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppMetrics', () {
    const metrics = AppMetrics();

    test('resolves control geometry', () {
      const style = TextStyle(fontSize: 12, height: 1.5);

      expect(metrics.controlPaddingYFor(AppControlSize.compact), 6);
      expect(metrics.controlPaddingYFor(AppControlSize.regular), 10);
      expect(metrics.controlMinHeightFor(AppControlSize.compact), 24);
      expect(metrics.controlMinHeightFor(AppControlSize.regular), 28);
      expect(metrics.controlIconBoxFor(style), 18);
      expect(
        metrics.controlNaturalHeightFor(
          style,
          size: AppControlSize.compact,
        ),
        30,
      );
    });

    test('copies and interpolates every metric', () {
      final copied = metrics.copyWith(titleBarHeight: 40);
      final unchanged = metrics.copyWith();
      const other = AppMetrics(
        titleBarHeight: 40,
        preferredInteractiveTarget: 56,
      );

      expect(copied.titleBarHeight, 40);
      expect(unchanged.titleBarHeight, metrics.titleBarHeight);
      expect(metrics.lerp(null, 0.5), metrics);
      expect(metrics.lerp(other, 0.5).titleBarHeight, 36);
      expect(metrics.lerp(other, 0.5).preferredInteractiveTarget, 52);
    });
  });

  group('AppRadii', () {
    const radii = AppRadii();

    test('builds nested shapes', () {
      expect(radii.allMicro, BorderRadius.circular(4));
      expect(radii.allSmall, BorderRadius.circular(6));
      expect(radii.allMedium, BorderRadius.circular(8));
      expect(radii.allLarge, BorderRadius.circular(12));
      expect(radii.allPill, BorderRadius.circular(999));
      expect(radii.panel(), isA<RoundedSuperellipseBorder>());
      expect(radii.control(radii.allSmall), isA<RoundedRectangleBorder>());
      expect(radii.isPanelTier(radii.allLarge), isTrue);
    });

    test('copies and interpolates the scale', () {
      final copied = radii.copyWith(micro: 2);
      final unchanged = radii.copyWith();
      const other = AppRadii(micro: 8, small: 10, medium: 12, large: 16);

      expect(copied.micro, 2);
      expect(unchanged.micro, radii.micro);
      expect(radii.lerp(null, 0.5), radii);
      expect(radii.lerp(other, 0.5).micro, 6);
    });
  });

  group('AppEffects', () {
    const effects = AppEffects();

    test('builds light and dark overlay effects', () {
      expect(effects.overlayShadow(Brightness.light), hasLength(1));
      expect(effects.overlayShadow(Brightness.dark), hasLength(1));
      expect(
        effects.focusRing(
          Brightness.light,
          accent: const Color(0xFF0000FF),
        ),
        hasLength(1),
      );
      expect(
        effects.focusRing(
          Brightness.dark,
          accent: const Color(0xFF0000FF),
        ),
        hasLength(1),
      );
      expect(effects.scrim(Brightness.light), isA<Color>());
      expect(effects.scrim(Brightness.dark), isA<Color>());
    });

    test('copies and interpolates the scale', () {
      final copied = effects.copyWith(overlayBlurRadius: 20);
      final unchanged = effects.copyWith();
      const other = AppEffects(
        overlayBlurRadius: 20,
        overlayOffsetY: 8,
        focusRingWidth: 4,
      );

      expect(copied.overlayBlurRadius, 20);
      expect(unchanged.overlayBlurRadius, effects.overlayBlurRadius);
      expect(effects.lerp(null, 0.5), effects);
      expect(effects.lerp(other, 0.5).overlayBlurRadius, 18);
    });
  });

  group('AppMotion', () {
    const motion = AppMotion();

    test('resolves reduced motion', () {
      expect(motion.resolve(motion.fast, reduceMotion: false), motion.fast);
      expect(
        motion.resolve(motion.fast, reduceMotion: true),
        Duration.zero,
      );
    });

    testWidgets('reads reduced motion from MediaQuery', (tester) async {
      late Duration duration;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              duration = motion.resolveFor(context, motion.normal);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(duration, Duration.zero);
    });

    test('copies and interpolates every motion token', () {
      final copied = motion.copyWith(fast: const Duration(milliseconds: 200));
      final unchanged = motion.copyWith();
      const other = AppMotion(
        fast: Duration(milliseconds: 300),
        normal: Duration(milliseconds: 300),
        slow: Duration(milliseconds: 300),
        loadingPulse: Duration(milliseconds: 1000),
        runningGlow: Duration(milliseconds: 3000),
        intelligenceShimmer: Duration(milliseconds: 2000),
        intelligenceImpact: Duration(milliseconds: 400),
        defaultCurve: Curves.linear,
        scrollCurve: Curves.linear,
        popupCurve: Curves.linear,
      );

      expect(copied.fast, const Duration(milliseconds: 200));
      expect(unchanged.fast, motion.fast);
      expect(motion.lerp(null, 0.5), motion);
      expect(motion.lerp(other, 0.25).defaultCurve, motion.defaultCurve);
      expect(motion.lerp(other, 0.75).defaultCurve, other.defaultCurve);
    });
  });

  group('AppTypography', () {
    final light = AppTypography.resolve(colors: AppColors.light);
    final dark = AppTypography.resolve(
      colors: AppColors.dark,
      uiFontFamily: 'Example UI',
      uiFontFamilyFallback: const <String>['Fallback'],
      codeFontFamily: 'Example Mono',
      uiFontSize: 14,
      codeFontSize: 16,
    );

    test('copies and interpolates the semantic table', () {
      final copied = light.copyWith(
        displayLarge: const TextStyle(fontSize: 99),
      );
      final unchanged = light.copyWith();

      expect(copied.displayLarge.fontSize, 99);
      expect(unchanged.displayLarge, light.displayLarge);
      expect(light.lerp(null, 0.5), light);
      expect(light.lerp(dark, 0.5).bodyMedium, isA<TextStyle>());
    });

    testWidgets('resolves configured and overridden typography', (
      tester,
    ) async {
      late AppTypography configured;
      late AppTypography overridden;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              configured = AppTypography.of(context);
              overridden = AppTypography.of(
                context,
                codeFontFamily: 'Override Mono',
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(configured.bodyMedium.fontFamily, bundledUiFontFamily);
      expect(overridden.codeMedium.fontFamily, 'Override Mono');
    });
  });
}
