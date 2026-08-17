import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient(this.baseUrl, {this.tokenProvider, this.deviceProvider, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final String? Function()? tokenProvider;
  final String? Function()? deviceProvider;
  final http.Client _client;

  Uri uri(String path) => Uri.parse(baseUrl).resolve(path);

  Future<List<Map<String, dynamic>>> games() async {
    final data = await _get('/api/v1/games/');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> me() async =>
      await _get('/api/v1/auth/me/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> wallet() async =>
      await _get('/api/v1/economy/wallet/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> createRoom(String game) => _send(
    '/api/v1/multiplayer/rooms/',
    {'game': game, 'max_players': 2, 'is_private': false},
  );

  Future<Map<String, dynamic>> joinRoom(String roomId) =>
      _send('/api/v1/multiplayer/rooms/$roomId/join/', {});

  Future<List<Map<String, dynamic>>> roomLobby({String? game}) async {
    final query = game == null ? '' : '?game=${Uri.encodeQueryComponent(game)}';
    return ((await _get('/api/v1/multiplayer/lobby/$query')) as List)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> game(String slug) async =>
      await _get('/api/v1/games/$slug/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> createGameSession(
    String game, {
    String? roomId,
  }) => _send('/api/v1/games/$game/session/', {
    'room_id': ?roomId,
  });

  Future<Map<String, dynamic>> room(String id) async =>
      await _get('/api/v1/multiplayer/rooms/$id/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> setRoomReady(String id, bool ready) => _send(
    '/api/v1/multiplayer/rooms/$id/ready/',
    {'ready': ready},
  );

  Future<Map<String, dynamic>> startRoom(String id) =>
      _send('/api/v1/multiplayer/rooms/$id/start/', {});

  Future<void> leaveRoom(String id) async {
    final response = await _client.post(
      uri('/api/v1/multiplayer/rooms/$id/leave/'),
      headers: _headers(json: true),
      body: '{}',
    );
    _decode(response);
  }

  Future<dynamic> _get(String path) async {
    final response = await _client.get(uri(path), headers: _headers());
    return _decode(response);
  }

  Future<Map<String, dynamic>> _send(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(
      uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(response) as Map<String, dynamic>;
  }

  Map<String, String> _headers({bool json = false}) {
    final token = tokenProvider?.call();
    final device = deviceProvider?.call();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Token $token',
      if (device != null && device.isNotEmpty) 'X-Game-Device': device,
    };
  }

  dynamic _decode(http.Response response) {
    final body = response.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body is Map ? body['message'] : null;
      throw ApiException(
        message is String ? message : '请求失败（${response.statusCode}）',
      );
    }
    return body;
  }
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
