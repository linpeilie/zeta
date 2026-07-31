import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_build_counter.dart';

void main() {
  testWidgets('restores the previous rebuild callback on dispose', (
    tester,
  ) async {
    final previous = debugOnRebuildDirtyWidget;
    final counter = TestWidgetBuildCounter(
      runtimeTypes: const <String>{'_BuildProbe'},
    );

    counter.start();
    expect(debugOnRebuildDirtyWidget, isNot(same(previous)));

    await tester.pumpWidget(const _BuildProbe());
    expect(counter.snapshot()['_BuildProbe'], greaterThan(0));

    counter.dispose();
    expect(debugOnRebuildDirtyWidget, same(previous));
  });
}

class _BuildProbe extends StatelessWidget {
  const _BuildProbe();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
