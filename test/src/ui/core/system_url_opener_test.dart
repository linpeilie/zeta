import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/ui/core/system_url_opener.dart';

import '../../testing/recording_system_url_opener.dart';

void main() {
  group('外链白名单', () {
    test('http / https 受理', () {
      for (final url in <String>[
        'https://example.com',
        'http://example.com/a/b?c=d#e',
        'HTTPS://Example.COM/大小写与中文',
        '  https://example.com/前后空白  ',
      ]) {
        expect(isOpenableExternalUrl(url), isTrue, reason: url);
      }
    });

    test('其余 scheme 一律拒绝（fail-closed）', () {
      for (final url in <String>[
        'javascript:alert(1)',
        'file:///etc/passwd',
        'ftp://example.com/a',
        'data:text/html,<script>alert(1)</script>',
        'mailto:a@example.com',
        'vbscript:msgbox(1)',
        'zeta://open',
      ]) {
        expect(isOpenableExternalUrl(url), isFalse, reason: url);
      }
    });

    test('无 scheme 或无 host 都拒绝', () {
      for (final url in <String>[
        '',
        '   ',
        'example.com',
        '/usr/local/bin',
        './相对路径.md',
        '#anchor',
        'https:',
        'http:///no-host',
      ]) {
        expect(isOpenableExternalUrl(url), isFalse, reason: url);
      }
    });
  });

  group('记录型打开器', () {
    test('受理的进 opened，拒绝的进 rejected 且回报 false', () async {
      final opener = RecordingSystemUrlOpener();

      expect(await opener.openUrl('  https://example.com/a  '), isTrue);
      expect(await opener.openUrl('javascript:alert(1)'), isFalse);

      expect(opener.opened, <String>['https://example.com/a']);
      expect(opener.rejected, <String>['javascript:alert(1)']);
    });
  });
}
