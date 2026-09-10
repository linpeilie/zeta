import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_markdown/src/render/chip_text.dart';
import 'package:zeta_markdown/src/render/markdown_document_view.dart';
import 'package:zeta_markdown/src/selection/selection_host.dart';
import 'package:zeta_markdown/zeta_markdown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('standalone MarkdownWidget does not install SelectionArea', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: 'Hello world'),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsNothing);
    expect(find.byType(MarkdownSelectionHost), findsOneWidget);
  });

  testWidgets('joins ancestor SelectionArea and skips custom host', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: MarkdownWidget(data: 'Hello world'),
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownDocumentView), findsOneWidget);
    expect(find.byType(MarkdownSelectionHost), findsNothing);
    expect(find.byType(MarkdownNativeSelectionBlock), findsWidgets);
  });

  testWidgets('inline code is a chip span under SelectionArea', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: MarkdownWidget(data: 'before `code` after'),
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownChipText), findsOneWidget);
    final chip = tester.widget<MarkdownChipText>(find.byType(MarkdownChipText));
    var foundChip = false;
    chip.span.visitChildren((span) {
      if (span is MarkdownChipSpan && span.text == 'code') {
        foundChip = true;
        return false;
      }
      return true;
    });
    expect(foundChip, isTrue);
  });

  testWidgets('SelectionArea copy shortcut writes selected markdown', (
    tester,
  ) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final arguments = methodCall.arguments as Map<Object?, Object?>;
        copiedText = arguments['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: MarkdownWidget(data: 'Hello world'),
          ),
        ),
      ),
    );

    final textFinder = find.textContaining('Hello world', findRichText: true);
    expect(textFinder, findsOneWidget);
    final start = tester.getTopLeft(textFinder) + const Offset(4, 8);
    final end = tester.getBottomRight(textFinder) - const Offset(4, 4);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copiedText, isNotNull);
    expect(copiedText, contains('Hello'));
  });

  testWidgets('list markers stay out of native copied text', (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final arguments = methodCall.arguments as Map<Object?, Object?>;
        copiedText = arguments['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: MarkdownWidget(data: '- alpha\n- beta'),
          ),
        ),
      ),
    );

    final first = tester.getTopLeft(
      find.textContaining('alpha', findRichText: true),
    );
    final last = tester.getBottomRight(
      find.textContaining('beta', findRichText: true),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: first + const Offset(4, 8));
    await gesture.down(first + const Offset(4, 8));
    await tester.pump();
    await gesture.moveTo(last - const Offset(4, 4));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copiedText, isNotNull);
    expect(copiedText, contains('alpha'));
    expect(copiedText, isNot(contains('•')));
  });

  testWidgets('isolated nested scrollables still copy and do not assert', (
    tester,
  ) async {
    FlutterErrorDetails? flutterError;
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterError = details;
      previousOnError?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = previousOnError;
    });

    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final arguments = methodCall.arguments as Map<Object?, Object?>;
        copiedText = arguments['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const body = 'Selectable phrase here';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 160,
            child: SelectionArea(
              child: MarkdownSelectionScrollIsolation(
                child: ListView(
                  children: [
                    MarkdownSelectionScrollRestore(
                      child: MarkdownWidget(
                        data:
                            '```\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n```\n\n$body',
                        useColumn: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final textFinder =
        find.textContaining('Selectable phrase', findRichText: true);
    expect(textFinder, findsOneWidget);
    final start = tester.getTopLeft(textFinder) + const Offset(4, 6);
    final end = tester.getBottomRight(textFinder) - const Offset(4, 4);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(flutterError, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copiedText, contains('Selectable'));
  });
}
