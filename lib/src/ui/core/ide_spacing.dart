import 'package:flutter/widgets.dart';

/// IDE 设计系统间距 token。
abstract final class IdeSpacing {
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  static const EdgeInsets none = EdgeInsets.zero;

  static const EdgeInsets all4 = EdgeInsets.all(space4);
  static const EdgeInsets all6 = EdgeInsets.all(space6);
  static const EdgeInsets all8 = EdgeInsets.all(space8);
  static const EdgeInsets all10 = EdgeInsets.all(space10);
  static const EdgeInsets all12 = EdgeInsets.all(space12);
  static const EdgeInsets all16 = EdgeInsets.all(space16);
  static const EdgeInsets all20 = EdgeInsets.all(space20);

  static const EdgeInsets horizontal6 = EdgeInsets.symmetric(
    horizontal: space6,
  );
  static const EdgeInsets horizontal8 = EdgeInsets.symmetric(
    horizontal: space8,
  );
  static const EdgeInsets horizontal10 = EdgeInsets.symmetric(
    horizontal: space10,
  );
  static const EdgeInsets horizontal12 = EdgeInsets.symmetric(
    horizontal: space12,
  );
  static const EdgeInsets horizontal16 = EdgeInsets.symmetric(
    horizontal: space16,
  );
  static const EdgeInsets horizontal20 = EdgeInsets.symmetric(
    horizontal: space20,
  );

  static const EdgeInsets vertical4 = EdgeInsets.symmetric(vertical: space4);
  static const EdgeInsets vertical6 = EdgeInsets.symmetric(vertical: space6);
  static const EdgeInsets vertical8 = EdgeInsets.symmetric(vertical: space8);
  static const EdgeInsets vertical12 = EdgeInsets.symmetric(vertical: space12);
  static const EdgeInsets vertical16 = EdgeInsets.symmetric(vertical: space16);

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: space20,
    vertical: space16,
  );
  static const EdgeInsets pagePaddingCompact = EdgeInsets.all(space12);
  static const EdgeInsets sectionPadding = EdgeInsets.all(space16);
  static const EdgeInsets panelPadding = EdgeInsets.all(space12);
  static const EdgeInsets cardPadding = EdgeInsets.all(space10);
  static const EdgeInsets dialogPadding = EdgeInsets.all(space16);
  static const EdgeInsets toolbarPadding = EdgeInsets.symmetric(
    horizontal: space8,
    vertical: space4,
  );
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: space10,
    vertical: space6,
  );
  static const EdgeInsets settingsRowPadding = EdgeInsets.symmetric(
    horizontal: space12,
    vertical: space10,
  );
  static const EdgeInsets composerPadding = EdgeInsets.fromLTRB(
    space12,
    space10,
    space8,
    space8,
  );
  static const EdgeInsets compactControlPadding = EdgeInsets.symmetric(
    horizontal: space8,
    vertical: space4,
  );
  static const EdgeInsets inputContentPadding = EdgeInsets.symmetric(
    horizontal: space12,
    vertical: space8,
  );
}
