import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'game/lobby/angel_guild_screen.dart';
import 'game/lobby/guild_lobby_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force TikTok 9:16 aspect ratio on desktop
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final wm = WindowManager.instance;
    await wm.ensureInitialized();

    final windowOptions = WindowOptions(
      size: const Size(450, 800), // 9:16 portrait
      minimumSize: const Size(360, 640),
      center: true,
      title: 'Sanctum Siege',
    );

    wm.waitUntilReadyToShow(windowOptions, () async {
      await wm.show();
      await wm.focus();
    });
  }

  runApp(SanctumSiegeApp(controller: GuildLobbyController()));
}

/// Root app — starts at Angel Guild lobby, then enters battle.
class SanctumSiegeApp extends StatelessWidget {
  final GuildLobbyController controller;

  /// Global navigator key so the game can return to the lobby
  /// even after the original route was replaced/disposed.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const SanctumSiegeApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: SanctumSiegeApp.navigatorKey,
      title: 'Sanctum Siege',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0A1A),
        textTheme: GoogleFonts.vt323TextTheme(ThemeData.dark().textTheme),
      ),
      home: AngelGuildScreen(controller: controller),
    );
  }
}
