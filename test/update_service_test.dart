import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minigameapp/update_service.dart';

void main() {
  test('更新响应优先选择匹配平台的资源', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['version'], '0.0.0');
      expect(request.url.queryParameters['user_id'], '42');
      return http.Response(
        jsonEncode({
          'has_update': true,
          'version': '0.0.1',
          'title': 'v0.0.1发布',
          'release_notes': '本体诞生',
          'file_size': 84844664,
          'download_url': 'https://fallback.example/update.zip',
          'release_date': '2026-08-17T10:29:57.604546Z',
          'assets': [
            {
              'os': 'win11',
              'arch': 'x64',
              'download_url': 'https://asset.example/update.zip',
              'file_size': 1024,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = UpdateService(
      client: client,
      versionProvider: () async => '0.0.0',
      osProvider: () => 'win10',
      archProvider: () => 'x64',
    );

    final update = await service.check(userId: 42, force: true);

    expect(update.hasUpdate, isTrue);
    expect(update.version, '0.0.1');
    expect(update.title, 'v0.0.1发布');
    expect(update.notes, '本体诞生');
    expect(update.url, 'https://asset.example/update.zip');
    expect(update.fileSize, 1024);
    expect(update.releaseDate, DateTime.parse('2026-08-17T10:29:57.604546Z'));
  });

  for (final platform in [
    ('macos', 'arm64'),
    ('linux', 'x64'),
    ('android', 'arm64'),
    ('ios', 'arm64'),
  ]) {
    test('选择 ${platform.$1}/${platform.$2} 对应资源', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'has_update': true,
              'version': '1.0.0',
              'download_url': 'https://fallback.example/update',
              'assets': [
                {
                  'os': platform.$1,
                  'arch': platform.$2,
                  'download_url': 'https://${platform.$1}.example/update',
                },
              ],
            }),
            200,
          ));
      final service = UpdateService(
        client: client,
        versionProvider: () async => '0.0.0',
        osProvider: () => platform.$1,
        archProvider: () => platform.$2,
      );

      final update = await service.check(force: true);

      expect(update.url, 'https://${platform.$1}.example/update');
    });
  }
}
