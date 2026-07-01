import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'relay_client.dart';
import 'lobby/angel_guild_screen.dart';
import 'lobby/guild_lobby_controller.dart';

/// ──────────────────────────────────────────────────
/// GAME COVER — Entrance Screen
///
/// Full-screen game cover image. Waits for the "go"
/// CLI command (StartGameEvent) before transitioning
/// to the Angel Guild lobby.
/// ──────────────────────────────────────────────────

class CoverScreen extends StatefulWidget {
  const CoverScreen({super.key});

  @override
  State<CoverScreen> createState() => _CoverScreenState();
}

class _CoverScreenState extends State<CoverScreen> {
  late final RelayClient _relay;
  bool _hasEntered = false;

  @override
  void initState() {
    super.initState();

    _relay = RelayClient(
      url: 'ws://localhost:8080',
      onEvent: (event) {
        if (event is StartGameEvent && !_hasEntered) {
          _hasEntered = true;
          _relay.dispose();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AngelGuildScreen(
                controller: GuildLobbyController(),
              ),
            ),
          );
        }
      },
    );
    _relay.connect();
  }

  @override
  void dispose() {
    _relay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen cover image
          Image.asset(
            'assets/images/game_cover.png',
            fit: BoxFit.cover,
          ),
          // Subtle bottom hint
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'AWAITING YOUR COMMAND',
                style: GoogleFonts.cinzel(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
