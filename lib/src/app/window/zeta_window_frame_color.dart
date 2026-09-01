import 'package:flutter/widgets.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// 启动窗口底色：优先用已解析的外观亮度，缺省再跟随系统。
Color launchWindowFrameColor({
  required Brightness systemBrightness,
  Brightness? preferredBrightness,
}) {
  final brightness = preferredBrightness ?? systemBrightness;
  return brightness == Brightness.dark
      ? IdeColors.dark.frame
      : IdeColors.light.frame;
}
