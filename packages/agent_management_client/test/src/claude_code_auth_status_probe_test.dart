import 'dart:async';
import 'dart:io';

import 'package:agent_management_client/agent_management_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  group('decodeClaudeCodeAuthStatus', () {
    test('rejects empty, malformed, scalar, and missing login state', () {
      expect(decodeClaudeCodeAuthStatus(''), isNull);
      expect(decodeClaudeCodeAuthStatus('{'), isNull);
      expect(decodeClaudeCodeAuthStatus('[]'), isNull);
      expect(decodeClaudeCodeAuthStatus('{"authMethod":"api_key"}'), isNull);
    });

    test('keeps only trimmed whitelisted fields', () {
      final snapshot = decodeClaudeCodeAuthStatus('''
{"loggedIn":true,"authMethod":" api_key ","apiProvider":7,
 "subscriptionType":" ","email":"secret@example.com","token":"secret"}
''');

      expect(snapshot?.loggedIn, isTrue);
      expect(snapshot?.authMethod, 'api_key');
      expect(snapshot?.apiProvider, isNull);
      expect(snapshot?.subscriptionType, isNull);
    });
  });

  test(
    'probe returns null when locator or command evidence is unreliable',
    () async {
      final missing = ClaudeCodeAuthStatusProbe(
        locate: (_) async => null,
        processRunner: processRunnerFor(FakeProcessHandle.text()),
      );
      final locatorFailure = ClaudeCodeAuthStatusProbe(
        locate: (_) async => throw StateError('locator'),
        processRunner: processRunnerFor(FakeProcessHandle.text()),
      );
      final badExit = _probeFor(FakeProcessHandle.text(code: 2, stdout: '{}'));

      expect(
        await missing.probe(AgentProviderConfig.defaultClaudeCode),
        isNull,
      );
      expect(
        await locatorFailure.probe(AgentProviderConfig.defaultClaudeCode),
        isNull,
      );
      expect(
        await badExit.probeCommand(_command, const <String, String>{}),
        isNull,
      );
    },
  );

  test('probe accepts logged-in exit zero and logged-out exit one', () async {
    final loggedIn = _probeFor(
      FakeProcessHandle.text(
        stdout: '{"loggedIn":true,"authMethod":"oauth_token"}',
      ),
    );
    final loggedOut = _probeFor(
      FakeProcessHandle.text(code: 1, stdout: '{"loggedIn":false}'),
    );

    expect(
      (await loggedIn.probe(AgentProviderConfig.defaultClaudeCode))?.loggedIn,
      isTrue,
    );
    expect(
      (await loggedOut.probeCommand(
        _command,
        const <String, String>{},
      ))?.loggedIn,
      isFalse,
    );
  });

  test(
    'probe contains timeout, process, filesystem, and unknown failures',
    () async {
      final failures = <Exception>[
        TimeoutException('fixture'),
        const ProcessException('claude', <String>[]),
        const FileSystemException('fixture'),
      ];
      for (final failure in failures) {
        final probe = ClaudeCodeAuthStatusProbe(
          locate: (_) async => _command,
          processRunner: CliProcessRunner(
            starter: (_, _, {environment}) async => throw failure,
          ),
        );
        expect(
          await probe.probeCommand(_command, const <String, String>{}),
          isNull,
        );
      }

      final probe = ClaudeCodeAuthStatusProbe(
        locate: (_) async => _command,
        processRunner: CliProcessRunner(
          starter: (_, _, {environment}) async => throw StateError('fixture'),
        ),
      );
      expect(
        await probe.probeCommand(_command, const <String, String>{}),
        isNull,
      );
    },
  );

  test('account adapter maps every whitelisted auth label', () async {
    final cases = <(String, String)>[
      (
        '{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"pro"}',
        'Claude Pro',
      ),
      (
        '{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"max"}',
        'Claude Max',
      ),
      (
        '{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"team"}',
        'Claude Team',
      ),
      (
        '{"loggedIn":true,"authMethod":"claude.ai",'
            '"subscriptionType":"enterprise"}',
        'Claude Enterprise',
      ),
      ('{"loggedIn":true,"authMethod":"claude.ai"}', 'Claude.ai'),
      ('{"loggedIn":true,"authMethod":"api_key"}', 'API key'),
      ('{"loggedIn":true,"authMethod":"api_key_helper"}', 'API key helper'),
      ('{"loggedIn":true,"authMethod":"oauth_token"}', 'OAuth token'),
      ('{"loggedIn":true,"authMethod":"unknown"}', 'Authenticated'),
      (
        '{"loggedIn":true,"authMethod":"third_party","apiProvider":"bedrock"}',
        'Amazon Bedrock',
      ),
      (
        '{"loggedIn":true,"authMethod":"third_party","apiProvider":"vertex"}',
        'Google Vertex AI',
      ),
      (
        '{"loggedIn":true,"authMethod":"third_party","apiProvider":"foundry"}',
        'Microsoft Foundry',
      ),
      (
        '{"loggedIn":true,"authMethod":"third_party","apiProvider":"gemini"}',
        'Gemini',
      ),
      (
        '{"loggedIn":true,"authMethod":"third_party","apiProvider":"grok"}',
        'Grok',
      ),
      (
        '{"loggedIn":true,"authMethod":"third_party","apiProvider":"openai"}',
        'OpenAI',
      ),
      ('{"loggedIn":true,"authMethod":"third_party"}', 'Third-party provider'),
    ];
    for (final (payload, label) in cases) {
      final result = await _probeFor(
        FakeProcessHandle.text(stdout: payload),
      ).accountProbe(_command, const <String, String>{});
      expect(result.status, AgentAccountStatus.loggedIn);
      expect(result.label, label);
    }

    final loggedOut = await _probeFor(
      FakeProcessHandle.text(code: 1, stdout: '{"loggedIn":false}'),
    ).accountProbe(_command, const <String, String>{});
    final unavailable = await _probeFor(
      FakeProcessHandle.text(code: 2),
    ).accountProbe(_command, const <String, String>{});
    expect(loggedOut.status, AgentAccountStatus.loggedOut);
    expect(loggedOut.label, isNull);
    expect(unavailable.status, AgentAccountStatus.unavailable);
  });
}

ClaudeCodeAuthStatusProbe _probeFor(FakeProcessHandle handle) {
  return ClaudeCodeAuthStatusProbe(
    locate: (_) async => _command,
    processRunner: processRunnerFor(handle),
  );
}

final _command = ResolvedCliProcessCommand(
  executable: 'claude',
  arguments: const <String>[],
  displayPath: 'claude',
);
