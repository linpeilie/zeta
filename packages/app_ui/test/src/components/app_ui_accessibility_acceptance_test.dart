import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('WCAG 2.2 AA acceptance', () {
    for (final palette in <String, AppColors>{
      'light': AppColors.light,
      'dark': AppColors.dark,
    }.entries) {
      test('${palette.key} text remains AA on every content surface', () {
        final colors = palette.value;
        final surfaces = <String, Color>{
          'surface': colors.surface,
          'surfaceElevated': colors.surfaceElevated,
          'surfaceOverlay': colors.surfaceOverlay,
          'panel': colors.panel,
          'editor': colors.editor,
        };
        final foregrounds = <String, Color>{
          'textPrimary': colors.textPrimary,
          'textSecondary': colors.textSecondary,
          'textTertiary': colors.textTertiary,
          'mutedText': colors.mutedText,
        };

        for (final surface in surfaces.entries) {
          for (final foreground in foregrounds.entries) {
            expect(
              _contrastRatio(foreground.value, surface.value),
              greaterThanOrEqualTo(4.5),
              reason:
                  '${palette.key}.${foreground.key} on ${surface.key} must '
                  'meet WCAG AA normal-text contrast',
            );
          }
        }
      });

      test('${palette.key} focus indicator remains distinguishable', () {
        final colors = palette.value;
        for (final surface in <Color>[
          colors.surface,
          colors.surfaceElevated,
          colors.surfaceOverlay,
          colors.panel,
          colors.editor,
        ]) {
          expect(
            _contrastRatio(colors.focusRing, surface),
            greaterThanOrEqualTo(3),
          );
        }
      });
    }

    testWidgets('interactive controls preserve the 24px target floor', (
      tester,
    ) async {
      const buttonKey = ValueKey<String>('button');
      const iconButtonKey = ValueKey<String>('icon-button');
      const chipKey = ValueKey<String>('chip');
      const switchKey = ValueKey<String>('switch');
      await tester.pumpShadcnApp(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const IdeButton(
              key: buttonKey,
              label: 'Continue',
              onPressed: _noop,
            ),
            const IdeIconButton(
              key: iconButtonKey,
              icon: Icons.refresh,
              semanticLabel: 'Refresh',
              onPressed: _noop,
            ),
            const IdeChip(key: chipKey, label: 'Filter', onPressed: _noop),
            IdeSwitch(
              key: switchKey,
              value: true,
              semanticLabel: 'Enable feature',
              onChanged: (_) {},
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      for (final key in <Key>[
        buttonKey,
        iconButtonKey,
        chipKey,
        switchKey,
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(24), reason: '$key width');
        expect(size.height, greaterThanOrEqualTo(24), reason: '$key height');
      }
    });

    testWidgets('representative desktop content supports 200% text', (
      tester,
    ) async {
      await tester.pumpShadcnApp(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(
            width: 760,
            height: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                IdePageHeader(
                  title: 'Accessibility settings',
                  subtitle: 'Configure the desktop experience',
                  leading: IdeIconBox(Icons.accessibility_new),
                ),
                Expanded(
                  child: IdePageBody(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        IdeStatusCard(
                          tone: IdeStatusCardTone.info,
                          title: 'Screen reader ready',
                          body: Text('Announcements use live regions.'),
                        ),
                        IdeKeyValueRow(
                          label: 'Text scaling',
                          value: '200 percent',
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: IdeButton(
                            label: 'Save accessibility settings',
                            onPressed: _noop,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        size: const Size(800, 740),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Accessibility settings'), findsOneWidget);
      expect(find.text('Save accessibility settings'), findsOneWidget);
    });

    testWidgets('reduced motion resolves component animation to zero', (
      tester,
    ) async {
      await tester.pumpShadcnApp(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: IdeSwitch(
            value: true,
            semanticLabel: 'Reduced motion switch',
            onChanged: (_) {},
          ),
        ),
      );

      final animatedContainers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(IdeSwitch),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(animatedContainers, isNotEmpty);
      expect(
        animatedContainers.every(
          (container) => container.duration == Duration.zero,
        ),
        isTrue,
      );
    });
  });
}

double _contrastRatio(Color foreground, Color background) {
  final opaqueForeground = Color.alphaBlend(foreground, background);
  final foregroundLuminance = opaqueForeground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = math.max(foregroundLuminance, backgroundLuminance);
  final darker = math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

void _noop() {}
