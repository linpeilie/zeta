import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File(
    'tool/packaging/sync_release_to_develop.sh',
  ).absolute.path.replaceAll('\\', '/');
  late Directory temp;
  late String repo;
  late String origin;
  late String release;

  String git(List<String> args, {String? cwd}) {
    final result = Process.runSync('git', args, workingDirectory: cwd ?? repo);
    expect(result.exitCode, 0, reason: '${args.join(' ')}\n${result.stderr}');
    return '${result.stdout}'.trim();
  }

  String commit(String file, String contents) {
    File('$repo/$file').writeAsStringSync(contents);
    git(['add', file]);
    git(['commit', '-m', contents]);
    return git(['rev-parse', 'HEAD']);
  }

  ProcessResult sync({String? sha}) => Process.runSync(
    'bash',
    [script, 'v1.0.0', sha ?? release],
    workingDirectory: repo,
    environment: {
      'GITHUB_STEP_SUMMARY': '${temp.path}/summary.md'.replaceAll('\\', '/'),
    },
  );

  String remote(String branch) =>
      git(['--git-dir=$origin', 'rev-parse', 'refs/heads/$branch']);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('zeta-release-sync-');
    repo = Directory('${temp.path}/checkout').path;
    origin = '${temp.path}/origin.git';
    Directory(repo).createSync();
    git(['init', '--bare', origin]);
    git(['init', '--initial-branch=main']);
    git(['config', 'user.name', 'Release test']);
    git(['config', 'user.email', 'release@example.invalid']);
    git(['config', 'commit.gpgsign', 'false']);
    git(['config', 'core.autocrlf', 'false']);
    git(['remote', 'add', 'origin', origin]);
    commit('shared.txt', 'base');
    git(['branch', 'develop']);
    release = commit('shared.txt', 'release');
    git(['tag', 'v1.0.0']);
    git(['push', 'origin', 'main', 'develop', 'refs/tags/v1.0.0']);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('fast forwards develop and reruns without adding commits', () {
    final first = sync();
    expect(first.exitCode, 0, reason: '${first.stderr}');
    expect(remote('develop'), release);
    expect(sync().exitCode, 0);
    expect(remote('develop'), remote('main'));
  });

  test('preserves divergent develop commits with a real merge', () {
    git(['checkout', 'develop']);
    final development = commit('feature.txt', 'new feature');
    git(['push', 'origin', 'develop']);
    final result = sync();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final merged = remote('develop');
    expect(git(['show', '-s', '--format=%P', merged]), '$development $release');
    expect(git(['show', '$merged:feature.txt']), 'new feature');
    expect(sync().exitCode, 0);
    expect(remote('develop'), merged);
  });

  test('conflicts leave published refs and develop unchanged', () {
    git(['checkout', 'develop']);
    final development = commit('shared.txt', 'conflicting development');
    git(['push', 'origin', 'develop']);
    expect(sync().exitCode, isNot(0));
    expect(remote('develop'), development);
    expect(remote('main'), release);
    expect(git(['rev-parse', 'v1.0.0']), release);
    expect(File('$repo/.git/MERGE_HEAD').existsSync(), isFalse);
  });

  test('rejects a tag pointing at a different commit', () {
    final before = remote('develop');
    expect(sync(sha: before).exitCode, isNot(0));
    expect(remote('develop'), before);
  });

  test('rejects a release outside main history', () {
    final before = remote('develop');
    git(['--git-dir=$origin', 'update-ref', 'refs/heads/main', before]);
    expect(sync().exitCode, isNot(0));
    expect(remote('develop'), before);
  });

  test('push rejection reports failure without changing develop', () {
    File('$repo/.git/hooks/pre-push').writeAsStringSync('#!/bin/sh\nexit 1\n');
    Process.runSync('bash', [
      '-c',
      'chmod +x .git/hooks/pre-push',
    ], workingDirectory: repo);
    final before = remote('develop');
    final result = sync();
    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('Push rejected'));
    expect(remote('develop'), before);
  });

  test('retries a racing develop update and preserves its commit', () {
    git(['checkout', 'develop']);
    final racing = commit('race.txt', 'concurrent feature');
    git(['push', 'origin', 'HEAD:refs/heads/race']);
    final quotedOrigin = origin
        .replaceAll('\\', '/')
        .replaceAll("'", "'\"'\"'");
    File('$repo/.git/hooks/pre-push').writeAsStringSync(
      '#!/bin/sh\n'
      'if [ ! -f .git/race-done ]; then\n'
      "  git --git-dir='$quotedOrigin' update-ref refs/heads/develop $racing\n"
      '  touch .git/race-done\n'
      'fi\n',
    );
    Process.runSync('bash', [
      '-c',
      'chmod +x .git/hooks/pre-push',
    ], workingDirectory: repo);
    final result = sync();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      git(['show', '-s', '--format=%P', remote('develop')]),
      '$racing $release',
    );
  });
}
