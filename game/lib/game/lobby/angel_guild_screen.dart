import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flame/game.dart';
import 'guild_lobby_controller.dart';
import '../relay_client.dart';
import '../sanctum_siege_game.dart';
import 'persistent_storage.dart';
import '../../main.dart';

/// ──────────────────────────────────────────────────
/// ANGEL GUILD — Party Selection Screen
///
/// Anime guild aesthetic: parchment background, wood
/// trim border, 2×9 card grid, zero touch elements.
///
/// Creates its own [RelayClient] and routes typed events
/// to the [GuildLobbyController] via a switch.
/// ──────────────────────────────────────────────────

class AngelGuildScreen extends StatefulWidget {
  final GuildLobbyController controller;

  const AngelGuildScreen({super.key, required this.controller});

  @override
  State<AngelGuildScreen> createState() => _AngelGuildScreenState();
}

class _AngelGuildScreenState extends State<AngelGuildScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;
  late final RelayClient _relay;

  static const _darkBrown = Color(0xFF2C1A04);
  static const _mediumBrown = Color(0xFF5C3A1E);
  static const _gold = Color(0xFFD4A017);

  GuildLobbyController get ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    ctrl.startCountdown();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _relay = RelayClient(
      url: 'ws://localhost:8080',
      onEvent: _handleEvent,
    );
    _relay.connect();

    // Restore gifter points from previous match (crash-safe)
    PersistentStorage.restoreLobbyState(ctrl);

    ctrl.onMatchReady = _enterBattle;
  }

  void _handleEvent(RelayEvent event) {
    switch (event) {
      case JoinEvent e:
        ctrl.addPlayer(LobbyPlayer(
          username: e.username,
          profilePicUrl: '',
          points: 0,
          isGifter: e.isGifter,
        ));
      case LikeEvent e:
        ctrl.processLikePoints(e.username, e.count, isFollower: e.isFollower);
      case GiftEvent e:
        ctrl.processGiftPoints(e.username, coinCost: e.coinCost, count: e.count, isFollower: e.isFollower);
        ctrl.markAsGifter(e.username);
      case LobbyUpdateEvent _:
        _fillMockParty();
      case LobbyClearEvent _:
        ctrl.clearLobby();
      case StartMatchEvent _:
      case StartGameEvent _:
        if (ctrl.phase == LobbyPhase.ranking) {
          ctrl.startClassAssignment();
          _startClassTimer();
        } else if (ctrl.phase == LobbyPhase.classAssignment) {
          // Second go — skip remaining class time
          _classTimer?.cancel();
          ctrl.finalizeClasses();
          ctrl.startMatchTransition(() {});
        }
      case CommentEvent e:
        _handleClassCommand(e);
      default:
        break;
    }
  }

  /// Parse !class commands during the class assignment phase.
  void _handleClassCommand(CommentEvent e) {
    if (ctrl.phase != LobbyPhase.classAssignment) return;
    final text = e.text.trim().toLowerCase();
    final match = RegExp(r'^!(archer|knight|melee|wizard)$').firstMatch(text);
    if (match == null) return;
    final chosen = switch (match.group(1)!) {
      'knight' || 'melee' => 'melee',
      _ => 'sunfletcher', // sunfletcher or future wizard
    };
    ctrl.setPlayerClass(e.username, chosen);
  }

  /// Start the 30-second class assignment countdown timer.
  Timer? _classTimer;

  void _startClassTimer() {
    _classTimer?.cancel();
    _classTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (ctrl.phase != LobbyPhase.classAssignment) {
        t.cancel();
        return;
      }
      ctrl.classTimerSeconds--;
      ctrl.notifyListeners();
      if (ctrl.classTimerSeconds <= 0) {
        t.cancel();
        ctrl.finalizeClasses();
        ctrl.startMatchTransition(() {});
      }
    });
  }

  void _fillMockParty() {
    final names = [
      'SakuraBlade', 'Raven_Night', 'AetherKing', 'LunaStar_99', 'Zer0_Cool',
      'PhantomX', 'CrimsonTide', 'Novaflare', 'ShadowWeaver', 'Celestia_M',
      'BlazeFury', 'FrostByte', 'VoidWalker', 'StormChaser', 'LunarEclipse',
    ];
    final wildcards = [
      'TinySparrow', 'PixelPaw', 'FloatingLeaf', 'DewDrop_42', 'HappyBean',
    ];

    final players = <LobbyPlayer>[];
    for (int i = 0; i < names.length; i++) {
      players.add(LobbyPlayer(
        username: names[i], profilePicUrl: '', points: (18 - i) * 90,
        isGifter: true,
      ));
    }
    for (final w in wildcards) {
      players.add(LobbyPlayer(
        username: w, profilePicUrl: '', points: 0, isGifter: false,
      ));
    }
    ctrl.updateLobby(players);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _relay.dispose();
    ctrl.stopCountdown();
    super.dispose();
  }

  void _enterBattle() {
    _relay.dispose();
    _classTimer?.cancel();

    // Extract lobby player usernames and class assignments
    final usernames = ctrl.partySlots
        .where((p) => p != null)
        .map((p) => p!.username)
        .toList();
    final classMap = ctrl.classAssignments;
    print('[lobby] Entering battle with ${usernames.length} elite soldiers');

    // Save filtered registry to disk (crash-safe seed) before entering battle
    PersistentStorage.saveLobbyState(ctrl.masterRegistry, ctrl.selectedUsernames);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameWidget(
          game: SanctumSiegeGame(
            lobbyUsernames: usernames,
            classAssignments: classMap,
            onGameOver: () {
              // Use the app-level navigator key — the original screen
              // may already be disposed after pushReplacement.
              SanctumSiegeApp.navigatorKey.currentState?.pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => AngelGuildScreen(
                    controller: GuildLobbyController(),
                  ),
                ),
                (route) => false,
              );
            },
          ),
        ),
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          return Stack(
            children: [
              _buildParchmentBase(),
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(),
                    _buildTimerBar(),
                    // CONDITIONAL PHASE ROUTER:
                    Expanded(
                      child: ctrl.phase == LobbyPhase.tutorial
                          ? _buildTutorialHandbookView()
                          : _buildCardGrid(),
                    ),
                    _buildFooter(),
                  ],
                ),
              ),
              ..._buildPointPopups(),
              if (ctrl.isTransitioning) _buildTransitionOverlay(),
            ],
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════
  //  Parchment Background
  // ══════════════════════════════════════════════════

  Widget _buildParchmentBase() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage('assets/images/parchment_bg.png'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.08),
            BlendMode.darken,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.symmetric(
            vertical: BorderSide(
              color: _mediumBrown.withValues(alpha: 0.7),
              width: 4,
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════
  //  Header
  // ══════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        children: [
          Container(height: 3, color: _mediumBrown),
          const SizedBox(height: 8),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_gold, Color(0xFFFFD700), _gold],
              stops: [0.0, 0.5, 1.0],
            ).createShader(bounds),
            child: Text(
              ctrl.phase == LobbyPhase.classAssignment
                  ? 'CLASS ASSIGNMENT'
                  : 'ANGEL GUILD',
              textAlign: TextAlign.center,
              style: GoogleFonts.cinzel(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: _darkBrown.withValues(alpha: 0.6),
                    blurRadius: 6,
                    offset: const Offset(1, 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            ctrl.phase == LobbyPhase.classAssignment
                ? 'TOP 5: !sunfletcher or !knight in chat'
                : 'PARTY SELECTION',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 5,
              color: _darkBrown.withValues(alpha: 0.7),
            ),
          ),
          // Instructional hints (hidden during class assignment)
          if (ctrl.phase == LobbyPhase.ranking)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.thumb_up, size: 11,
                      color: _darkBrown.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text(
                    'Like to climb',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: _darkBrown.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.star, size: 11,
                      color: _gold.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text(
                    'Follow = 2x points',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: _gold.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Container(height: 1, color: _gold)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.diamond, size: 12, color: _gold),
              ),
              Expanded(child: Container(height: 1, color: _gold)),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════
  //  Timer Bar
  // ══════════════════════════════════════════════════

  Widget _buildTimerBar() {
    final bool isTutorial = ctrl.phase == LobbyPhase.tutorial;
    final bool isClassPhase = ctrl.phase == LobbyPhase.classAssignment;

    final int seconds = isTutorial
        ? ctrl.tutorialTimerSeconds
        : (isClassPhase ? ctrl.classTimerSeconds : ctrl.countdownSeconds);

    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    final timeStr = '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isTutorial ? Icons.help_outline : (isClassPhase ? Icons.shield : Icons.schedule),
            size: 13,
            color: _mediumBrown,
          ),
          const SizedBox(width: 6),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: _darkBrown,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isTutorial
                ? 'until battle preview starts'
                : (isClassPhase ? 'to pick class' : 'until muster'),
            style: TextStyle(
              fontSize: 10,
              color: _mediumBrown.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════
  //  Party Card Grid (2 columns × 9 rows)
  // ══════════════════════════════════════════════════

  Widget _buildCardGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 3.8,
          crossAxisSpacing: 6,
          mainAxisSpacing: 4,
        ),
        itemCount: 18,
        itemBuilder: (context, index) {
          final player = ctrl.partySlots[index];
          final rank = index + 1;
          final isTop3 = rank <= 3;
          final isPointsSlot = rank <= 13;
          final isGlowing = ctrl.glowingCardIndices.contains(index);

          if (player == null) {
            return _buildEmptySlot(rank);
          }

          return _buildPlayerCard(
            rank: rank,
            player: player,
            isTop3: isTop3,
            isPointsSlot: isPointsSlot,
            isGlowing: isGlowing,
          );
        },
      ),
    );
  }

  Widget _buildEmptySlot(int rank) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.brown.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _mediumBrown.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$rank.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w300,
                color: _mediumBrown.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Awaiting Hero...',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: _mediumBrown.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard({
    required int rank,
    required LobbyPlayer player,
    required bool isTop3,
    required bool isPointsSlot,
    required bool isGlowing,
  }) {
    final Color borderColor;

    if (isGlowing) {
      borderColor = Colors.amber;
    } else if (isTop3) {
      borderColor = _gold;
    } else if (isPointsSlot) {
      borderColor = _mediumBrown.withValues(alpha: 0.5);
    } else {
      borderColor = Colors.cyan.withValues(alpha: 0.3);
    }

    final Color glowColor = isGlowing
        ? Colors.amber.withValues(alpha: 0.4)
        : isTop3
            ? _gold.withValues(alpha: 0.12)
            : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: isTop3 ? 1.5 : 0.8),
        boxShadow: isTop3 || isGlowing
            ? [BoxShadow(color: glowColor, blurRadius: 6, spreadRadius: 0)]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            // Rank badge
            SizedBox(
              width: 28,
              child: isTop3
                  ? Icon(
                      rank == 1
                          ? Icons.auto_awesome
                          : rank == 2
                              ? Icons.star
                              : Icons.star_half,
                      size: 18,
                      color: borderColor,
                    )
                  : Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _darkBrown.withValues(alpha: 0.6),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            // Avatar with follower badge
            Stack(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: player.isGifter
                        ? const LinearGradient(
                            colors: [_gold, Color(0xFFFFD700)])
                        : const LinearGradient(
                            colors: [Color(0xFF7B61FF), Color(0xFF00BCD4)]),
                    border: isTop3
                        ? Border.all(color: _gold, width: 1.5)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      player.username.isNotEmpty
                          ? player.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Follower 2x badge
                if (player.isFollower)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _gold,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white, width: 1),
                      ),
                      child: const Center(
                        child: Text(
                          '2x',
                          style: TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2C1A04),
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            // Username + points
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            player.username,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _darkBrown,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                      if (player.isGifter)
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Icon(
                            Icons.diamond,
                            size: 13,
                            color: _gold,
                          ),
                        ),
                      if (player.soldierClass != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Icon(
                            player.soldierClass == 'melee'
                                ? Icons.shield
                                : Icons.gps_fixed,
                            size: 11,
                            color: player.soldierClass == 'melee'
                                ? const Color(0xFF4A6FA5)
                                : const Color(0xFFD4AF37),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.favorite, size: 9, color: _gold),
                      const SizedBox(width: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${player.points}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _mediumBrown,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════
  //  Footer
  // ══════════════════════════════════════════════════

  Widget _buildFooter() {
    final filled = ctrl.partySlots.where((p) => p != null).length;
    final totalPoints = ctrl.partySlots.fold<int>(
      0,
      (sum, p) => sum + (p?.points ?? 0),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          Container(height: 1, color: _gold.withValues(alpha: 0.5)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _footerChip(Icons.people, '$filled / 18 Heroes'),
              const SizedBox(width: 16),
              _footerChip(Icons.favorite, '$totalPoints pts'),
            ],
          ),
          const SizedBox(height: 4),
          Container(height: 3, color: _mediumBrown),
        ],
      ),
    );
  }

  Widget _footerChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: _gold),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _darkBrown,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════
  //  Point Popup Overlays
  // ══════════════════════════════════════════════════

  List<Widget> _buildPointPopups() {
    if (ctrl.activePopups.isEmpty) return [];

    return ctrl.activePopups.map((popup) {
      final idx = ctrl.partySlots.indexWhere(
        (p) => p?.username == popup.username,
      );
      if (idx == -1) return const SizedBox.shrink();

      final row = idx ~/ 2;
      final col = idx % 2;
      final cardWidth = (MediaQuery.of(context).size.width - 36) / 2;
      final topOffset = 160.0 + (row * (cardWidth / 4.0 + 4));

      return Positioned(
        top: topOffset,
        left: 12 + (col * (cardWidth + 6)),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1200),
          builder: (context, value, child) {
            return Opacity(
              opacity: 1.0 - value,
              child: Transform.translate(
                offset: Offset(0, -20 * value),
                child: Text(
                  '+${popup.pointsAdded}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _gold,
                    shadows: [
                      Shadow(
                        color: Colors.amber.withValues(alpha: 0.6),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }).toList();
  }

  // ══════════════════════════════════════════════════
  //  Match Transition Overlay
  // ══════════════════════════════════════════════════

  Widget _buildTransitionOverlay() {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, child) {
        return Container(
          color: Colors.white.withValues(alpha: 0.1 * _glowAnim.value),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome,
                    size: 48,
                    color: _gold.withValues(alpha: _glowAnim.value)),
                const SizedBox(height: 16),
                Text(
                  'TO THE BATTLEFIELD!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: _gold.withValues(alpha: _glowAnim.value),
                    shadows: [
                      Shadow(
                        color: Colors.amber.withValues(alpha: 0.5),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════
  //  Tutorial Handbook
  // ══════════════════════════════════════════════════

  Widget _buildTutorialHandbookView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── SECTION 1: MEET YOUR CLASSES ──
          _buildTutorialHeader("⚔️ SOLDIER ARCHETYPES"),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildClassOnboardingCard(
                  icon: Icons.shield,
                  className: "ANGEL KNIGHT",
                  details: "Melee Tank Class\n• Health: 8 HP Max\n• Range: 40px\n• Action: Devastating direct close-quarters strikes.",
                  color: const Color(0xFF4A6FA5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildClassOnboardingCard(
                  icon: Icons.gps_fixed,
                  className: "SUNFLETCHER",
                  details: "Ranged Archer Class\n• Health: 3 HP Max\n• Range: 280px\n• Action: Continuous long-distance cover-fire.",
                  color: const Color(0xFFD4AF37),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── SECTION 2: LEADERBOARD & SELECTION ──
          _buildTutorialHeader("🏆 LEADERBOARD QUALIFICATION"),
          const SizedBox(height: 8),
          _buildInstructionBullet(
            title: "Climb with Stream Likes",
            desc: "Interact and send likes during the ranking lobby phase to score points and push your name into the Elite 18 roster.",
          ),
          _buildInstructionBullet(
            title: "Top 5 Role Command Locking",
            desc: "If you secure a spot in the Top 5, use chat choices during the selection window. Type '!knight' or '!sunfletcher' (or '!archer') to immediately change your class assignment archetype.",
          ),
          const SizedBox(height: 20),

          // ── SECTION 3: IN-GAME COMBAT SYSTEM ──
          _buildTutorialHeader("🔥 IN-GAME COMBAT INTERACTIONS"),
          const SizedBox(height: 8),
          _buildInstructionBullet(
            title: "💖 Likes Interaction Mechanism",
            desc: "• Out of Combat: Grants your unit a temporary +50% movement speed burst to reinforce frontline positions faster.\n• In Combat: Spawns an immediate multi-projectile or strike burst (up to 10 bonus rapid-attacks per action) directed at the nearest threat.",
          ),
          _buildInstructionBullet(
            title: "💬 Chat Commenting Routes (3 Ways to Direct)",
            desc: "1. Reply to live game status alerts.\n2. Target player comment text lines to follow up their action chain.\n3. Type a direct chat message containing the target username.",
          ),
          _buildInstructionBullet(
            title: "📜 Live Battlefield Tactical Commands",
            desc: "• 'revive @username' — Moves your unit into position to form a pooling magic resurrection circle over a fallen player's ghost.\n• 'cover @username' or 'guard @username' (Shortcuts: 'c' / 'g') — Forces interceptor bodyguard mode, continuously engaging threats entering that ally's danger path.\n• 'cancel' — Breaks active special assignments to clear your path back to main up-marching combat lines.",
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialHeader(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: _mediumBrown.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: GoogleFonts.cinzel(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: _darkBrown,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildClassOnboardingCard({
    required IconData icon,
    required String className,
    required String details,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _mediumBrown.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 6),
          Text(
            className,
            style: GoogleFonts.cinzel(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _darkBrown,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            details,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _darkBrown.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionBullet({required String title, required String desc}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "• $title",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _darkBrown,
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              desc,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _darkBrown.withValues(alpha: 0.75),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
