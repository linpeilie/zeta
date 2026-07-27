import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/layout/ide_constraint_bucket_builder.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('同 bucket 连续改宽时 builder 只调用 1 次且 State 保持', (tester) async {
    var builderCalls = 0;
    await pumpIdeComponent(
      tester,
      size: const Size(800, 600),
      child: IdeConstraintBucketBuilder<String>(
        selectBucket: _widthBucket,
        builder: (context, bucket) {
          builderCalls += 1;
          return _BucketProbe(label: bucket);
        },
      ),
    );

    expect(builderCalls, 1);
    expect(find.text('regular'), findsOneWidget);
    final probeState = tester.state<_BucketProbeState>(
      find.byType(_BucketProbe),
    );
    expect(probeState.mountCount, 1);

    for (var width = 800; width >= 700; width -= 1) {
      await tester.binding.setSurfaceSize(Size(width.toDouble(), 600));
      await tester.pump();
    }

    expect(builderCalls, 1);
    expect(
      tester.state<_BucketProbeState>(find.byType(_BucketProbe)),
      same(probeState),
    );
    expect(probeState.mountCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨 breakpoint 时 builder 仅再调用 1 次且 State 保持', (tester) async {
    var builderCalls = 0;
    await pumpIdeComponent(
      tester,
      size: const Size(800, 600),
      child: IdeConstraintBucketBuilder<String>(
        selectBucket: _widthBucket,
        builder: (context, bucket) {
          builderCalls += 1;
          return _BucketProbe(label: bucket);
        },
      ),
    );

    final probeState = tester.state<_BucketProbeState>(
      find.byType(_BucketProbe),
    );
    expect(builderCalls, 1);
    expect(find.text('regular'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(639, 600));
    await tester.pump();

    expect(builderCalls, 2);
    expect(find.text('compact'), findsOneWidget);
    expect(
      tester.state<_BucketProbeState>(find.byType(_BucketProbe)),
      same(probeState),
    );
    expect(probeState.mountCount, 1);

    await tester.binding.setSurfaceSize(const Size(640, 600));
    await tester.pump();

    expect(builderCalls, 3);
    expect(find.text('regular'), findsOneWidget);
    expect(
      tester.state<_BucketProbeState>(find.byType(_BucketProbe)),
      same(probeState),
    );
    expect(probeState.mountCount, 1);
  });

  testWidgets('仅高度变化且 selectBucket 不依赖高度时不重建', (tester) async {
    var builderCalls = 0;
    await pumpIdeComponent(
      tester,
      size: const Size(800, 600),
      child: IdeConstraintBucketBuilder<String>(
        selectBucket: _widthBucket,
        builder: (context, bucket) {
          builderCalls += 1;
          return _BucketProbe(label: bucket);
        },
      ),
    );
    expect(builderCalls, 1);

    for (var height = 600; height <= 720; height += 4) {
      await tester.binding.setSurfaceSize(Size(800, height.toDouble()));
      await tester.pump();
    }

    expect(builderCalls, 1);
  });

  testWidgets('父配置变化会失效缓存并重建 child 内容', (tester) async {
    var builderCalls = 0;
    var labelPrefix = 'A';
    late StateSetter setHostState;

    await pumpIdeComponent(
      tester,
      size: const Size(800, 600),
      child: StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return IdeConstraintBucketBuilder<String>(
            selectBucket: _widthBucket,
            builder: (context, bucket) {
              builderCalls += 1;
              return Text('$labelPrefix-$bucket');
            },
          );
        },
      ),
    );

    expect(builderCalls, 1);
    expect(find.text('A-regular'), findsOneWidget);

    setHostState(() {
      labelPrefix = 'B';
    });
    await tester.pump();

    expect(builderCalls, 2);
    expect(find.text('B-regular'), findsOneWidget);
    expect(find.text('A-regular'), findsNothing);
  });

  testWidgets('主题变化时 child 仍能响应 InheritedWidget', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(800, 600),
      themeMode: ThemeMode.dark,
      child: IdeConstraintBucketBuilder<String>(
        selectBucket: _widthBucket,
        builder: (context, bucket) {
          final brightness = Theme.of(context).brightness;
          return Text('theme-${brightness.name}-$bucket');
        },
      ),
    );

    expect(find.text('theme-dark-regular'), findsOneWidget);

    await pumpIdeComponent(
      tester,
      size: const Size(800, 600),
      themeMode: ThemeMode.light,
      child: IdeConstraintBucketBuilder<String>(
        selectBucket: _widthBucket,
        builder: (context, bucket) {
          final brightness = Theme.of(context).brightness;
          return Text('theme-${brightness.name}-$bucket');
        },
      ),
    );

    expect(find.text('theme-light-regular'), findsOneWidget);
  });

  testWidgets('文字缩放变化时 child 仍能响应 MediaQuery', (tester) async {
    var textScale = 1.0;
    late StateSetter setHostState;
    var builderCalls = 0;

    await pumpIdeComponent(
      tester,
      size: const Size(800, 600),
      child: StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: IdeConstraintBucketBuilder<String>(
              selectBucket: _widthBucket,
              builder: (context, bucket) {
                builderCalls += 1;
                final scale = MediaQuery.textScalerOf(context).scale(1);
                return Text('scale-$scale-$bucket');
              },
            ),
          );
        },
      ),
    );

    expect(builderCalls, 1);
    expect(find.text('scale-1.0-regular'), findsOneWidget);

    // 父级 StatefulBuilder 重建会 didUpdateWidget 失效缓存并重建 child；
    // 断言缩放后的文案正确，且不因 bucket 缓存卡在旧 MediaQuery。
    setHostState(() {
      textScale = 1.5;
    });
    await tester.pump();

    expect(find.text('scale-1.5-regular'), findsOneWidget);
    expect(find.text('scale-1.0-regular'), findsNothing);
    expect(builderCalls, 2);
  });
}

String _widthBucket(BoxConstraints constraints) {
  return constraints.maxWidth < 640 ? 'compact' : 'regular';
}

class _BucketProbe extends StatefulWidget {
  const _BucketProbe({required this.label});

  final String label;

  @override
  State<_BucketProbe> createState() => _BucketProbeState();
}

class _BucketProbeState extends State<_BucketProbe> {
  int mountCount = 0;

  @override
  void initState() {
    super.initState();
    mountCount += 1;
  }

  @override
  Widget build(BuildContext context) {
    return Text(widget.label);
  }
}
