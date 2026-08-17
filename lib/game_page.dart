import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as windows;

import 'api_client.dart';
import 'auth_store.dart';
import 'game_web_frame.dart';
import 'platform_info.dart';

class GamePage extends StatefulWidget {
  const GamePage({
    required this.api,
    required this.auth,
    required this.game,
    this.room,
    super.key,
  });

  final ApiClient api;
  final AuthStore auth;
  final Map<String, dynamic> game;
  final Map<String, dynamic>? room;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  WebViewController? _webView;
  windows.WebviewController? _windowsWebView;
  String? _webGameUrl;
  Map<String, dynamic>? _room;
  bool _creatingRoom = false;
  bool _updatingRoom = false;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    if (kIsWeb) {
      _loadGame();
    } else if (isWindows) {
      _initializeWindowsWebView();
    } else {
      _webView = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'MiniGameHost',
          onMessageReceived: _handleBridgeMessage,
        )
        ..setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => _injectContext()),
        );
      _loadGame();
    }
  }

  Future<void> _initializeWindowsWebView() async {
    final controller = windows.WebviewController();
    try {
      await controller.initialize();
      await controller.setPopupWindowPolicy(windows.WebviewPopupWindowPolicy.deny);
      controller.loadingState.listen((state) {
        if (state == windows.LoadingState.navigationCompleted) {
          _injectContext();
        }
      });
      controller.webMessage.listen((message) {
        if (message is String) _handleBridgeText(message);
      });
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _windowsWebView = controller);
      await _loadGame();
    } catch (error) {
      if (mounted) _message('Windows WebView2 初始化失败：$error');
    }
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    _handleBridgeText(message.message);
  }

  void _handleBridgeText(String message) {
    final action = _bridgeAction(message);
    if (action == 'close') {
      Navigator.of(context).pop();
    } else if (action == 'openLogin') {
      Navigator.of(context).pop(true);
    }
  }

  String? _bridgeAction(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map && decoded['action'] is String) {
        return decoded['action'] as String;
      }
    } on FormatException {
      return message;
    }
    return message;
  }

  Future<void> _loadGame() async {
    try {
      final session = await widget.api.createGameSession(
        widget.game['slug'] as String,
        roomId: _room?['id'] as String?,
      );
      if (!mounted) return;
      _session = session;
      final playPath = widget.game['play_url'] as String;
      final url = Uri.parse('${widget.api.baseUrl}$playPath');
      if (kIsWeb) {
        final platform = {
          'game': widget.game,
          'sdkApiBase': '${widget.api.baseUrl}${session['api_base']}',
          'gameSessionToken': session['token'],
          'expiresAt': session['expires_at'],
          if (_room?['websocket_url'] is String)
            'room': {
              ..._room!,
              'websocket_url': _websocketUrl(_room!['websocket_url'] as String),
            },
        };
        final encoded = base64Url.encode(utf8.encode(jsonEncode(platform))).replaceAll('=', '');
        setState(
          () => _webGameUrl =
              '${url.toString()}#platform=${Uri.encodeComponent(encoded)}',
        );
      } else if (isWindows) {
        await _windowsWebView!.loadUrl(url.toString());
      } else {
        await _webView!.loadRequest(url);
      }
    } catch (error) {
      if (mounted) _message('无法创建游戏会话：$error');
    }
  }

  Map<String, dynamic>? _session;

  Future<void> _injectContext() async {
    if (_session == null || kIsWeb) return;
    final websocketUrl = _room?['websocket_url'];
    final context = {
      'game': widget.game,
      'sdkApiBase': '${widget.api.baseUrl}${_session!['api_base']}',
      'gameSessionToken': _session!['token'],
      'expiresAt': _session!['expires_at'],
      if (websocketUrl is String)
        'room': {..._room!, 'websocket_url': _websocketUrl(websocketUrl)},
    };
    final encoded = jsonEncode(context).replaceAll('</', '<\\/');
    final script = '''
      window.MiniGamePlatform = $encoded;
      window.dispatchEvent(new CustomEvent('MiniGamePlatformReady', {detail: window.MiniGamePlatform}));
    ''';
    if (isWindows) {
      await _windowsWebView?.executeScript(script);
    } else {
      await _webView?.runJavaScript(script);
    }
  }

  String _websocketUrl(String value) {
    final uri = Uri.parse(value);
    if (uri.hasScheme) return value;
    final base = Uri.parse(widget.api.baseUrl);
    return base
        .replace(scheme: base.scheme == 'https' ? 'wss' : 'ws')
        .resolve(value)
        .toString();
  }

  Future<void> _createRoom() async {
    setState(() => _creatingRoom = true);
    try {
      final room = await widget.api.createRoom(widget.game['slug'] as String);
      if (!mounted) return;
      setState(() => _room = room);
      await _loadGame();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('联机房间已创建')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建房间失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _creatingRoom = false);
      }
    }
  }

  Future<void> _setReady() async {
    if (_room == null) {
      return;
    }
    setState(() => _updatingRoom = true);
    try {
      final room = await widget.api.setRoomReady(_room!['id'] as String, true);
      if (mounted) {
        setState(() => _room = room);
        await _injectContext();
      }
    } catch (error) {
      if (mounted) _message('设置准备状态失败：$error');
    } finally {
      if (mounted) setState(() => _updatingRoom = false);
    }
  }

  Future<void> _startRoom() async {
    if (_room == null) {
      return;
    }
    setState(() => _updatingRoom = true);
    try {
      final room = await widget.api.startRoom(_room!['id'] as String);
      if (mounted) {
        setState(() => _room = room);
        await _injectContext();
      }
    } catch (error) {
      if (mounted) _message('开始游戏失败：$error');
    } finally {
      if (mounted) setState(() => _updatingRoom = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _copyRoomId() async {
    final roomId = _room?['id'] as String?;
    if (roomId == null) return;
    await Clipboard.setData(ClipboardData(text: roomId));
    if (mounted) _message('房间号已复制：$roomId');
  }

  Future<void> _copyInviteLink() async {
    final roomId = _room?['id'] as String?;
    final link = kIsWeb && roomId != null
        ? '${Uri.base.origin}/?room=$roomId'
        : _room?['invite_url'] as String?;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) _message('邀请链接已复制');
  }

  @override
  void dispose() {
    final roomId = _room?['id'] as String?;
    if (roomId != null) {
      widget.api.leaveRoom(roomId);
    }
    _windowsWebView?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supportsMultiplayer =
        widget.game['manifest'] is Map &&
        (widget.game['manifest'] as Map)['multiplayer'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.game['name'] as String),
        actions: [
          if (supportsMultiplayer)
            IconButton(
              tooltip: '创建联机房间',
              onPressed: _creatingRoom ? null : _createRoom,
              icon: _creatingRoom
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.groups),
              ),
          if (_room != null)
            IconButton(
              tooltip: '复制房间号',
              onPressed: _copyRoomId,
              icon: const Icon(Icons.copy_all_outlined),
            ),
          if (_room != null)
            IconButton(
              tooltip: '复制邀请链接',
              onPressed: _copyInviteLink,
              icon: const Icon(Icons.link_outlined),
            ),
          if (_room != null)
            IconButton(
              tooltip: '准备',
              onPressed: _updatingRoom ? null : _setReady,
              icon: const Icon(Icons.check_circle_outline),
            ),
          if (_room != null)
            IconButton(
              tooltip: '开始游戏',
              onPressed: _updatingRoom ? null : _startRoom,
              icon: const Icon(Icons.play_circle_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_room != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: InkWell(
                onTap: _copyRoomId,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_outlined, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '房间号：${_room!['id']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Text('点击复制'),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: isWindows
                ? (_windowsWebView == null
                      ? const Center(child: CircularProgressIndicator())
                      : windows.Webview(_windowsWebView!))
                : kIsWeb
                ? (_webGameUrl == null
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          children: [
                            Positioned.fill(child: gameWebFrame(_webGameUrl!)),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Tooltip(
                                message: _webGameUrl!,
                                child: const Icon(Icons.info_outline, size: 16),
                              ),
                            ),
                          ],
                        ))
                : WebViewWidget(controller: _webView!),
          ),
        ],
      ),
    );
  }
}
