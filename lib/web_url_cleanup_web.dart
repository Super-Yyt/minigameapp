import 'dart:js_interop';

@JS('history.replaceState')
external void _replaceState(JSAny? state, String title, String url);

void clearLoginTokenFromUrl() => _replaceState(null, '', '/');
