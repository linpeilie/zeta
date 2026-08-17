import 'dart:convert';
import 'dart:io';

const int _defaultLimit = 20;

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/report_test_timings.dart <report.json> [limit]',
    );
    exitCode = 64;
    return;
  }

  final limit = arguments.length == 2
      ? int.tryParse(arguments[1])
      : _defaultLimit;
  if (limit == null || limit <= 0) {
    stderr.writeln('limit must be a positive integer');
    exitCode = 64;
    return;
  }

  final reportFile = File(arguments.first);
  if (!await reportFile.exists()) {
    stderr.writeln('Test report does not exist: ${reportFile.path}');
    exitCode = 66;
    return;
  }

  final report = await TestTimingReport.fromFile(reportFile);
  stdout.write(report.render(limit: limit));
}

/// `package:test` JSON reporter 的耗时摘要。
final class TestTimingReport {
  TestTimingReport({
    required this.totalMilliseconds,
    required this.tests,
    required this.suites,
    required this.successCount,
    required this.failureCount,
    required this.skippedCount,
  });

  final int totalMilliseconds;
  final List<TestTimingEntry> tests;
  final List<SuiteTimingEntry> suites;
  final int successCount;
  final int failureCount;
  final int skippedCount;

  static Future<TestTimingReport> fromFile(File file) async {
    return parse(await file.readAsLines());
  }

  /// 解析逐行 JSON 事件；损坏的单行按宽容策略忽略。
  static TestTimingReport parse(Iterable<String> lines) {
    final suitePaths = <int, String>{};
    final runningTests = <int, _RunningTest>{};
    final tests = <TestTimingEntry>[];
    final suiteAccumulators = <int, _SuiteAccumulator>{};
    var totalMilliseconds = 0;
    var successCount = 0;
    var failureCount = 0;
    var skippedCount = 0;

    for (final line in lines) {
      Map<String, Object?> event;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, Object?>) {
          continue;
        }
        event = decoded;
      } on FormatException {
        continue;
      }

      final time = event['time'];
      if (time is int && time > totalMilliseconds) {
        totalMilliseconds = time;
      }

      switch (event['type']) {
        case 'suite':
          final suite = event['suite'];
          if (suite is Map<String, Object?> &&
              suite['id'] is int &&
              suite['path'] is String) {
            suitePaths[suite['id']! as int] = suite['path']! as String;
          }
          break;
        case 'testStart':
          final test = event['test'];
          if (test is Map<String, Object?> &&
              test['id'] is int &&
              test['suiteID'] is int &&
              test['name'] is String &&
              time is int) {
            final metadata = test['metadata'];
            final name = test['name']! as String;
            runningTests[test['id']! as int] = _RunningTest(
              suiteId: test['suiteID']! as int,
              name: name,
              startedAtMilliseconds: time,
              hidden:
                  test['line'] == null ||
                  name.endsWith('(setUpAll)') ||
                  name.endsWith('(tearDownAll)'),
              skipped:
                  metadata is Map<String, Object?> && metadata['skip'] == true,
            );
          }
          break;
        case 'testDone':
          final testId = event['testID'];
          if (testId is! int || time is! int) {
            continue;
          }
          final running = runningTests.remove(testId);
          if (running == null) {
            continue;
          }
          final duration = time - running.startedAtMilliseconds;
          final suite = suiteAccumulators.putIfAbsent(
            running.suiteId,
            _SuiteAccumulator.new,
          );
          suite.totalMilliseconds += duration;
          if (running.hidden) {
            suite.overheadMilliseconds += duration;
            continue;
          }

          suite.testCount += 1;
          final skipped = running.skipped || event['skipped'] == true;
          if (skipped) {
            skippedCount += 1;
          } else if (event['result'] == 'success') {
            successCount += 1;
          } else {
            failureCount += 1;
          }
          tests.add(
            TestTimingEntry(
              suitePath:
                  suitePaths[running.suiteId] ?? 'suite-${running.suiteId}',
              name: running.name,
              milliseconds: duration,
              skipped: skipped,
            ),
          );
          break;
      }
    }

    final suites =
        suiteAccumulators.entries
            .map(
              (entry) => SuiteTimingEntry(
                path: suitePaths[entry.key] ?? 'suite-${entry.key}',
                milliseconds: entry.value.totalMilliseconds,
                overheadMilliseconds: entry.value.overheadMilliseconds,
                testCount: entry.value.testCount,
              ),
            )
            .toList()
          ..sort(
            (left, right) => right.milliseconds.compareTo(left.milliseconds),
          );
    tests.sort(
      (left, right) => right.milliseconds.compareTo(left.milliseconds),
    );

    return TestTimingReport(
      totalMilliseconds: totalMilliseconds,
      tests: tests,
      suites: suites,
      successCount: successCount,
      failureCount: failureCount,
      skippedCount: skippedCount,
    );
  }

  String render({int limit = _defaultLimit}) {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('Test timing summary')
      ..writeln(
        'total=${_formatDuration(totalMilliseconds)} '
        'passed=$successCount failed=$failureCount skipped=$skippedCount',
      )
      ..writeln()
      ..writeln('Slowest suites');
    for (final (index, suite) in suites.take(limit).indexed) {
      buffer.writeln(
        '${index + 1}. ${_formatDuration(suite.milliseconds).padLeft(8)} '
        '${_relativePath(suite.path)} '
        '(overhead ${_formatDuration(suite.overheadMilliseconds)}, '
        '${suite.testCount} tests)',
      );
    }
    buffer
      ..writeln()
      ..writeln('Slowest tests');
    for (final (index, test)
        in tests.where((entry) => !entry.skipped).take(limit).indexed) {
      buffer.writeln(
        '${index + 1}. ${_formatDuration(test.milliseconds).padLeft(8)} '
        '${_relativePath(test.suitePath)} :: ${test.name}',
      );
    }
    return buffer.toString();
  }
}

final class TestTimingEntry {
  const TestTimingEntry({
    required this.suitePath,
    required this.name,
    required this.milliseconds,
    required this.skipped,
  });

  final String suitePath;
  final String name;
  final int milliseconds;
  final bool skipped;
}

final class SuiteTimingEntry {
  const SuiteTimingEntry({
    required this.path,
    required this.milliseconds,
    required this.overheadMilliseconds,
    required this.testCount,
  });

  final String path;
  final int milliseconds;
  final int overheadMilliseconds;
  final int testCount;
}

final class _RunningTest {
  const _RunningTest({
    required this.suiteId,
    required this.name,
    required this.startedAtMilliseconds,
    required this.hidden,
    required this.skipped,
  });

  final int suiteId;
  final String name;
  final int startedAtMilliseconds;
  final bool hidden;
  final bool skipped;
}

final class _SuiteAccumulator {
  int totalMilliseconds = 0;
  int overheadMilliseconds = 0;
  int testCount = 0;
}

String _formatDuration(int milliseconds) {
  if (milliseconds < 1000) {
    return '${milliseconds}ms';
  }
  return '${(milliseconds / 1000).toStringAsFixed(2)}s';
}

String _relativePath(String path) {
  final normalizedPath = path.replaceAll('\\', '/');
  final normalizedRoot = Directory.current.path.replaceAll('\\', '/');
  if (normalizedPath.startsWith('$normalizedRoot/')) {
    return normalizedPath.substring(normalizedRoot.length + 1);
  }
  return normalizedPath;
}
