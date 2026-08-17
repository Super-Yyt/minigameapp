import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'auth_store.dart';
import 'game_page.dart';
import 'update_service.dart';
import 'web_url_cleanup.dart';

const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://mgapi.dy.ci',
);

void main() => runApp(const MainApp());

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  static const _deepLinkChannel = MethodChannel('minigame/deep_link');
  final _auth = AuthStore();
  final _links = AppLinks();
  late final ApiClient _api = ApiClient(
    apiBase,
    tokenProvider: () => _auth.token,
    deviceProvider: () => _auth.deviceId,
  );
  StreamSubscription<Uri>? _linkSubscription;
  String? _pendingRoomId;

  @override
  void initState() {
    super.initState();
    _auth.load();
    if (kIsWeb) {
      _handleLink(Uri.base);
    }
    _links.getInitialLink().then(_handleLink);
    _linkSubscription = _links.uriLinkStream.listen(_handleLink);
    _deepLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'received' && call.arguments is String) {
        await _handleLink(Uri.tryParse(call.arguments as String));
      }
    });
  }

  Future<void> _handleLink(Uri? uri) async {
    final nativeCallback =
        uri?.scheme == 'minigame' &&
        uri?.host == 'auth' &&
        uri?.path == '/callback';
    final webCallback =
        kIsWeb && uri?.queryParameters.containsKey('token') == true;
    if (nativeCallback || webCallback) {
      await _auth.saveToken(uri!.queryParameters['token'] ?? '');
      if (webCallback) {
        clearLoginTokenFromUrl();
      }
    }
    final roomId = uri?.queryParameters['room'];
    if (roomId != null && roomId.isNotEmpty) {
      _pendingRoomId = roomId;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _deepLinkChannel.setMethodCallHandler(null);
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiniGame',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff7357ff)),
      ),
      home: GameCenterPage(
        api: _api,
        auth: _auth,
        initialRoomId: _pendingRoomId,
      ),
    );
  }
}

class GameCenterPage extends StatefulWidget {
  const GameCenterPage({
    required this.api,
    required this.auth,
    this.initialRoomId,
    super.key,
  });

  final ApiClient api;
  final AuthStore auth;
  final String? initialRoomId;

  @override
  State<GameCenterPage> createState() => _GameCenterPageState();
}

class _GameCenterPageState extends State<GameCenterPage> {
  late Future<List<Map<String, dynamic>>> _games = widget.api.games();
  final _updates = UpdateService();
  Map<String, dynamic>? _profile;
  String _appVersion = '...';

  @override
  void initState() {
    super.initState();
    _loadProfileAndCheckUpdate();
    if (widget.initialRoomId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _joinRoom(widget.initialRoomId),
      );
    }
  }

  Future<void> _loadProfileAndCheckUpdate() async {
    if (_updates.supported) {
      _appVersion = await _updates.currentVersion();
      if (mounted) setState(() {});
    }
    await widget.auth.load();
    if (widget.auth.isLoggedIn) {
      try {
        _profile = await widget.api.me();
        if (mounted) setState(() {});
      } catch (_) {
        _profile = null;
      }
    }
    if (_updates.supported && mounted) await _checkUpdate(silent: true);
  }

  Future<void> _checkUpdate({bool silent = false}) async {
    try {
      final update = await _updates.check(userId: _profile?['id'] as int?);
      if (!mounted) return;
      if (!update.hasUpdate) {
        if (!silent) _message('当前已是最新版本 $_appVersion');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(update.title ?? '发现新版本 ${update.version ?? ''}'),
          content: Text(
            [
              if (update.version != null) '版本：${update.version}',
              if (update.notes != null) update.notes!,
              if (update.fileSize != null)
                '大小：${(update.fileSize! / 1024 / 1024).toStringAsFixed(1)} MB',
              if (update.releaseDate != null)
                '发布时间：${update.releaseDate!.toLocal().toString().split('.').first}',
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('稍后'),
            ),
            if (update.url != null)
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  if (!await _updates.openDownload(update) && mounted) {
                    _message('无法打开更新下载地址');
                  }
                },
                child: const Text('下载更新'),
              ),
          ],
        ),
      );
    } catch (error) {
      if (!silent && mounted) _message('检查更新失败：$error');
    }
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本：$_appVersion'),
            const SizedBox(height: 8),
            Text('账号：${_profile?['用户名'] ?? '未登录'}'),
          ],
        ),
        actions: [
          if (_updates.supported)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _checkUpdate();
              },
              icon: const Icon(Icons.system_update_outlined),
              label: const Text('检查更新'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    final loginUri = widget.api
        .uri('/api/v1/auth/login/')
        .replace(
          queryParameters: {
            if (kIsWeb) 'client': 'web',
            if (kIsWeb) 'web_origin': Uri.base.origin,
            if (widget.initialRoomId != null) 'room': widget.initialRoomId!,
          },
        );
    final launched = await launchUrl(
      loginUri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
    if (!launched && mounted) {
      _message('无法打开登录页面');
    }
  }

  Future<void> _openGame(
    Map<String, dynamic> game, {
    Map<String, dynamic>? room,
  }) async {
    final openLogin = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GamePage(
          api: widget.api,
          auth: widget.auth,
          game: game,
          room: room,
        ),
      ),
    );
    if (openLogin == true) {
      await _login();
    }
  }

  Future<void> _createRoom(Map<String, dynamic> game) async {
    if (!widget.auth.isLoggedIn) {
      _message('请先登录后再创建联机房间');
      return;
    }
    try {
      final room = await widget.api.createRoom(game['slug'] as String);
      if (mounted) {
        await _openGame(game, room: room);
      }
    } catch (error) {
      if (mounted) {
        _message('创建房间失败：$error');
      }
    }
  }

  Future<void> _joinRoom([String? initialRoomId]) async {
    if (!widget.auth.isLoggedIn) {
      _message('请先登录，登录后会继续加入该房间');
      await _login();
      return;
    }
    final controller = TextEditingController(text: initialRoomId ?? '');
    final roomId =
        initialRoomId ??
        await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('加入联机房间'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: '房间 UUID'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('加入'),
              ),
            ],
          ),
        );
    controller.dispose();
    if (roomId == null || roomId.isEmpty) return;
    try {
      final room = await widget.api.joinRoom(roomId);
      final game = await widget.api.game(room['game'] as String);
      if (mounted) await _openGame(game, room: room);
    } catch (error) {
      if (mounted) _message('加入房间失败：$error');
    }
  }

  Future<void> _showLobby() async {
    if (!widget.auth.isLoggedIn) {
      _message('请先登录后查看联机大厅');
      return;
    }
    try {
      final rooms = await widget.api.roomLobby();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('联机大厅'),
          content: SizedBox(
            width: 520,
            child: rooms.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无公开等待房间，可以在游戏卡片上创建房间。'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: rooms.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      return ListTile(
                        title: Text(room['game_name'] as String),
                        subtitle: Text(
                          '房主：${room['owner']}  人数：${room['member_count']}/${room['max_players']}',
                        ),
                        trailing: FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _joinRoom(room['id'] as String);
                          },
                          child: const Text('加入'),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            if (widget.auth.isLoggedIn)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('${_profile?['用户名'] ?? '已登录'}'),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _message('大厅加载失败：$error');
    }
  }

  Future<void> _showWallet() async {
    if (!widget.auth.isLoggedIn) {
      _message('请先登录后查看钱包');
      return;
    }
    try {
      final wallet = await widget.api.wallet();
      if (!mounted) {
        return;
      }
      final accounts = (wallet['accounts'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('我的钱包'),
          content: accounts.isEmpty
              ? const Text('暂无资产')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: accounts
                      .map(
                        (account) => ListTile(
                          title: Text('${account['name']}'),
                          trailing: Text('${account['balance']}'),
                        ),
                      )
                      .toList(),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        _message('钱包加载失败：$error');
      }
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.auth,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('MiniGame'),
          actions: [
            IconButton(
              tooltip: '联机大厅',
              onPressed: _showLobby,
              icon: const Icon(Icons.meeting_room_outlined),
            ),
            IconButton(
              tooltip: '输入房间号加入',
              onPressed: _joinRoom,
              icon: const Icon(Icons.group_add_outlined),
            ),
            Center(child: Text(widget.auth.isLoggedIn ? '已登录' : '未登录')),
            IconButton(
              tooltip: '我的钱包',
              onPressed: _showWallet,
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
            IconButton(
              tooltip: '设置',
              onPressed: _showSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
            TextButton.icon(
              onPressed: widget.auth.isLoggedIn ? widget.auth.logout : _login,
              icon: Icon(widget.auth.isLoggedIn ? Icons.logout : Icons.login),
              label: Text(widget.auth.isLoggedIn ? '退出登录' : 'OIDC 登录'),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _games,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('游戏目录加载失败：${snapshot.error}'));
            }
            final games = snapshot.data ?? [];
            if (games.isEmpty) {
              return const Center(child: Text('暂无已发布游戏'));
            }
            return RefreshIndicator(
              onRefresh: () async =>
                  setState(() => _games = widget.api.games()),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: games.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final game = games[index];
                  final multiplayer =
                      game['manifest'] is Map &&
                      (game['manifest'] as Map)['multiplayer'] == true;
                  return Card(
                    child: ListTile(
                      title: Text(game['name'] as String),
                      subtitle: Text(
                        (game['description'] as String?) ?? '点击开始游戏',
                      ),
                      trailing: multiplayer
                          ? IconButton(
                              tooltip: '创建联机房间',
                              icon: const Icon(Icons.groups),
                              onPressed: () => _createRoom(game),
                            )
                          : const Icon(Icons.play_arrow),
                      onTap: () => _openGame(game),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
