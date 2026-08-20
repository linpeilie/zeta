import 'dart:convert';
import 'dart:typed_data';

import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  final image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );

  testWidgets('IdeImageThumbnail renders a non-interactive image', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      IdeImageThumbnail(
        image: image,
        size: 48,
        tooltip: 'View large',
        semanticLabel: 'Preview image',
        unavailableMessage: 'Image unavailable',
        closeSemanticLabel: 'Close preview',
        enablePreview: false,
        borderRadius: BorderRadius.zero,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.low,
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(PaneInteractiveSurface), findsNothing);
  });

  testWidgets('IdeImageThumbnail opens and closes a zoomable preview', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      IdeImageThumbnail(
        image: image,
        size: 64,
        tooltip: 'View large',
        semanticLabel: 'Preview image',
        unavailableMessage: 'Image unavailable',
        closeSemanticLabel: 'Close preview',
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(IdeImageThumbnail));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('IdeImageThumbnail renders default and custom errors', (
    tester,
  ) async {
    final invalid = MemoryImage(Uint8List(0));
    await tester.pumpShadcnApp(
      IdeImageThumbnail(
        image: invalid,
        size: 32,
        tooltip: 'View large',
        semanticLabel: 'Broken image',
        unavailableMessage: 'Image unavailable',
        closeSemanticLabel: 'Close preview',
        enablePreview: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

    await tester.pumpShadcnApp(
      IdeImageThumbnail(
        image: invalid,
        size: 64,
        tooltip: 'View large',
        semanticLabel: 'Broken image',
        unavailableMessage: 'Image unavailable',
        closeSemanticLabel: 'Close preview',
        enablePreview: false,
        error: const Text('Custom error'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Custom error'), findsOneWidget);

    expect(
      () => IdeImageThumbnail(
        image: invalid,
        size: -1,
        tooltip: 'View large',
        semanticLabel: 'Broken image',
        unavailableMessage: 'Image unavailable',
        closeSemanticLabel: 'Close preview',
      ),
      throwsAssertionError,
    );
  });

  testWidgets('showIdeImagePreview renders decode failure copy', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      Builder(
        builder: (context) => IdeButton(
          label: 'Open invalid',
          onPressed: () => showIdeImagePreview(
            context,
            image: MemoryImage(Uint8List(0)),
            semanticLabel: 'Broken image',
            unavailableMessage: 'Image unavailable',
            closeSemanticLabel: 'Close preview',
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open invalid'));
    await tester.pumpAndSettle();
    expect(find.text('Image unavailable'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
  });
}
