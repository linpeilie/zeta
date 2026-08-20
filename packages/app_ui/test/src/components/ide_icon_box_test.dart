import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('IdeIconBox', () {
    testWidgets('aligns an icon to the typography line box', (tester) async {
      await tester.pumpShadcnApp(
        const IdeIconBox(
          Icons.refresh,
          size: 64,
          color: Colors.red,
          key: ValueKey<String>('icon-box'),
        ),
      );

      final context = tester.element(find.byType(IdeIconBox));
      final expected = context.appMetrics.controlIconBoxFor(
        context.appTypography.bodySmall,
      );
      expect(tester.getSize(find.byType(IdeIconBox)), Size.square(expected));
      expect(tester.widget<Icon>(find.byIcon(Icons.refresh)).size, expected);
      expect(tester.widget<Icon>(find.byIcon(Icons.refresh)).color, Colors.red);
    });

    testWidgets('centers custom content using an explicit style', (
      tester,
    ) async {
      const style = TextStyle(fontSize: 20, height: 1.5);
      await tester.pumpShadcnApp(
        const IdeIconBox.custom(
          style: style,
          child: Text('C'),
        ),
      );

      expect(tester.getSize(find.byType(IdeIconBox)), const Size.square(30));
      expect(find.text('C'), findsOneWidget);
    });
  });
}
