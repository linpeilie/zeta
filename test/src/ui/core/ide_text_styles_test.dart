import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';

void main() {
  test('scales UI and code typography independently', () {
    final styles = IdeTextStyles.resolve(
      colors: IdeColors.light,
      uiFontSize: 14,
      codeFontSize: 18,
    );

    expect(styles.bodyMedium.fontSize, 14);
    expect(styles.displayLarge.fontSize, 21);
    expect(styles.codeMedium.fontSize, 18);
    expect(styles.codeSmall.fontSize, 16.5);
  });
}
