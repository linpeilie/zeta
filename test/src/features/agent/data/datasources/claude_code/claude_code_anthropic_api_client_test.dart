import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_anthropic_api_client.dart';

void main() {
  group('ClaudeCodeAnthropicApiClient', () {
    test('subscription OAuth uses Bearer and the oauth beta header', () async {
      final transport = _RecordingHttpClient(
        response: _FakeHttpClientResponse(
          statusCode: HttpStatus.ok,
          body: '{"data":[]}',
        ),
      );
      final client = ClaudeCodeAnthropicApiClient(
        httpClientFactory: () => transport,
      );

      final result = await client.listModels(
        accessToken: 'oauth-sensitive-token',
        isSubscriptionOAuth: true,
      );

      expect(result, <String, Object?>{'data': <Object?>[]});
      expect(transport.requestedUris, <Uri>[
        ClaudeCodeAnthropicApiClient.modelsUri,
      ]);
      expect(
        transport.request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer oauth-sensitive-token',
      );
      expect(
        transport.request.headers.value('anthropic-beta'),
        'oauth-2025-04-20',
      );
      expect(transport.request.headers.value('x-api-key'), isNull);
      expect(
        transport.request.headers.value('anthropic-version'),
        '2023-06-01',
      );
      expect(transport.closedForcefully, isTrue);
    });

    test('API key mode uses x-api-key without any oauth header', () async {
      final transport = _RecordingHttpClient(
        response: _FakeHttpClientResponse(
          statusCode: HttpStatus.ok,
          body: '{"data":[]}',
        ),
      );
      final client = ClaudeCodeAnthropicApiClient(
        httpClientFactory: () => transport,
      );

      await client.listModels(
        accessToken: 'api-key-sensitive-value',
        isSubscriptionOAuth: false,
      );

      expect(
        transport.request.headers.value('x-api-key'),
        'api-key-sensitive-value',
      );
      expect(
        transport.request.headers.value(HttpHeaders.authorizationHeader),
        isNull,
      );
      expect(transport.request.headers.value('anthropic-beta'), isNull);
      expect(transport.closedForcefully, isTrue);
    });

    test(
      'usage quota uses OAuth headers and optional CLI user agent',
      () async {
        final transport = _RecordingHttpClient(
          response: _FakeHttpClientResponse(
            statusCode: HttpStatus.ok,
            body: '{"five_hour":null}',
          ),
        );
        final client = ClaudeCodeAnthropicApiClient(
          httpClientFactory: () => transport,
        );

        await client.readUsageQuota(
          accessToken: 'oauth-sensitive-token',
          claudeCodeVersion: '2.1.227',
        );

        expect(transport.requestedUris, <Uri>[
          ClaudeCodeAnthropicApiClient.usageQuotaUri,
        ]);
        expect(
          transport.request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer oauth-sensitive-token',
        );
        expect(
          transport.request.headers.value('anthropic-beta'),
          'oauth-2025-04-20',
        );
        expect(
          transport.request.headers.value(HttpHeaders.userAgentHeader),
          'claude-code/2.1.227',
        );
        expect(transport.request.headers.value('x-api-key'), isNull);
        expect(transport.closedForcefully, isTrue);
      },
    );

    test('401, 429, and other non-200 responses return null safely', () async {
      for (final statusCode in <int>[
        HttpStatus.unauthorized,
        HttpStatus.tooManyRequests,
        HttpStatus.internalServerError,
      ]) {
        final loggedStatusCodes = <int>[];
        final transport = _RecordingHttpClient(
          response: _FakeHttpClientResponse(
            statusCode: statusCode,
            body: 'sensitive-response-body',
          ),
        );
        final client = ClaudeCodeAnthropicApiClient(
          httpClientFactory: () => transport,
          statusLogger: loggedStatusCodes.add,
        );

        await expectLater(
          client.listModels(
            accessToken: 'sensitive-token',
            isSubscriptionOAuth: true,
          ),
          completion(isNull),
        );

        expect(loggedStatusCodes, <int>[statusCode]);
        expect(transport.response!.listened, isFalse);
        expect(transport.closedForcefully, isTrue);
      }
    });

    test(
      'timeout and network failures return null and close the client',
      () async {
        for (final error in <Object>[
          TimeoutException('redacted'),
          const SocketException('redacted'),
        ]) {
          final transport = _RecordingHttpClient(getUrlError: error);
          final client = ClaudeCodeAnthropicApiClient(
            httpClientFactory: () => transport,
          );

          await expectLater(
            client.listModels(
              accessToken: 'sensitive-token',
              isSubscriptionOAuth: true,
            ),
            completion(isNull),
          );

          expect(transport.closedForcefully, isTrue);
        }
      },
    );

    test('invalid JSON and non-object JSON return null', () async {
      for (final body in <String>['{invalid-json}', '[1,2,3]']) {
        final transport = _RecordingHttpClient(
          response: _FakeHttpClientResponse(
            statusCode: HttpStatus.ok,
            body: body,
          ),
        );
        final client = ClaudeCodeAnthropicApiClient(
          httpClientFactory: () => transport,
        );

        await expectLater(
          client.listModels(
            accessToken: 'sensitive-token',
            isSubscriptionOAuth: true,
          ),
          completion(isNull),
        );

        expect(transport.closedForcefully, isTrue);
      }
    });
  });
}

final class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient({this.response, this.getUrlError});

  final _FakeHttpClientResponse? response;
  final Object? getUrlError;
  final List<Uri> requestedUris = <Uri>[];
  late final _RecordingHttpClientRequest request = _RecordingHttpClientRequest(
    response: response!,
  );
  bool closedForcefully = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUris.add(url);
    final error = getUrlError;
    if (error != null) {
      throw error;
    }
    return request;
  }

  @override
  void close({bool force = false}) {
    closedForcefully = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingHttpClientRequest implements HttpClientRequest {
  _RecordingHttpClientRequest({required this.response});

  final _FakeHttpClientResponse response;

  @override
  final _RecordingHttpHeaders headers = _RecordingHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingHttpHeaders implements HttpHeaders {
  final Map<String, String> _values = <String, String>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => _values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({required this.statusCode, required this.body});

  @override
  final int statusCode;
  final String body;
  bool listened = false;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listened = true;
    return Stream<List<int>>.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
