import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'diagnostic command emits only safe metadata and never refreshes',
    () async {
      const token = 'synthetic-diagnostic-secret';
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['tool/diagnose_credentials.dart'],
        environment: {'CLAUDE_CODE_OAUTH_TOKEN': token, 'CI': 'true'},
        includeParentEnvironment: false,
      );
      expect(result.exitCode, 0);
      expect(result.stdout, isNot(contains(token)));
      expect(result.stderr, isNot(contains(token)));
      expect(jsonDecode(result.stdout as String), {
        'mode': 'readOnly',
        'refreshAttempted': false,
        'status': 'available',
        'source': 'environment',
        'expiry': 'unknown',
        'refreshTokenPresent': false,
        'preflight': 'notChecked',
      });
    },
  );

  test('invalid diagnostic arguments are not echoed', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['tool/diagnose_credentials.dart', 'synthetic-secret'],
      environment: const {'CI': 'true'},
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 64);
    expect(result.stdout, isNot(contains('synthetic-secret')));
    expect(result.stderr, isNot(contains('synthetic-secret')));
  });
}
