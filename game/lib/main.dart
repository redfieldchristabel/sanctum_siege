import 'dart:io';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'game/sanctum_siege_game.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force TikTok 9:16 aspect ratio on desktop
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final wm = WindowManager.instance;
    await wm.ensureInitialized();

    final windowOptions = WindowOptions(
      size: const Size(450, 800),  // 9:16 portrait
      minimumSize: const Size(360, 640),
      center: true,
      title: 'Sanctum Siege',
    );

    wm.waitUntilReadyToShow(windowOptions, () async {
      await wm.show();
      await wm.focus();
    });
  }

  runApp(GameWidget(game: SanctumSiegeGame()));
}
