import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/presentation/widgets/agent_markdown_body.dart';
import 'package:zeta_ui/zeta_ui.dart';

import '../../../../testing/recording_system_url_opener.dart';

/// 会话正文里的链接必须交给系统浏览器，且白名单只放 http(s)。
void main() {
  testWidgets('点击 http 链接交给系统打开器', (tester) async {
    final opener = RecordingSystemUrlOpener();
    await _pumpBody(
      tester,
      opener,
      'Visit [Example](https://example.com/docs)',
    );

    await _tapLink(tester, 'Visit Example', label: 'Example');

    expect(opener.opened, <String>['https://example.com/docs']);
    expect(opener.rejected, isEmpty);
  });

  testWidgets('javascript: 链接被打开器拒绝，不会拉起任何程序', (tester) async {
    final opener = RecordingSystemUrlOpener();
    await _pumpBody(tester, opener, 'Visit [Example](javascript:alert%281%29)');

    await _tapLink(tester, 'Visit Example', label: 'Example');

    expect(opener.opened, isEmpty);
    expect(opener.rejected, hasLength(1));
  });
}

Future<void> _pumpBody(
  WidgetTester tester,
  RecordingSystemUrlOpener opener,
  String markdown,
) async {
  final lightIdeTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'CodeFont',
  );
  final darkIdeTheme = buildIdeThemeData(
    brightness: Brightness.dark,
    codeFontFamily: 'CodeFont',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[recordingSystemUrlOpenerOverride(opener)],
      child: IdeThemeScope(
        themeMode: ThemeMode.dark,
        lightTheme: lightIdeTheme,
        darkTheme: darkIdeTheme,
        child: MaterialApp(
          theme: buildMaterialTheme(darkIdeTheme),
          home: Scaffold(body: AgentRawMarkdownBody(data: markdown)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 按渲染坐标点中链接文字：markdown 的链接是 span 上的 recognizer，
/// 直接 `tap(find.text(...))` 会落在整行而不是链接区间上。
Future<void> _tapLink(
  WidgetTester tester,
  String plainText, {
  required String label,
}) async {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is RichText && widget.text.toPlainText().contains(plainText),
  );
  final richText = tester.widget<RichText>(finder);
  final renderBox = tester.renderObject<RenderBox>(finder);
  final painter = TextPainter(
    text: richText.text,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: renderBox.size.width);
  final start = plainText.indexOf(label);
  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + label.length),
  );

  await tester.tapAt(renderBox.localToGlobal(boxes.first.toRect().center));
  await tester.pump();
}
