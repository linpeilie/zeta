import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 阶段 0 可观测性隐私守卫。
///
/// 探针的价值在于「永远只记录白名单」。这里用源码级断言固定三件事：
///
/// 1. Riverpod 观察器不得触碰 provider 的 state 正文或 family 参数（G7）；
/// 2. 指标采集实现只能由 `lib/src/app/observability` 组合，业务层只见端口；
/// 3. 指标白名单只能在 [ZetaMetric] 里扩展，调用点不得自造自由文本指标名。
void main() {
  final observerSource = File(
    'lib/src/app/observability/zeta_provider_observer.dart',
  ).readAsStringSync();

  test('Riverpod 观察器不读取 state 正文与 family 参数', () {
    const forbidden = <String>[
      r'$newValue',
      r'$previousValue',
      r'$value',
      'newValue.toString()',
      'previousValue.toString()',
      'value.toString()',
      'provider.argument',
      'container.read',
    ];

    for (final token in forbidden) {
      expect(
        observerSource,
        isNot(contains(token)),
        reason: '观察器出现了会泄漏 provider 状态的写法：$token',
      );
    }
  });

  test('观察器只把 provider 名与结果分类交给指标端口', () {
    // 观察器允许出现的标签来源：声明期的 name 与实现类型名。
    expect(observerSource, contains('provider.name'));
    expect(observerSource, contains('provider.runtimeType'));
    expect(observerSource, isNot(contains('jsonEncode')));
    expect(observerSource, isNot(contains('loggerFor')));
  });

  test('采集实现只在 app 组合层被构造', () {
    final offenders = <String>[];
    for (final file in <File>[
      ..._dartFilesUnder('lib'),
      ..._dartFilesUnder('packages'),
    ]) {
      final path = _posix(file.path);
      // 只看生产源码：Package 自己的测试当然可以构造采集实现。
      final isProductionSource =
          path.startsWith('lib/') || path.contains('/lib/');
      if (!isProductionSource ||
          path.startsWith('lib/src/app/observability/') ||
          path.startsWith('packages/zeta_foundation/')) {
        continue;
      }
      final source = file.readAsStringSync();
      if (source.contains('InMemoryZetaMetricsPort(')) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '业务代码只能依赖 ZetaMetricsPort 端口，采集实现由 app 注入：\n'
          '${offenders.join('\n')}',
    );
  });

  test('指标调用点不接受自由文本指标名', () {
    final offenders = <String>[];
    for (final file in _dartFilesUnder('lib')) {
      final path = _posix(file.path);
      final source = file.readAsStringSync();
      for (final match in _metricCallPattern.allMatches(source)) {
        final argument = match.group(2)!.trim();
        // 允许 `ZetaMetric.xxx` 常量，或已经声明为 ZetaMetric 类型的变量；
        // 只要出现字符串字面量或插值，就说明有人绕开了白名单。
        if (!argument.contains("'") && !argument.contains(r'$')) {
          continue;
        }
        offenders.add('$path: ${match.group(1)}($argument …)');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '指标名必须来自 ZetaMetric 枚举：\n${offenders.join('\n')}',
    );
  });

  test('ZetaMetricLabel.constant 只接受源码字面量', () {
    final offenders = <String>[];
    for (final file in <File>[
      ..._dartFilesUnder('lib'),
      ..._dartFilesUnder('packages'),
    ]) {
      final path = _posix(file.path);
      if (!path.startsWith('lib/') && !path.contains('/lib/')) {
        continue;
      }
      // 声明自身（`const ZetaMetricLabel.constant(this.value)`）不是调用点。
      if (path.endsWith('zeta_metric_label.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      for (final match in _constantLabelPattern.allMatches(source)) {
        // 去掉 dart format 可能补上的尾逗号后再判定。
        final argument = match.group(1)!.trim().replaceFirst(RegExp(r',$'), '');
        // 字面量常量是唯一被允许的形态；变量必须走 declaredIdentifier / hashed。
        if (RegExp(r"^'[^'$]*'$").hasMatch(argument)) {
          continue;
        }
        final line = source.substring(0, match.start).split('\n').length;
        offenders.add('$path:$line ZetaMetricLabel.constant($argument)');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'constant 入口代表"这个值写死在源码里"。运行期取值请用 '
          'ZetaMetricLabel.declaredIdentifier 或 .hashed：\n${offenders.join('\n')}',
    );
  });

  test('指标标签维度不接受裸 String', () {
    final tagsSource = File(
      'packages/zeta_foundation/lib/src/observability/zeta_metric.dart',
    ).readAsStringSync();

    expect(tagsSource, contains('final ZetaMetricLabel? providerId'));
    expect(tagsSource, contains('final ZetaMetricLabel? component'));
    expect(tagsSource, isNot(contains('String? providerId')));
    expect(tagsSource, isNot(contains('String? component')));
  });

  test('指标端口签名不接受 String 指标名', () {
    final portSource = File(
      'packages/zeta_foundation/lib/src/observability/zeta_metrics_port.dart',
    ).readAsStringSync();

    expect(portSource, contains('void record(ZetaMetricSample sample)'));
    expect(portSource, isNot(contains('String metric')));
    expect(portSource, isNot(contains('String name')));
  });

  test('指标枚举与端口不引入日志或序列化依赖', () {
    for (final file in _dartFilesUnder(
      'packages/zeta_foundation/lib/src/observability',
    )) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('print(')));
      expect(source, isNot(contains('jsonEncode')));
      expect(source, isNot(contains('loggerFor')));
    }
  });
}

Iterable<File> _dartFilesUnder(String directory) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

final RegExp _constantLabelPattern = RegExp(
  r'ZetaMetricLabel\.constant\(\s*([^)]*)\)',
);

final RegExp _metricCallPattern = RegExp(
  r'\.(counter|gauge|duration)\(\s*([^,)\n]+)',
);

String _posix(String path) => path.replaceAll(r'\', '/');
