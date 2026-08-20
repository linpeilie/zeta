import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 单次滚动基线采样；只依赖 Flutter 测试树，不依赖业务 Provider。
@immutable
final class ScrollMetricsSample {
  const ScrollMetricsSample({
    required this.label,
    required this.step,
    required this.pixels,
    required this.maxScrollExtent,
    required this.viewportDimension,
    required this.extentBefore,
    required this.extentAfter,
    required this.firstVisibleItemId,
    required this.firstVisibleItemTop,
    required this.builtChildCount,
    required this.visibleChildCount,
    this.trackedAnchorId,
    this.trackedAnchorTop,
  });

  final String label;
  final int step;
  final double pixels;
  final double maxScrollExtent;
  final double viewportDimension;
  final double extentBefore;
  final double extentAfter;
  final String? firstVisibleItemId;
  final double? firstVisibleItemTop;
  final int builtChildCount;
  final int visibleChildCount;
  final String? trackedAnchorId;
  final double? trackedAnchorTop;

  double get normalizedOffset =>
      maxScrollExtent <= 0 ? 0 : pixels / maxScrollExtent;

  double get endDistance => maxScrollExtent - pixels;

  @override
  String toString() {
    return 'label=$label step=$step '
        'pixels=${pixels.toStringAsFixed(3)} '
        'max=${maxScrollExtent.toStringAsFixed(3)} '
        'viewport=${viewportDimension.toStringAsFixed(3)} '
        'before=${extentBefore.toStringAsFixed(3)} '
        'after=${extentAfter.toStringAsFixed(3)} '
        'normalized=${normalizedOffset.toStringAsFixed(6)} '
        'anchor=${firstVisibleItemId ?? '-'} '
        'anchorTop=${firstVisibleItemTop?.toStringAsFixed(3) ?? '-'} '
        'tracked=${trackedAnchorId ?? '-'} '
        'trackedTop=${trackedAnchorTop?.toStringAsFixed(3) ?? '-'} '
        'built=$builtChildCount visible=$visibleChildCount';
  }
}

/// 收集有序样本，并只在显式打开诊断开关时输出完整 trace。
final class ScrollMetricsTrace {
  ScrollMetricsTrace(this.scenario);

  static const bool diagnosticsEnabled = bool.fromEnvironment(
    'ZETA_SCROLL_BASELINE_DIAGNOSTICS',
  );
  static const String diagnosticTracePath = String.fromEnvironment(
    'ZETA_SCROLL_BASELINE_TRACE_PATH',
  );

  final String scenario;
  final List<ScrollMetricsSample> samples = <ScrollMetricsSample>[];

  ScrollMetricsSample capture(
    WidgetTester tester, {
    required String label,
    required Finder scrollView,
    required String itemKeyPrefix,
    Key? trackedItemKey,
  }) {
    final sample = captureScrollMetrics(
      tester,
      label: label,
      step: samples.length,
      scrollView: scrollView,
      itemKeyPrefix: itemKeyPrefix,
      trackedItemKey: trackedItemKey,
    );
    samples.add(sample);
    if (diagnosticsEnabled) {
      developer.log(sample.toString(), name: 'zeta.scroll.baseline.$scenario');
      if (diagnosticTracePath.isNotEmpty) {
        File(diagnosticTracePath).writeAsStringSync(
          '$scenario $sample\n',
          mode: FileMode.append,
        );
      }
    }
    return sample;
  }
}

ScrollMetricsSample captureScrollMetrics(
  WidgetTester tester, {
  required String label,
  required int step,
  required Finder scrollView,
  required String itemKeyPrefix,
  Key? trackedItemKey,
}) {
  final scrollable = find.descendant(
    of: scrollView,
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable.first).position;
  final viewportRect = tester.getRect(scrollView);
  final candidates = _keyedRenderBoxes(
    itemKeyPrefix: itemKeyPrefix,
    viewportRect: viewportRect,
  );
  final visible =
      candidates
          .where(
            (candidate) =>
                candidate.rect.bottom > viewportRect.top + 0.5 &&
                candidate.rect.top < viewportRect.bottom - 0.5,
          )
          .toList(growable: false)
        ..sort((left, right) => left.rect.top.compareTo(right.rect.top));
  final firstVisible = visible.isEmpty ? null : visible.first;
  final trackedFinder = trackedItemKey == null
      ? null
      : find.byKey(trackedItemKey, skipOffstage: false);
  final trackedTop = trackedFinder == null || trackedFinder.evaluate().isEmpty
      ? null
      : tester.getRect(trackedFinder).top - viewportRect.top;
  final trackedId = switch (trackedItemKey) {
    ValueKey<String>(:final value) when value.startsWith(itemKeyPrefix) =>
      value.substring(itemKeyPrefix.length),
    _ => null,
  };

  return ScrollMetricsSample(
    label: label,
    step: step,
    pixels: position.pixels,
    maxScrollExtent: position.maxScrollExtent,
    viewportDimension: position.viewportDimension,
    extentBefore: position.extentBefore,
    extentAfter: position.extentAfter,
    firstVisibleItemId: firstVisible?.id,
    firstVisibleItemTop: firstVisible == null
        ? null
        : firstVisible.rect.top - viewportRect.top,
    builtChildCount: candidates.length,
    visibleChildCount: visible.length,
    trackedAnchorId: trackedId,
    trackedAnchorTop: trackedTop,
  );
}

double itemViewportTop(
  WidgetTester tester, {
  required Finder scrollView,
  required Key itemKey,
}) {
  final viewportTop = tester.getRect(scrollView).top;
  return tester.getRect(find.byKey(itemKey)).top - viewportTop;
}

List<_KeyedRenderBox> _keyedRenderBoxes({
  required String itemKeyPrefix,
  required Rect viewportRect,
}) {
  final keyed = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith(itemKeyPrefix);
  }, skipOffstage: false);
  final byId = <String, _KeyedRenderBox>{};
  for (final element in keyed.evaluate()) {
    final key = element.widget.key! as ValueKey<String>;
    final renderObject = element.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      continue;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    if (!rect.isFinite || rect.width <= 0 || rect.height < 0) {
      continue;
    }
    byId[key.value] = _KeyedRenderBox(
      id: key.value.substring(itemKeyPrefix.length),
      rect: rect,
    );
  }
  return byId.values.toList(growable: false);
}

final class _KeyedRenderBox {
  const _KeyedRenderBox({required this.id, required this.rect});

  final String id;
  final Rect rect;
}
