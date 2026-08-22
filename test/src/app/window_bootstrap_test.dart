import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/window_bootstrap.dart';
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  group('launchWindowFrameColor', () {
    test('follows the preferred brightness even when the system differs', () {
      expect(
        launchWindowFrameColor(
          systemBrightness: Brightness.dark,
          preferredBrightness: Brightness.light,
        ),
        IdeColors.light.frame,
      );
      expect(
        launchWindowFrameColor(
          systemBrightness: Brightness.light,
          preferredBrightness: Brightness.dark,
        ),
        IdeColors.dark.frame,
      );
    });

    test('falls back to the system brightness when none is preferred', () {
      expect(
        launchWindowFrameColor(systemBrightness: Brightness.dark),
        IdeColors.dark.frame,
      );
      expect(
        launchWindowFrameColor(systemBrightness: Brightness.light),
        IdeColors.light.frame,
      );
    });
  });
}
