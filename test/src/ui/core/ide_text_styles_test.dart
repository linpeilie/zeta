import 'package:flutter/material.dart';
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
    expect(styles.displayHero.fontSize, closeTo(32.6667, 0.0001));
    expect(styles.displayLarge.fontSize, 21);
    expect(styles.codeMedium.fontSize, 18);
    expect(styles.codeSmall.fontSize, 16.5);
    expect(styles.pageTitle.fontSize, 17.5);
    expect(styles.sectionTitle.fontSize, closeTo(15.1667, 0.0001));
    expect(styles.rowTitle.fontSize, 14);
    expect(styles.groupTitle.fontSize, 10.5);
    expect(styles.toolbarLabel.fontSize, closeTo(12.8333, 0.0001));
    expect(styles.proseBody.fontSize, closeTo(15.1667, 0.0001));
    expect(styles.meta.fontSize, closeTo(11.6667, 0.0001));
    expect(styles.placeholder.fontSize, 14);
    // 机器标识符与数值按代码字号缩放（codeScale = 18/12 = 1.5），
    // 不跟随界面字号。
    expect(styles.identifier.fontSize, 18);
    expect(styles.numeric.fontSize, 16.5);
    expect(styles.metricValue.fontSize, 27);
  });

  test('机器标识符与数值使用等宽字体', () {
    final styles = IdeTextStyles.resolve(
      colors: IdeColors.light,
      uiFontFamily: 'Geist',
      codeFontFamily: 'JetBrainsMono',
    );

    expect(styles.identifier.fontFamily, 'JetBrainsMono');
    expect(styles.numeric.fontFamily, 'JetBrainsMono');
    expect(styles.metricValue.fontFamily, 'JetBrainsMono');
    // 对照：普通界面文本仍走 UI 字体。
    expect(styles.bodyMedium.fontFamily, 'Geist');
    expect(styles.rowTitle.fontFamily, 'Geist');
  });

  test('表格数值与指标数值启用等宽数字，保证按位对齐', () {
    final styles = IdeTextStyles.resolve(colors: IdeColors.light);

    expect(
      styles.numeric.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    expect(
      styles.metricValue.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    // 普通正文不应被强制等宽数字。
    expect(styles.bodyMedium.fontFeatures, isNull);
  });

  test('identifier 尺寸对齐 rowTitle，便于在列表行里直接替换', () {
    final styles = IdeTextStyles.resolve(colors: IdeColors.light);

    expect(styles.identifier.fontSize, styles.rowTitle.fontSize);
    expect(styles.identifier.fontWeight, styles.rowTitle.fontWeight);
  });

  test('高层语义样式使用统一字重与前景色', () {
    final styles = IdeTextStyles.resolve(colors: IdeColors.dark);

    expect(styles.pageTitle.fontWeight, FontWeight.w600);
    expect(styles.sectionTitle.fontWeight, FontWeight.w600);
    expect(styles.rowTitle.fontWeight, FontWeight.w500);
    expect(styles.toolbarLabel.color, IdeColors.dark.textSecondary);
    expect(styles.proseBody.height, 1.55);
    expect(styles.meta.color, IdeColors.dark.textTertiary);
    expect(styles.metricValue.fontWeight, FontWeight.w600);
    expect(styles.placeholder.color, IdeColors.dark.textTertiary);
  });

  test('英雄标题是全表唯一压过 displayLarge 的一档，并收紧字距', () {
    final styles = IdeTextStyles.resolve(colors: IdeColors.light);

    // 首页标题要当「绝对视觉中心」，必须明显大于原本的最大展示标题。
    expect(
      styles.displayHero.fontSize,
      greaterThan(styles.displayLarge.fontSize!),
    );
    expect(styles.displayHero.fontWeight, FontWeight.w700);
    // 大字号下默认字间距显得松，负字距把标题收成一个整体。
    expect(styles.displayHero.letterSpacing, -0.4);
    expect(styles.displayHero.color, IdeColors.light.textPrimary);
  });

  test('分组眉标题压到全表最小字号，并靠字重与次级色站住索引位', () {
    final styles = IdeTextStyles.resolve(colors: IdeColors.dark);

    // 眉标题必须小于它管辖的行标题与行描述，否则会重新变成「区块标题」。
    expect(styles.groupTitle.fontSize, lessThan(styles.titleSmall.fontSize!));
    expect(styles.groupTitle.fontSize, lessThan(styles.meta.fontSize!));
    expect(styles.groupTitle.fontWeight, FontWeight.w700);
    expect(styles.groupTitle.color, IdeColors.dark.textSecondary);
    // 字距补偿小字号下的拥挤感。
    expect(styles.groupTitle.letterSpacing, 0.4);
    // 对照：sectionTitle 是要被读到的区块标题，方向相反。
    expect(styles.groupTitle.fontSize, lessThan(styles.sectionTitle.fontSize!));
  });
}
