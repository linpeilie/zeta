import 'dart:async';
import 'dart:io';

import 'package:agent_management_client/agent_management_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  test('runner appends launcher arguments and caps malformed output', () async {
    String? executable;
    List<String>? arguments;
    Map<String, String>? environment;
    final handle = FakeProcessHandle(
      code: 3,
      stdoutBytes: <int>[...'abcdef'.codeUnits, 0xFF],
      stderrBytes: 'warning'.codeUnits,
    );
    final runner = processRunnerFor(
      handle,
      onStart: (seenExecutable, seenArguments, seenEnvironment) {
        executable = seenExecutable;
        arguments = seenArguments;
        environment = seenEnvironment;
      },
    );
    final result = await runner.run(
      ResolvedCliProcessCommand(
        executable: 'launcher',
        arguments: const <String>['prefix'],
        displayPath: 'provider',
      ),
      const <String>['--version'],
      maxOutputCharacters: 4,
      environment: const <String, String>{'SAFE': 'value'},
    );

    expect(executable, 'launcher');
    expect(arguments, <String>['prefix', '--version']);
    expect(environment, <String, String>{'SAFE': 'value'});
    expect(result.exitCode, 3);
    expect(result.succeeded, isFalse);
    expect(result.stdout, 'abcd');
    expect(result.stderr, 'warn');
    expect(result.combinedOutput, 'abcd\nwarn');
    expect(result.elapsed, isNot(Duration.zero));
  });

  test(
    'runner accepts an output cap of zero and successful empty output',
    () async {
      final result =
          await processRunnerFor(
            FakeProcessHandle.text(stdout: 'ignored', stderr: 'ignored'),
          ).run(
            ResolvedCliProcessCommand(
              executable: 'fixture',
              arguments: const [],
            ),
            const <String>[],
            maxOutputCharacters: 0,
          );

      expect(result.succeeded, isTrue);
      expect(result.stdout, isEmpty);
      expect(result.stderr, isEmpty);
      expect(result.combinedOutput, isEmpty);
    },
  );

  test('runner rejects negative output caps before process startup', () async {
    await expectLater(
      processRunnerFor(FakeProcessHandle.text()).run(
        ResolvedCliProcessCommand(executable: 'fixture', arguments: const []),
        const <String>[],
        maxOutputCharacters: -1,
      ),
      throwsArgumentError,
    );
  });

  test('runner kills a timed-out injected process', () async {
    final handle = FakeProcessHandle(neverExits: true);

    await expectLater(
      processRunnerFor(handle).run(
        ResolvedCliProcessCommand(executable: 'fixture', arguments: const []),
        const <String>[],
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(handle.killed, isTrue);
  });

  test(
    'default runner executes and terminates real disposable processes',
    () async {
      final shellCommand = ResolvedCliProcessCommand(
        executable: Platform.isWindows ? 'cmd.exe' : '/bin/sh',
        arguments: Platform.isWindows
            ? const <String>['/c']
            : const <String>['-c'],
      );
      final version = await const CliProcessRunner().run(
        shellCommand,
        const <String>['echo Dart'],
      );
      expect(version.succeeded, isTrue);
      expect(version.combinedOutput.toLowerCase(), contains('dart'));

      final waitCommand = Platform.isWindows
          ? 'ping -n 6 127.0.0.1 > nul'
          : 'sleep 5';
      await expectLater(
        const CliProcessRunner().run(
          shellCommand,
          <String>[waitCommand],
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
}
