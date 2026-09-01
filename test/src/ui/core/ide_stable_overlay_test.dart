import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  test('popover configurations stop following their anchor', () {
    final configuration = ideStableOverlayConfiguration(
      sf.PopoverConfiguration(
        alignment: Alignment.bottomCenter,
        follow: true,
        onTickFollow: (_) {},
      ),
    );

    expect(configuration, isA<sf.PopoverConfiguration>());
    final popover = configuration as sf.PopoverConfiguration;
    expect(popover.follow, isFalse);
    expect(popover.onTickFollow, isNull);
    // 只关 follow，其余字段原样透传。
    expect(popover.alignment, Alignment.bottomCenter);
  });

  test('menu configurations stop following their anchor', () {
    final configuration = ideStableOverlayConfiguration(
      const sf.MenuConfiguration(
        alignment: Alignment.bottomCenter,
        follow: true,
        modal: false,
      ),
    );

    expect(configuration, isA<sf.MenuConfiguration>());
    final menu = configuration as sf.MenuConfiguration;
    expect(menu.follow, isFalse);
    expect(menu.onTickFollow, isNull);
    expect(menu.alignment, Alignment.bottomCenter);
    expect(menu.modal, isFalse);
  });

  test('tooltip configurations stop following their anchor', () {
    final configuration = ideStableOverlayConfiguration(
      const sf.TooltipConfiguration(
        alignment: Alignment.topCenter,
        follow: true,
      ),
    );

    expect(configuration, isA<sf.TooltipConfiguration>());
    final tooltip = configuration as sf.TooltipConfiguration;
    expect(tooltip.follow, isFalse);
    expect(tooltip.alignment, Alignment.topCenter);
  });

  test('configurations without anchor following are left alone', () {
    const dialog = sf.DialogConfiguration();
    expect(ideStableOverlayConfiguration(dialog), same(dialog));
  });
}
