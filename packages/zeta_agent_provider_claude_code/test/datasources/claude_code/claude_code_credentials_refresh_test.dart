import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code_testing.dart';

final _now = DateTime.utc(2026, 9, 5);
String _json({
  DateTime? expiry,
  String token = 'synthetic-old',
  String? refresh = 'synthetic-refresh',
  List<String> scopes = const ['user:inference', 'user:profile'],
}) => jsonEncode({
  'otherAccount': {'preserve': true},
  'claudeAiOauth': {
    'accessToken': token,
    'refreshToken': refresh,
    'expiresAt': (expiry ?? _now).millisecondsSinceEpoch,
    'scopes': scopes,
    'subscriptionType': 'max',
    'rateLimitTier': 'tier',
    'unknown': [1, 2],
  },
});
ClaudeCodeOAuthCredentials _next() => ClaudeCodeOAuthCredentials(
  accessToken: 'synthetic-new',
  refreshToken: 'synthetic-rotated',
  expiresAt: _now.add(const Duration(hours: 1)),
  scopes: ['user:inference', 'user:profile'],
);
Matcher _failure(ClaudeCodeCredentialRefreshFailure failure) =>
    isA<ClaudeCodeCredentialRefreshException>().having(
      (e) => e.failure,
      'failure',
      failure,
    );

void main() {
  late Directory directory;
  late File file;
  late _Refresh client;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zeta-oauth-fixture-');
    file = File('${directory.path}/.credentials.json');
    await file.writeAsString(_json());
    client = _Refresh(() async => _next());
  });
  tearDown(() async {
    await directory.delete(recursive: true);
    final lock = Directory('${directory.path}.lock');
    if (await lock.exists()) await lock.delete(recursive: true);
  });
  LocalClaudeCodeCredentialsService service({
    ClaudeCodeCredentialsPlatform platform =
        ClaudeCodeCredentialsPlatform.linux,
    _Secure? secure,
    ClaudeCodeCredentialRefreshCoordinator? coordinator,
    ClaudeCodeCredentialLock? lock,
    Map<String, String> environment = const {},
  }) => LocalClaudeCodeCredentialsService(
    environment: environment,
    platform: platform,
    credentialsPath: file.path,
    secureSource: secure ?? _Secure(null),
    refreshClient: client,
    refreshCoordinator: coordinator,
    refreshLock: lock,
    clock: () => _now,
  );

  for (final platform in ClaudeCodeCredentialsPlatform.values) {
    test(
      '${platform.name}: refreshes selected source and preserves unknown fields',
      () async {
        final secure = _Secure(
          platform == ClaudeCodeCredentialsPlatform.macOS ? _json() : null,
        );
        final reader = service(platform: platform, secure: secure);
        final before = await file.readAsString();
        expect((await reader.read()).credentials!.accessToken, 'synthetic-old');
        expect(client.calls, 0); // read remains side-effect free.
        final result = await reader.ensureFresh();
        expect(result.credentials!.accessToken, 'synthetic-new');
        expect(result.credentials!.refreshToken, 'synthetic-rotated');
        expect(result.credentials!.expiresAt, _next().expiresAt);
        expect(client.calls, 1);
        final stored =
            jsonDecode(
                  platform == ClaudeCodeCredentialsPlatform.macOS
                      ? secure.contents!
                      : await file.readAsString(),
                )
                as Map;
        expect(stored['otherAccount'], {'preserve': true});
        expect(stored['claudeAiOauth']['unknown'], [1, 2]);
        expect(stored['claudeAiOauth']['subscriptionType'], 'max');
        expect(stored['claudeAiOauth']['rateLimitTier'], 'tier');
        if (platform == ClaudeCodeCredentialsPlatform.macOS) {
          expect(await file.readAsString(), before);
          expect(secure.writes, 1);
        }
        await reader.ensureFresh();
        expect(client.calls, 1);
        expect(await Directory('${directory.path}.lock').exists(), isFalse);
      },
    );
  }

  test(
    'preflight failure reports that the remote refresh was not attempted',
    () async {
      final secure = _Secure(_json())
        ..preflightFailure = const ClaudeCodeSecureCredentialsWriteException(
          ClaudeCodeCredentialPersistenceStage.preflight,
          ClaudeCodeCredentialPersistenceReason.payloadTooLarge,
        );
      await expectLater(
        service(
          platform: ClaudeCodeCredentialsPlatform.macOS,
          secure: secure,
        ).ensureFresh(),
        throwsA(
          isA<ClaudeCodeCredentialRefreshException>()
              .having(
                (e) => e.source,
                'source',
                ClaudeCodeCredentialsSource.keychain,
              )
              .having(
                (e) => e.persistenceStage,
                'stage',
                ClaudeCodeCredentialPersistenceStage.preflight,
              )
              .having(
                (e) => e.persistenceReason,
                'reason',
                ClaudeCodeCredentialPersistenceReason.payloadTooLarge,
              )
              .having((e) => e.refreshCompleted, 'refreshCompleted', false),
        ),
      );
      expect(client.calls, 0);
      expect(secure.writes, 0);
    },
  );

  test(
    'write diagnostics retain the stage and remote progress, never secrets',
    () async {
      final secure = _Secure(_json())
        ..writeFailure = const ClaudeCodeSecureCredentialsWriteException(
          ClaudeCodeCredentialPersistenceStage.write,
          ClaudeCodeCredentialPersistenceReason.interactionNotAllowed,
          exitCode: 1,
        );
      await expectLater(
        service(
          platform: ClaudeCodeCredentialsPlatform.macOS,
          secure: secure,
        ).ensureFresh(),
        throwsA(
          isA<ClaudeCodeCredentialRefreshException>().having(
            (e) => e.toString(),
            'diagnostics',
            'ClaudeCodeCredentialRefreshException(persistence, source=keychain, stage=write, reason=interactionNotAllowed, refreshCompleted=true, exitCode=1)',
          ),
        ),
      );
      expect(client.calls, 1);
    },
  );

  test('final verification failures have their own stage', () async {
    final secure = _Secure(_json())..dropWrite = true;
    await expectLater(
      service(
        platform: ClaudeCodeCredentialsPlatform.macOS,
        secure: secure,
      ).ensureFresh(),
      throwsA(
        isA<ClaudeCodeCredentialRefreshException>()
            .having(
              (e) => e.persistenceStage,
              'stage',
              ClaudeCodeCredentialPersistenceStage.verify,
            )
            .having(
              (e) => e.persistenceReason,
              'reason',
              ClaudeCodeCredentialPersistenceReason.readbackMismatch,
            )
            .having((e) => e.refreshCompleted, 'refreshCompleted', true),
      ),
    );
  });

  for (final platform in ClaudeCodeCredentialsPlatform.values) {
    test(
      '${platform.name}: readback uses persisted millisecond expiry precision',
      () async {
        final preciseExpiry = _now.add(
          const Duration(hours: 1, microseconds: 731),
        );
        client = _Refresh(
          () async => ClaudeCodeOAuthCredentials(
            accessToken: 'synthetic-new',
            refreshToken: 'synthetic-rotated',
            expiresAt: preciseExpiry,
            scopes: ['user:inference', 'user:profile'],
          ),
        );
        final secure = _Secure(
          platform == ClaudeCodeCredentialsPlatform.macOS ? _json() : null,
        );
        final reader = service(platform: platform, secure: secure);
        final result = await reader.ensureFresh();
        await reader.ensureFresh();
        expect(
          result.credentials!.expiresAt,
          DateTime.fromMillisecondsSinceEpoch(
            preciseExpiry.millisecondsSinceEpoch,
            isUtc: true,
          ),
        );
        expect(result.credentials!.accessToken, 'synthetic-new');
        expect(result.credentials!.refreshToken, 'synthetic-rotated');
        expect(client.calls, 1);
      },
    );
  }

  test(
    'a real one-millisecond expiry mismatch still fails verification',
    () async {
      final secure = _Secure(_json())..offsetExpiry = true;
      await expectLater(
        service(
          platform: ClaudeCodeCredentialsPlatform.macOS,
          secure: secure,
        ).ensureFresh(),
        throwsA(
          isA<ClaudeCodeCredentialRefreshException>().having(
            (e) => e.persistenceReason,
            'reason',
            ClaudeCodeCredentialPersistenceReason.readbackMismatch,
          ),
        ),
      );
    },
  );

  test('five-minute boundary refreshes, six minutes does not', () async {
    await file.writeAsString(
      _json(expiry: _now.add(const Duration(minutes: 6))),
    );
    await service().ensureFresh();
    expect(client.calls, 0);
    await file.writeAsString(
      _json(expiry: _now.add(const Duration(minutes: 5))),
    );
    await service().ensureFresh();
    expect(client.calls, 1);
  });

  test(
    'external authentication and unknown expiry do not borrow refresh tokens',
    () async {
      for (final env in [
        {'ANTHROPIC_API_KEY': 'synthetic-key'},
        {'CLAUDE_CODE_OAUTH_TOKEN': 'synthetic-env'},
      ]) {
        await service(environment: env).ensureFresh();
      }
      final data = jsonDecode(_json()) as Map;
      data['claudeAiOauth'].remove('expiresAt');
      await file.writeAsString(jsonEncode(data));
      await service().ensureFresh();
      expect(client.calls, 0);
    },
  );

  test(
    'missing, malformed and non-refreshable snapshots are distinct',
    () async {
      await file.delete();
      expect(
        (await service().ensureFresh()).status,
        ClaudeCodeCredentialsStatus.missing,
      );
      for (final raw in [
        '{invalid',
        _json(refresh: null),
        _json(scopes: ['user:profile']),
      ]) {
        await file.writeAsString(raw);
        await expectLater(
          service().ensureFresh(),
          throwsA(_failure(ClaudeCodeCredentialRefreshFailure.unavailable)),
        );
        expect(await file.readAsString(), raw);
      }
      expect(client.calls, 0);
    },
  );

  for (final flag in ['USE_LOCAL_OAUTH', 'USE_STAGING_OAUTH']) {
    test('padded $flag issuer flag cannot reach production', () async {
      await expectLater(
        service(environment: {'USER_TYPE': 'ant', flag: ' YES '}).ensureFresh(),
        throwsA(_failure(ClaudeCodeCredentialRefreshFailure.unsupportedIssuer)),
      );
      expect(client.calls, 0);
    });
  }

  test('custom issuer cannot send a token to production', () async {
    await expectLater(
      service(
        environment: {
          'CLAUDE_CODE_CUSTOM_OAUTH_URL': 'https://fixture.invalid',
        },
      ).ensureFresh(),
      throwsA(_failure(ClaudeCodeCredentialRefreshFailure.unsupportedIssuer)),
    );
    expect(client.calls, 0);
  });

  test('rereads after acquiring lock and adopts a CLI rotation', () async {
    final lock = _Lock(
      before: () => file.writeAsString(
        _json(expiry: _next().expiresAt, token: 'cli-new'),
      ),
    );
    expect(
      (await service(lock: lock).ensureFresh()).credentials!.accessToken,
      'cli-new',
    );
    expect(client.calls, 0);
  });

  test(
    'concurrent runtimes share one refresh and subsequent calls reread',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      client = _Refresh(() async {
        started.complete();
        await release.future;
        return _next();
      });
      final coordinator = ClaudeCodeCredentialRefreshCoordinator();
      final a = service(coordinator: coordinator);
      final b = service(coordinator: coordinator);
      final pending = Future.wait(
        List.generate(12, (i) => (i.isEven ? a : b).ensureFresh()),
      );
      await started.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.calls, 1);
      release.complete();
      final results = await pending;
      expect(
        results.every((r) => r.credentials!.accessToken == 'synthetic-new'),
        isTrue,
      );
      await file.writeAsString(
        _json(expiry: _next().expiresAt, token: 'external-account'),
      );
      expect(
        (await a.ensureFresh()).credentials!.accessToken,
        'external-account',
      );
    },
  );

  test(
    'separate coordinators serialize through the CLI-compatible lock',
    () async {
      client = _Refresh(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return _next();
      });
      await Future.wait([service().ensureFresh(), service().ensureFresh()]);
      expect(client.calls, 1);
    },
  );

  test(
    'refresh failure is sanitized, preserves storage and releases lock',
    () async {
      final original = await file.readAsString();
      client = _Refresh(
        () async => throw StateError('synthetic-secret HTTP body'),
      );
      await expectLater(
        service().ensureFresh(),
        throwsA(_failure(ClaudeCodeCredentialRefreshFailure.unavailable)),
      );
      expect(await file.readAsString(), original);
      expect(await Directory('${directory.path}.lock').exists(), isFalse);
      client = _Refresh(() async => _next());
      await service().ensureFresh();
      expect(client.calls, 1);
    },
  );

  test('external login during HTTP is never overwritten', () async {
    final external = _json(token: 'external-login', expiry: _next().expiresAt);
    client = _Refresh(() async {
      await file.writeAsString(external);
      return _next();
    });
    await expectLater(
      service().ensureFresh(),
      throwsA(_failure(ClaudeCodeCredentialRefreshFailure.sourceChanged)),
    );
    expect(await file.readAsString(), external);
  });

  test(
    'a corrupt or denied Keychain primary cannot rotate a fallback file',
    () async {
      for (final secure in [
        _Secure('invalid'),
        _Secure(null)..denyRead = true,
      ]) {
        await expectLater(
          service(
            platform: ClaudeCodeCredentialsPlatform.macOS,
            secure: secure,
          ).ensureFresh(),
          throwsA(_failure(ClaudeCodeCredentialRefreshFailure.sourceChanged)),
        );
      }
      expect(client.calls, 0);
    },
  );

  test(
    'Keychain write denial and false success fail closed without file fallback',
    () async {
      final original = await file.readAsString();
      for (final fail in [true, false]) {
        final secure = _Secure(_json())
          ..denyWrite = fail
          ..dropWrite = !fail;
        await expectLater(
          service(
            platform: ClaudeCodeCredentialsPlatform.macOS,
            secure: secure,
          ).ensureFresh(),
          throwsA(_failure(ClaudeCodeCredentialRefreshFailure.persistence)),
        );
        expect(await file.readAsString(), original);
      }
    },
  );

  test(
    'missing Keychain primary refreshes the existing fallback file only',
    () async {
      final secure = _Secure(null);
      await service(
        platform: ClaudeCodeCredentialsPlatform.macOS,
        secure: secure,
      ).ensureFresh();
      expect(secure.writes, 0);
      expect(
        jsonDecode(await file.readAsString())['claudeAiOauth']['accessToken'],
        'synthetic-new',
      );
    },
  );

  test('lost lock prevents writeback after remote rotation', () async {
    final original = await file.readAsString();
    final lock = _Lock();
    client = _Refresh(() async {
      lock.lost = true;
      return _next();
    });
    await expectLater(
      service(lock: lock).ensureFresh(),
      throwsA(_failure(ClaudeCodeCredentialRefreshFailure.lockLost)),
    );
    expect(await file.readAsString(), original);
  });

  test('existing lock is never stolen and wait is bounded', () async {
    await Directory('${directory.path}.lock').create();
    await expectLater(
      service(
        lock: const DirectoryClaudeCodeCredentialLock(waitLimit: Duration.zero),
      ).ensureFresh(),
      throwsA(_failure(ClaudeCodeCredentialRefreshFailure.lockUnavailable)),
    );
    expect(client.calls, 0);
    expect(await Directory('${directory.path}.lock').exists(), isTrue);
  });

  test(
    'native directory heartbeat survives beyond the initial lease period',
    () async {
      await const DirectoryClaudeCodeCredentialLock().run(directory.path, (
        validate,
      ) async {
        final initial = (await Directory(
          '${directory.path}.lock',
        ).stat()).modified;
        await Future<void>.delayed(const Duration(milliseconds: 2400));
        await validate();
        expect(
          (await Directory(
            '${directory.path}.lock',
          ).stat()).modified.isAfter(initial),
          isTrue,
        );
      });
      expect(await Directory('${directory.path}.lock').exists(), isFalse);
    },
  );

  test(
    'ownership change fails validation and does not delete another lock',
    () async {
      await expectLater(
        const DirectoryClaudeCodeCredentialLock().run(directory.path, (
          validate,
        ) async {
          await Process.run('/usr/bin/touch', [
            '-t',
            '200001010000',
            '${directory.path}.lock',
          ]);
          await validate();
        }),
        throwsA(_failure(ClaudeCodeCredentialRefreshFailure.lockLost)),
      );
      expect(await Directory('${directory.path}.lock').exists(), isTrue);
    },
    skip: Platform.isWindows
        ? 'Directory mtime mutation uses POSIX fixture'
        : false,
  );

  test(
    'file replacement leaves no temporary copy and restricts POSIX access',
    () async {
      await service().ensureFresh();
      expect(await directory.list().length, 1);
      if (!Platform.isWindows) {
        expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
      }
    },
  );

  group('OAuth transport', () {
    test(
      'posts the current refresh token and granted scopes, rotates and closes',
      () async {
        final http = _Http(_response());
        final current = ClaudeCodeOAuthCredentials(
          accessToken: 'synthetic-old',
          refreshToken: 'synthetic-refresh',
          scopes: ['user:inference', 'user:profile'],
        );
        final result = await HttpClaudeCodeOAuthRefreshClient(
          clientFactory: () => http,
          clock: () => _now.add(const Duration(microseconds: 731)),
        ).refresh(current);
        expect(
          http.uri,
          Uri.parse('https://platform.claude.com/v1/oauth/token'),
        );
        expect(jsonDecode(http.request.body), {
          'grant_type': 'refresh_token',
          'refresh_token': 'synthetic-refresh',
          'client_id': '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
          'scope': 'user:inference user:profile',
        });
        expect(http.request.followRedirects, isFalse);
        expect(http.request.headers.contentType?.mimeType, 'application/json');
        expect(result.accessToken, 'synthetic-new');
        expect(result.refreshToken, 'synthetic-rotated');
        expect(result.expiresAt, _now.add(const Duration(hours: 1)));
        expect(result.scopes, ['user:inference']);
        expect(http.closed, isTrue);
      },
    );
    test('omitted rotation and scope preserve the existing values', () async {
      final http = _Http(
        jsonEncode({'access_token': 'synthetic-new', 'expires_in': 3600}),
      );
      final current = ClaudeCodeOAuthCredentials(
        accessToken: 'old',
        refreshToken: 'kept',
        scopes: ['user:inference'],
      );
      final result = await HttpClaudeCodeOAuthRefreshClient(
        clientFactory: () => http,
      ).refresh(current);
      expect(result.refreshToken, 'kept');
      expect(result.scopes, current.scopes);
    });
    for (final status in [400, 401, 403, 429, 500, 302]) {
      test('HTTP $status is sanitized and is not retried', () async {
        final http = _Http('synthetic-secret', status: status);
        await expectLater(
          HttpClaudeCodeOAuthRefreshClient(
            clientFactory: () => http,
          ).refresh(_next()),
          throwsA(
            _failure(
              [400, 401, 403].contains(status)
                  ? ClaudeCodeCredentialRefreshFailure.rejected
                  : ClaudeCodeCredentialRefreshFailure.transport,
            ),
          ),
        );
        expect(http.calls, 1);
        expect(http.closed, isTrue);
      });
    }
    for (final body in [
      'invalid',
      '[]',
      '{}',
      _response(seconds: 0),
      _response(seconds: -1),
      _response(seconds: 1.5),
      _response(seconds: '3600'),
      _response(seconds: 31536001),
      jsonEncode({'access_token': '', 'expires_in': 3600}),
      'x' * 65537,
    ]) {
      test(
        'invalid response ${body.length > 100 ? 'oversize' : body} fails closed',
        () async {
          final http = _Http(body);
          await expectLater(
            HttpClaudeCodeOAuthRefreshClient(
              clientFactory: () => http,
            ).refresh(_next()),
            throwsA(
              _failure(ClaudeCodeCredentialRefreshFailure.invalidResponse),
            ),
          );
          expect(http.closed, isTrue);
        },
      );
    }
  });
}

String _response({Object seconds = 3600}) => jsonEncode({
  'access_token': 'synthetic-new',
  'refresh_token': 'synthetic-rotated',
  'expires_in': seconds,
  'scope': 'user:inference',
});

final class _Refresh implements ClaudeCodeOAuthRefreshClient {
  _Refresh(this.callback);
  final Future<ClaudeCodeOAuthCredentials> Function() callback;
  int calls = 0;
  @override
  Future<ClaudeCodeOAuthCredentials> refresh(
    ClaudeCodeOAuthCredentials current,
  ) {
    calls++;
    return callback();
  }
}

final class _Secure
    implements
        ClaudeCodeSecureCredentialsSource,
        ClaudeCodeSecureCredentialsWriter {
  _Secure(this.contents);
  String? contents;
  bool denyRead = false,
      denyWrite = false,
      dropWrite = false,
      offsetExpiry = false;
  int writes = 0;
  ClaudeCodeSecureCredentialsWriteException? preflightFailure, writeFailure;
  @override
  Future<String?> read() async {
    if (denyRead) throw StateError('synthetic-private-error');
    return contents;
  }

  @override
  void validateWrite(String value) {
    if (preflightFailure != null) throw preflightFailure!;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    if (writeFailure != null) throw writeFailure!;
    if (denyWrite) throw StateError('synthetic-private-error');
    if (!dropWrite) {
      if (offsetExpiry) {
        final decoded = jsonDecode(value) as Map;
        decoded['claudeAiOauth']['expiresAt'] =
            (decoded['claudeAiOauth']['expiresAt'] as int) + 1;
        contents = jsonEncode(decoded);
      } else {
        contents = value;
      }
    }
  }
}

final class _Lock implements ClaudeCodeCredentialLock {
  _Lock({this.before});
  final Future<Object?> Function()? before;
  bool lost = false;
  @override
  Future<T> run<T>(
    String directory,
    Future<T> Function(Future<void> Function()) operation,
  ) async {
    await before?.call();
    return operation(() async {
      if (lost) {
        throw const ClaudeCodeCredentialRefreshException(
          ClaudeCodeCredentialRefreshFailure.lockLost,
        );
      }
    });
  }
}

final class _Http extends _Fake implements HttpClient {
  _Http(String body, {int status = 200})
    : request = _Request(_Response(body, status));
  final _Request request;
  Uri? uri;
  bool closed = false;
  int calls = 0;
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    calls++;
    uri = url;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = force;
  }
}

final class _Request extends _Fake implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final headers = _Headers();
  @override
  bool followRedirects = true;
  String body = '';
  @override
  void write(Object? object) {
    body += '$object';
  }

  @override
  Future<HttpClientResponse> close() async => response;
}

final class _Headers extends _Fake implements HttpHeaders {
  @override
  ContentType? contentType;
}

final class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.body, this.statusCode);
  final String body;
  @override
  final int statusCode;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
