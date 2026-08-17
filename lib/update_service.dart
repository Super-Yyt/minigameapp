import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'platform_info.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.hasUpdate,
    this.version,
    this.title,
    this.notes,
    this.url,
    this.fileSize,
    this.releaseDate,
  });

  final bool hasUpdate;
  final String? version;
  final String? title;
  final String? notes;
  final String? url;
  final int? fileSize;
  final DateTime? releaseDate;
}

class UpdateService {
  UpdateService({
    http.Client? client,
    this.versionProvider,
    this.osProvider,
    this.archProvider,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Future<String> Function()? versionProvider;
  final String? Function()? osProvider;
  final String? Function()? archProvider;

  String? get _os => osProvider?.call() ?? updateOs;
  String? get _arch => archProvider?.call() ?? updateArch;
  bool get supported => !kIsWeb && _os != null && _arch != null;

  Future<String> currentVersion() async =>
      versionProvider?.call() ?? (await PackageInfo.fromPlatform()).version;

  Future<UpdateInfo> check({int? userId, bool force = false}) async {
    if (!force && !supported) return const UpdateInfo(hasUpdate: false);
    final version = await currentVersion();
    final os = _os ?? 'win10';
    final arch = _arch ?? 'x64';
    final uri = Uri.https('dev-api.dy.ci', '/api/distribute/check/mg/', {
      'version': version,
      'os': os,
      'arch': arch,
      'channel': 'stable',
      if (userId != null) 'user_id': '$userId',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('更新服务返回 ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) throw const FormatException('更新响应格式错误');
    final assets = body['assets'];
    Map<String, dynamic>? asset;
    if (assets is List) {
      for (final value in assets.whereType<Map>()) {
        final candidate = Map<String, dynamic>.from(value);
        final os = candidate['os']?.toString().toLowerCase();
        final arch = candidate['arch']?.toString().toLowerCase();
        if (_matchesOs(os, osProvider?.call() ?? updateOs ?? 'win10') &&
            arch == (archProvider?.call() ?? updateArch ?? 'x64')) {
          asset = candidate;
          break;
        }
      }
    }
    String? textValue(dynamic value) => value is String && value.isNotEmpty ? value : null;
    final releaseDate = textValue(body['release_date']);
    return UpdateInfo(
      hasUpdate: body['has_update'] == true,
      version: (body['version'] ?? body['latest_version']) as String?,
      title: textValue(body['title']),
      notes: textValue(body['release_notes'] ?? body['notes'] ?? body['changelog']),
      url: textValue(asset?['download_url']) ??
          textValue(body['download_url'] ?? body['package_url'] ?? body['url']),
      fileSize: (asset?['file_size'] as num?)?.toInt() ??
          (body['file_size'] as num?)?.toInt(),
      releaseDate: releaseDate == null ? null : DateTime.tryParse(releaseDate),
    );
  }

  bool _matchesOs(String? assetOs, String currentOs) {
    if (assetOs == currentOs) return true;
    if (currentOs == 'win10') {
      return assetOs == 'win11' || assetOs == 'windows';
    }
    return false;
  }

  Future<bool> openDownload(UpdateInfo update) async {
    final url = update.url;
    if (url == null) return false;
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
