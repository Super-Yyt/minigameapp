import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStore extends ChangeNotifier {
  static const _tokenKey = 'oidc_token';
  static const _deviceKey = 'multiplayer_device_key';

  AuthStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String? _token;
  String? _deviceId;
  bool _ready = false;

  String? get token => _token;
  String? get deviceId => _deviceId;
  bool get isLoggedIn => _token != null;
  bool get isReady => _ready;

  Future<void> load() async {
    final storedToken = await _storage.read(key: _tokenKey);
    _token ??= storedToken;
    _deviceId ??= await _storage.read(key: _deviceKey);
    if (_deviceId == null) {
      _deviceId = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${identityHashCode(this).toRadixString(36)}';
      await _storage.write(key: _deviceKey, value: _deviceId!);
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> saveToken(String token) async {
    if (token.isEmpty) return;
    await _storage.write(key: _tokenKey, value: token);
    _token = token;
    notifyListeners();
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    _token = null;
    notifyListeners();
  }
}
