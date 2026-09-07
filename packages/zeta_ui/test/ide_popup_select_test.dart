import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  testWidgets('选择后关闭弹层并恢复触发器焦点', (tester) async {
    String? value = 'fast';
    late StateSetter update;
    await _pumpSelect(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return _TestSelect(
            value: value,
            onChanged: (next) {
              setState(() => value = next);
            },
          );
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('trigger')));
    await tester.pump();
    expect(find.byType(sf.SelectPopup<String>), findsOneWidget);
    expect(find.byType(IdePopoverPanel), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('option-smart')));
    await tester.pump();
    await tester.pump();

    expect(value, 'smart');
    expect(find.byType(sf.SelectPopup<String>), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'test-popup-select-trigger',
    );

    // 避免局部变量只写告警，也验证外部值更新仍可正常重建。
    update(() => value = 'fast');
    await tester.pump();
    expect(find.text('Fast'), findsOneWidget);
  });

  testWidgets('Esc 关闭弹层并恢复触发器焦点', (tester) async {
    await _pumpSelect(
      tester,
      const _TestSelect(value: 'fast', onChanged: _ignoreSelection),
    );

    await tester.tap(find.byKey(const ValueKey('trigger')));
    await tester.pump();
    expect(find.byType(sf.SelectPopup<String>), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();

    expect(find.byType(sf.SelectPopup<String>), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'test-popup-select-trigger',
    );
  });

  testWidgets('选项被清空时关闭已打开的弹层', (tester) async {
    var items = _items;
    late StateSetter update;
    await _pumpSelect(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return _TestSelect(
            value: 'fast',
            items: items,
            onChanged: _ignoreSelection,
          );
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('trigger')));
    await tester.pump();
    expect(find.byType(sf.SelectPopup<String>), findsOneWidget);

    update(() => items = const <IdePopupSelectItem<String>>[]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(sf.SelectPopup<String>), findsNothing);
  });
}

const _items = <IdePopupSelectItem<String>>[
  IdePopupSelectItem<String>(value: 'fast', label: 'Fast'),
  IdePopupSelectItem<String>(
    value: 'smart',
    label: 'Smart',
    key: ValueKey('option-smart'),
  ),
];

class _TestSelect extends StatelessWidget {
  const _TestSelect({
    required this.value,
    required this.onChanged,
    this.items = _items,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final List<IdePopupSelectItem<String>> items;

  @override
  Widget build(BuildContext context) {
    return IdePopupSelect<String>(
      value: value,
      placeholder: 'Model',
      items: items,
      tooltip: 'Choose model',
      focusNodeDebugLabel: 'test-popup-select-trigger',
      onChanged: onChanged,
      triggerBuilder:
          (
            context, {
            required label,
            required isOpen,
            required enabled,
            required focusNode,
            required onPressed,
          }) => IdeTab(
            key: const ValueKey('trigger'),
            label: label,
            selected: isOpen,
            enabled: enabled,
            focusNode: focusNode,
            onPressed: onPressed,
          ),
      itemBuilder: (context, item, {required selected}) => Text(item.label),
    );
  }
}

void _ignoreSelection(String _) {}

Future<void> _pumpSelect(WidgetTester tester, Widget child) async {
  final lightTheme = buildIdeThemeData(brightness: Brightness.light);
  final darkTheme = buildIdeThemeData(brightness: Brightness.dark);
  await tester.pumpWidget(
    IdeThemeScope(
      themeMode: ThemeMode.dark,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      child: sf.ShadcnApp(
        theme: buildShadcnTheme(lightTheme),
        darkTheme: buildShadcnTheme(darkTheme),
        themeMode: sf.ThemeMode.dark,
        home: sf.Scaffold(
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              disableAnimations: true,
            ),
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    ),
  );
}
