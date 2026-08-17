import 'package:flutter_test/flutter_test.dart';

import '../../tool/report_test_timings.dart';

void main() {
  test('parses suite load, test durations, results, and damaged lines', () {
    final report = TestTimingReport.parse(const <String>[
      '{"suite":{"id":0,"path":"/repo/test/a_test.dart"},'
          '"type":"suite","time":0}',
      '{"test":{"id":1,"name":"loading /repo/test/a_test.dart",'
          '"suiteID":0,"metadata":{"skip":false},"line":null},'
          '"type":"testStart","time":0}',
      'not-json',
      '{"testID":1,"result":"success","skipped":false,'
          '"type":"testDone","time":1200}',
      '{"test":{"id":4,"name":"group (setUpAll)","suiteID":0,'
          '"metadata":{"skip":false},"line":9},'
          '"type":"testStart","time":1200}',
      '{"testID":4,"result":"success","skipped":false,'
          '"type":"testDone","time":1210}',
      '{"test":{"id":2,"name":"fast case","suiteID":0,'
          '"metadata":{"skip":false},"line":10},'
          '"type":"testStart","time":1210}',
      '{"testID":2,"result":"success","skipped":false,'
          '"type":"testDone","time":1260}',
      '{"test":{"id":3,"name":"failed case","suiteID":0,'
          '"metadata":{"skip":false},"line":20},'
          '"type":"testStart","time":1260}',
      '{"testID":3,"result":"failure","skipped":false,'
          '"type":"testDone","time":1460}',
      '{"success":false,"type":"done","time":1500}',
    ]);

    expect(report.totalMilliseconds, 1500);
    expect(report.successCount, 1);
    expect(report.failureCount, 1);
    expect(report.skippedCount, 0);
    expect(report.suites.single.overheadMilliseconds, 1210);
    expect(report.suites.single.milliseconds, 1460);
    expect(report.tests.map((entry) => entry.name), <String>[
      'failed case',
      'fast case',
    ]);
    expect(report.render(limit: 1), contains('Slowest suites'));
    expect(report.render(limit: 1), contains('failed case'));
  });
}
