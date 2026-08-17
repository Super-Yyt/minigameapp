import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

int _frameId = 0;

Widget gameWebFrame(String url) {
  final viewType = 'minigame-frame-${_frameId++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (_) {
    return web.HTMLIFrameElement()
      ..src = url
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'fullscreen'
      ..referrerPolicy = 'no-referrer';
  });
  return HtmlElementView(viewType: viewType);
}
