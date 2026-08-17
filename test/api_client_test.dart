import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:minigameapp/api_client.dart';

void main() {
  test('请求携带 Token 认证头', () async {
    final client = _RecordingClient();
    final api = ApiClient(
      'https://example.com',
      tokenProvider: () => 'saved-token',
      client: client,
    );

    await api.wallet();

    expect(client.lastRequest!.headers['authorization'], 'Token saved-token');
  });
}

class _RecordingClient extends http.BaseClient {
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"accounts":[]}')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
