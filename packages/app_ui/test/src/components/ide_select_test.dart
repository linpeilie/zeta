import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import '../../helpers/helpers.dart';

void main() {
  testWidgets('IdeSelect renders the selected option and expand icon', (
    tester,
  ) async {
    int? selected;
    await tester.pumpShadcnApp(
      IdeSelect<int>(
        value: 2,
        width: 160,
        popupMinWidth: 180,
        popupMaxHeight: 200,
        options: const <IdeSelectOption<int>>[
          IdeSelectOption<int>(1, 'One'),
          IdeSelectOption<int>(2, 'Two'),
        ],
        onChanged: (value) => selected = value,
      ),
    );

    expect(find.text('Two'), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    await tester.tap(find.byType(sf.Select<int>));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('One'), findsOneWidget);
    await tester.tap(find.text('One').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(selected, 1);
  });

  testWidgets('IdeSelect covers disabled and unmatched values', (tester) async {
    await tester.pumpShadcnApp(
      const IdeSelect<int>(
        value: 99,
        width: 0,
        controlSize: AppControlSize.compact,
        popupWidthPolicy: IdeSelectPopupWidthPolicy.fitContent,
        placeholder: 'Choose',
        enabled: false,
        options: <IdeSelectOption<int>>[
          IdeSelectOption<int>(1, 'Disabled option', enabled: false),
        ],
        onChanged: null,
      ),
    );

    expect(find.text('Disabled option'), findsOneWidget);

    await tester.pumpShadcnApp(
      const IdeSelect<int>(
        value: 99,
        placeholder: 'Choose',
        options: <IdeSelectOption<int>>[],
        onChanged: null,
      ),
    );
    expect(find.text('Choose'), findsOneWidget);
  });

  testWidgets('IdeSelect validates popup width', (tester) async {
    expect(
      () => IdeSelect<int>(
        value: 1,
        options: const <IdeSelectOption<int>>[],
        onChanged: null,
        popupMinWidth: -1,
      ),
      throwsAssertionError,
    );
  });
}
