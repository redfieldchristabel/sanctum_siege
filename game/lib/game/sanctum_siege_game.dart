import 'dart:math';
import 'package:flutter/painting.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'relay_client.dart';
import 'components/arena_background.dart';
import 'components/devil_soldier.dart';
import 'components/devil_king.dart';
import 'components/angel_soldier.dart';
import 'components/sunfletcher.dart';
import 'components/angel_knight.dart';
import 'components/angel_queen.dart';
import 'components/projectile.dart';

/// Game phases
enum GamePhase { idle, countdown, fighting, gameOver, victory }

/// A revive-in-progress. Multiple viewers can revive the same ghost —
/// their soldiers all walk there and pool their likes together.
class ReviveSession {
  /// Username of the dead soldier (ghost).
  final String ghostUsername;

  /// All alive viewers currently attempting to revive this ghost.
  final List<ReviverSlot> revivers = [];

  /// How many likes accumulated so far (pooled across all revivers in range).
  int likesAccumulated = 0;

  /// Required likes to complete: 10 for archer, 3 for healer (future).
  final int threshold;

  /// True if the ghost's owner (the dead viewer) typed the revive command.
  final bool isOwnerRevive;

  /// Whether this session is still active.
  bool isActive = true;

  /// Time elapsed since session start.
  double elapsed = 0;

  /// Whether the UFO beam should play (just completed).
  bool justCompleted = false;
  double beamTimer = 0;
  static const double beamDuration = 1.0;

  ReviveSession({
    required this.ghostUsername,
    required String reviverUserId,
    required String reviverUsername,
    required this.threshold,
    this.isOwnerRevive = false,
  }) {
    revivers.add(ReviverSlot(userId: reviverUserId, username: reviverUsername));
  }

  double get progress => (likesAccumulated / threshold).clamp(0.0, 1.0);
  bool get isComplete => likesAccumulated >= threshold;

  /// True when at least one reviver is within revive range.
  bool get anyInRange => revivers.any((r) => r.isInRange);

  /// Add another viewer to this revive session.
  void addReviver(String userId, String username) {
    if (revivers.any((r) => r.userId == userId)) return; // already in
    revivers.add(ReviverSlot(userId: userId, username: username));
  }

  /// Remove a reviver (e.g. they died or left).
  void removeReviver(String userId) {
    revivers.removeWhere((r) => r.userId == userId);
  }

  /// Free all revivers — call when session ends.
  void freeAll() {
    isActive = false;
  }
}

/// One soldier participating in a revive ritual.
class ReviverSlot {
  final String userId;
  final String username;

  /// True when this reviver is within their class's revive range.
  bool isInRange = false;

  ReviverSlot({required this.userId, required this.username});
}

/// An overlay component that renders VICTORY / DEFEAT text on the canvas.
/// Added to the world when the game ends; removed on next_match.
class _EndGameOverlay extends PositionComponent {
  final String title;
  final bool isVictory;
  double _time = 0;

  _EndGameOverlay({required this.title, required this.isVictory})
      : super(size: Vector2(720, 1280));

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    final pulse = sin(_time * 2.0) * 0.06 + 0.94;
    final cx = size.x / 2;
    final cy = size.y / 2 - 40;

    // Large title text
    final titleStyle = TextStyle(
      color: isVictory
          ? const Color(0xFFFFD700).withValues(alpha: pulse)
          : const Color(0xFFCC2222).withValues(alpha: pulse),
      fontSize: 64,
      fontWeight: FontWeight.w900,
      letterSpacing: 6,
    );
    final titleTp = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    titleTp.paint(canvas, Offset(cx - titleTp.width / 2, cy - titleTp.height / 2));

    // Subtitle
    final subStyle = TextStyle(
      color: const Color(0xCCCCDDAA).withValues(alpha: pulse * 0.8),
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 2,
    );
    final subTp = TextPainter(
      text: TextSpan(text: "Type 'next' to continue", style: subStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    subTp.paint(canvas, Offset(cx - subTp.width / 2, cy + 50));

    // Decorative border glow
    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (isVictory ? const Color(0xFFFFD700) : const Color(0xFFCC2222))
              .withValues(alpha: 0.15 * pulse),
          const Color(0x00000000),
        ],
      ).createShader(Rect.fromLTWH(0, cy - 80, size.x, 160));
    canvas.drawRect(Rect.fromLTWH(0, cy - 80, size.x, 160), glowPaint);
  }
}

/// Sanctum Siege — TikTok interactive live game.
///
/// Flow:
///   1. idle — Queen visible, angels can join, nothing fights
///   2. countdown — admin sends `game_start`, 3s timer, admin queues waves
///   3. fighting — queued waves deploy, combat active, King attacks
///   4. gameOver — Queen died
///   5. victory — King died
///
/// [onGameOver] is called when the admin sends `next_match` after the game ends,
/// allowing the host screen to return to the lobby with preserved gifter points.
class SanctumSiegeGame extends FlameGame {
  final VoidCallback? onGameOver;
  late final RelayClient _relay;

  /// Usernames of the 18 elite soldiers from the lobby.
  final List<String> _lobbyUsernames;

  /// Class assignments from the lobby phase (username → 'sunfletcher'/'melee').
  final Map<String, String> _classAssignments;

  SanctumSiegeGame({
    this._lobbyUsernames = const [],
    this._classAssignments = const {},
    this.onGameOver,
  });
  GamePhase _phase = GamePhase.idle;
  double _countdownTimer = 0;
  static const double countdownDuration = 3.0; // 7 in prod

  // Shoot cooldowns
  final Map<Component, double> _shootTimers = {};

  // Wave queue — admin queues during countdown, they deploy in fighting
  final List<String> _waveQueue = [];

  // ── Revive system ─────────────────────────────────────────
  /// Active revive sessions, keyed by ghost username.
  final Map<String, ReviveSession> _reviveSessions = {};

  /// Set of userIds that left the stream mid-match (no re-entry).
  final Set<String> _leftUsers = {};

  static const double magicCircleDuration = 0.5;

  static const double angelRange = 280.0;
  static const double angelInterval = 1.5;
  static const double devilRange = 250.0;
  static const double devilInterval = 1.8;
  static const double kingRange = 400.0;
  static const double kingInterval = 0.6;

  // ─── ON LOAD ──────────────────────────────────────────────

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Force camera to show exactly 720x1280 game world, (0,0) = top-left
    camera.viewfinder.visibleGameSize = Vector2(720, 1280);
    camera.viewfinder.anchor = Anchor.topLeft;
    world.add(ArenaBackground());

    // Queen (passive, always visible)
    world.add(AngelQueen()..position = Vector2(360, 1255));
    // King (visible but doesn't fight until fighting phase)
    world.add(DevilKing()..position = Vector2(360, 70));
    // (rampart guards removed — only spawn via wave)

    // Spawn angels from lobby-selected players
    if (_lobbyUsernames.isNotEmpty) {
      print(
        '[game] Spawning ${_lobbyUsernames.length} elite soldiers from lobby',
      );
      for (final name in _lobbyUsernames) {
        _spawnAngelFromLobby(name);
      }
    }

    // Relay
    _relay = RelayClient(url: 'ws://localhost:8080', onEvent: _handleEvent);
    _relay.connect();

    if (_lobbyUsernames.isNotEmpty) {
      print('[game] ★ Lobby deployed — auto-starting countdown');
      _startCountdown();
    } else {
      print('[game] ★ IDLE — Waiting for admin to start game');
    }
  }

  // ─── UPDATE LOOP ──────────────────────────────────────────

  @override
  void update(double dt) {
    // Always run super so components keep rendering (esp. the end-game overlay)
    super.update(dt);

    if (_phase == GamePhase.gameOver || _phase == GamePhase.victory) return;

    if (_phase == GamePhase.countdown) {
      _countdownTimer -= dt;
      if (_countdownTimer <= 0) {
        _startFighting();
      }
      return; // no combat during countdown
    }

    if (_phase == GamePhase.fighting) {
      _processRevives(dt);
      _processCombat(dt);
      _processMeleeCombat(dt);
      _checkProjectileHits();
      _checkWinLose();
    }
  }

  // ─── PHASE TRANSITIONS ────────────────────────────────────

  void _startCountdown() {
    if (_phase != GamePhase.idle) return;
    _phase = GamePhase.countdown;
    _countdownTimer = countdownDuration;
    _waveQueue.clear();
    print(
      '[game] ★ COUNTDOWN ${countdownDuration}s — admin, queue your waves!',
    );
  }

  void _startFighting() {
    _phase = GamePhase.fighting;
    print('[game] ★ FIGHT! Deploying ${_waveQueue.length} queued wave(s)');

    // Save queue before clearing — Future.delayed runs later
    final waves = List<String>.from(_waveQueue);
    _waveQueue.clear();

    // Deploy all queued waves with small stagger
    for (int i = 0; i < waves.length; i++) {
      Future.delayed(Duration(milliseconds: i * 800), () {
        if (_phase == GamePhase.fighting) {
          _spawnDevilWave(waves[i]);
        }
      });
    }
  }

  // ─── REVIVE SYSTEM ──────────────────────────────────────────

  /// Process all active revive sessions each frame.
  void _processRevives(double dt) {
    final sessions = List<ReviveSession>.from(
      _reviveSessions.values,
    ).where((s) => s.isActive).toList();

    for (final session in sessions) {
      session.elapsed += dt;

      // Handle beam animation after completion
      if (session.justCompleted) {
        session.beamTimer += dt;
        if (session.beamTimer >= ReviveSession.beamDuration) {
          _completeRevive(session);
        }
        continue;
      }

      // Look up the ghost
      final ghost = _findGhost(session.ghostUsername);
      if (ghost == null || !ghost.isMounted) {
        session.freeAll();
        continue;
      }

      // Update each reviver: check alive + distance to ghost
      bool anyAlive = false;
      for (final slot in session.revivers.toList()) {
        final reviver = _findAngelByUserId(
          slot.userId,
          username: slot.username,
        );
        if (reviver == null || !reviver.isMounted || !reviver.isAlive) {
          print(
            '[revive] Reviver ${slot.username} died — removed from session',
          );
          reviver?.cancelRevive();
          session.removeReviver(slot.userId);
          continue;
        }
        anyAlive = true;

        // Walk to ghost (only once)
        if (!reviver.isReviving) {
          reviver.setReviveTarget(ghost.position.clone());
        }

        // Check if in revive range (close enough for current class)
        final dist = reviver.position.distanceTo(ghost.position);
        slot.isInRange = dist <= 50; // archer range; future: class-based
      }

      // If no revivers left alive, cancel the session
      if (!anyAlive) {
        print('[revive] No revivers left — cancel');
        ghost.isBeingRevived = false;
        session.freeAll();
        continue;
      }

      // Show magic circle + count likes only when at least one reviver is in range
      ghost.isBeingRevived = session.anyInRange;
      ghost.reviveProgress = session.progress;

      // Check completion
      if (session.isComplete) {
        session.justCompleted = true;
        session.beamTimer = 0;
        ghost.reviveBeamTimer = 0.001;
        ghost.isBeingRevived = false;
        final names = session.revivers.map((r) => r.username).join(', ');
        print('[revive] ★ ${session.ghostUsername} revived by $names!');
      }
    }

    // Cleanup inactive sessions
    _reviveSessions.removeWhere((_, s) => !s.isActive);
  }

  /// Find a ghost angel soldier by username.
  AngelSoldier? _findGhost(String username) {
    return world.children
        .whereType<AngelSoldier>()
        .where(
          (c) =>
              c.isMounted &&
              c.state == SoldierState.ghost &&
              c.username == username,
        )
        .firstOrNull;
  }

  /// Find an alive angel soldier by userId, falling back to username for dev.
  AngelSoldier? _findAngelByUserId(String userId, {String? username}) {
    // Try exact userId first (real TikTok flow)
    final exact = world.children
        .whereType<AngelSoldier>()
        .where((c) => c.isMounted && c.isAlive && c.userId == userId)
        .firstOrNull;
    if (exact != null) return exact;
    // Fallback: lookup by username (dev CLI flow where userId != soldier.userId)
    if (username != null) {
      return world.children
          .whereType<AngelSoldier>()
          .where((c) => c.isMounted && c.isAlive && c.username == username)
          .firstOrNull;
    }
    return null;
  }

  /// Complete the revive: restore ghost to alive and free all revivers.
  void _completeRevive(ReviveSession session) {
    final ghost = _findGhost(session.ghostUsername);
    if (ghost != null && ghost.isMounted) {
      ghost.revive(fullHp: session.isOwnerRevive);
      print('[revive] ✓ ${session.ghostUsername} is back!');
    }
    // Free all revivers so they can return to combat
    for (final slot in session.revivers) {
      final reviver = _findAngelByUserId(slot.userId, username: slot.username);
      reviver?.cancelRevive();
    }
    session.freeAll();
  }

  /// Start a revive session when a viewer types "revive @username".
  /// Multiple viewers can revive the same ghost — their soldiers pool likes.
  void _startRevive(
    String ghostUsername,
    String reviverUserId,
    String reviverUsername,
  ) {
    // Check ghost exists
    final ghost = _findGhost(ghostUsername);
    if (ghost == null) {
      print('[revive] Ghost $ghostUsername not found');
      return;
    }

    // Check existing session — add reviver to it
    final existing = _reviveSessions[ghostUsername];
    if (existing != null) {
      existing.addReviver(reviverUserId, reviverUsername);
      print(
        '[revive] $reviverUsername joins existing revive for $ghostUsername (${existing.revivers.length} revivers)',
      );
      return;
    }

    final isOwner = ghost.userId == reviverUserId;
    print(
      '[revive] ${isOwner ? "OWNER" : "VIEWER"} $reviverUsername → revive $ghostUsername',
    );

    _reviveSessions[ghostUsername] = ReviveSession(
      ghostUsername: ghostUsername,
      reviverUserId: reviverUserId,
      reviverUsername: reviverUsername,
      threshold: 10, // archer class
      isOwnerRevive: isOwner,
    );

    // Broadcast trigger for viewers to act upon
    print('📢 [SYSTEM] LIVE ALERTS: Player $reviverUsername is reviving $ghostUsername! Send "cover $reviverUsername" or "c" to clear their lane!');
  }

  /// Contribute likes to any revive where the liker is a reviver.
  /// Only counts if at least one reviver is in range.
  void _contributeLikesToRevive(String userId, int count) {
    for (final session in _reviveSessions.values) {
      if (!session.isActive) continue;
      final slot = session.revivers
          .where((r) => r.userId == userId)
          .firstOrNull;
      if (slot == null) continue;
      // Only count if at least one reviver is in revive range
      if (!session.anyInRange) return;
      session.likesAccumulated += count;
      print(
        '[revive] +$count likes → ${session.ghostUsername} (${session.likesAccumulated}/${session.threshold})',
      );
    }
  }

  /// Route likes intelligently: alive soldiers get combat bursts or speed boost,
  /// dead ghosts feed the revive meter.
  void _handleLikeEvent(LikeEvent e) {
    final soldier = _findAngelByUserId(e.userId, username: null);
    if (soldier == null || !soldier.isAlive) {
      // Dead / not found — route to revive system as before
      _contributeLikesToRevive(e.userId, e.count);
      return;
    }

    // Build target list (devils + king)
    final devils = world.children
        .whereType<DevilSoldier>()
        .where((c) => c.isMounted && c.isActiveCombatant)
        .toList();
    final king = world.children
        .whereType<DevilKing>()
        .where((c) => c.isMounted)
        .firstOrNull;
    final targets = [...devils, if (king != null) king];

    // Find nearest threat
    final nearest = _findNearestPos(soldier.position, targets);

    if (nearest != null) {
      final attackRange = soldier.isMelee ? soldier.meleeRange : angelRange;
      final dist = soldier.position.distanceTo(nearest);

      if (dist <= attackRange) {
        // CONDITION A: In combat — spawn extra projectiles (capped at 10)
        final count = e.count.clamp(1, 10);
        for (int i = 0; i < count; i++) {
          world.add(
            Projectile.angel(
              startX: soldier.position.x,
              startY: soldier.position.y - 40,
              targetX: nearest.x,
              targetY: nearest.y,
            ),
          );
        }
        print('[likes] ${soldier.username} fires $count bonus shots!');
        return;
      }
    }

    // CONDITION B: Out of combat — apply speed boost (0.1s per like, capped at 3s)
    final duration = e.count * 0.1;
    soldier.applySpeedBoost(duration);
    print('[likes] ${soldier.username} speed boosted +${duration}s');
  }

  /// Parse a chat comment for revive/cover/cancel commands.
  void _handleComment(CommentEvent e) {
    if (_phase != GamePhase.fighting) return;
    if (_leftUsers.contains(e.userId)) return;

    final text = e.text.trim();
    final lower = text.toLowerCase();

    // 1. UNIFIED CANCELLATION CHECK
    if (lower == 'cancel' || lower == 'cancel revive' || lower == 'cancel cover') {
      final soldier = _findAngelByUserId(e.userId, username: e.username);
      if (soldier != null) {
        soldier.cancelRevive();
        soldier.coverTarget = null;
        print('[game] ${e.username} stopped all active actions');
      }
      for (final session in _reviveSessions.values) {
        if (!session.isActive) continue;
        session.removeReviver(e.userId);
        if (session.revivers.isEmpty) {
          session.freeAll();
          final ghost = _findGhost(session.ghostUsername);
          if (ghost != null) ghost.isBeingRevived = false;
        }
      }
      return;
    }

    // 2. SHORTCUT PROTECTION RULE: Block simple "r" for base classes
    final shortReviveMatch = RegExp(r'^r\s+@?(\S+)', caseSensitive: false).firstMatch(text);
    if (shortReviveMatch != null) {
      print('⚠️ [REJECTED] Shortcut "r" is locked. Full word "revive" is required for your class specialty!');
      return;
    }

    // Standard longform revive check
    final reviveMatch = RegExp(r'^revive\s+@?(\S+)', caseSensitive: false).firstMatch(text);
    if (reviveMatch != null) {
      final ghostUsername = reviveMatch.group(1)!;
      _startRevive(ghostUsername, e.userId, e.username);
      return;
    }

    // 3. THE INTERCEPTOR ENGAGEMENT INTERFACE (cover, guard, c, g)
    final coverMatch = RegExp(r'^(cover|guard|c|g)(?:\s+@?(\S+))?$', caseSensitive: false).firstMatch(text);
    if (coverMatch != null) {
      final targetUsername = coverMatch.group(2);
      final mySoldier = _findAngelByUserId(e.userId, username: e.username);

      if (mySoldier == null || !mySoldier.isAlive) return;

      AngelSoldier? allyToProtect;

      if (targetUsername != null && targetUsername.isNotEmpty) {
        // Context A: Explicit name assignment lookup
        allyToProtect = world.children
            .whereType<AngelSoldier>()
            .where((c) => c.isMounted && c.isAlive && c.username.toLowerCase() == targetUsername.toLowerCase())
            .firstOrNull;
      } else {
        // Context B: Reply fallback -> find any teammate actively carrying out a revival target sequence
        allyToProtect = world.children
            .whereType<AngelSoldier>()
            .where((c) => c.isMounted && c.isAlive && c.isReviving)
            .firstOrNull;

        // Context C: If no active channels found, find any unit listed inside current active revive slots
        if (allyToProtect == null) {
          for (final session in _reviveSessions.values) {
            if (!session.isActive) continue;
            for (final slot in session.revivers) {
              final activeReviver = _findAngelByUserId(slot.userId, username: slot.username);
              if (activeReviver != null && activeReviver.isAlive) {
                allyToProtect = activeReviver;
                break;
              }
            }
            if (allyToProtect != null) break;
          }
        }
      }

      if (allyToProtect != null && allyToProtect != mySoldier) {
        mySoldier.cancelRevive(); // Exit existing streams/actions
        mySoldier.coverTarget = allyToProtect; // Lock tracking onto the savior
        print('🛡️ [DEFENSE ACTIVE] ${mySoldier.username} is now actively intercepting threats around ${allyToProtect.username}!');
      }
      return;
    }
  }

  /// Handle a viewer leaving the stream mid-match.
  void _handleLeave(String userId) {
    if (_phase != GamePhase.fighting) return;

    _leftUsers.add(userId);
    print('[game] $userId left the battle');

    // Remove this user from any active revive session
    for (final session in _reviveSessions.values) {
      if (!session.isActive) continue;
      final slot = session.revivers
          .where((r) => r.userId == userId)
          .firstOrNull;
      if (slot == null) continue;
      final reviver = _findAngelByUserId(userId, username: slot.username);
      reviver?.cancelRevive();
      session.removeReviver(userId);
      if (session.revivers.isEmpty) {
        session.freeAll();
        final ghost = _findGhost(session.ghostUsername);
        if (ghost != null) ghost.isBeingRevived = false;
      }
      print(
        '[game] Reviver $userId left — ${session.revivers.length} reviver(s) remain',
      );
    }

    // Find all soldiers (alive or ghost) owned by this user
    final soldiers = world.children
        .whereType<AngelSoldier>()
        .where((c) => c.isMounted && c.userId == userId)
        .toList();

    for (final s in soldiers) {
      if (s.isAlive) {
        s.moveTarget = Vector2(s.position.x, -100);
        s.cancelRevive();
        print('[game] ${s.username} flees from battle');
      } else if (s.state == SoldierState.ghost) {
        s.removeFromParent();
        print('[game] ${s.username}\'s ghost fades away');
      }
    }
  }

  void _processCombat(double dt) {
    final angels = world.children
        .whereType<AngelSoldier>()
        .where((c) => c.isMounted && c.isActiveCombatant && !c.isMelee)
        .toList();
    // Revivers are excluded from combat (no walk/shoot) but ARE targetable
    final allAliveAngels = world.children
        .whereType<AngelSoldier>()
        .where((c) => c.isMounted && c.isAlive)
        .toList();
    final devils = world.children
        .whereType<DevilSoldier>()
        .where((c) => c.isMounted && c.isActiveCombatant)
        .toList();
    final queen = world.children
        .whereType<AngelQueen>()
        .where((c) => c.isMounted)
        .firstOrNull;
    final king = world.children
        .whereType<DevilKing>()
        .where((c) => c.isMounted)
        .firstOrNull;

    final allAngelTargets = [...devils, if (king != null) king];
    final allDevilTargets = [...allAliveAngels, if (queen != null) queen];

    // Angels: find nearest devil, walk toward it or stop in range
    for (final a in angels) {
      if (a.coverTarget != null) continue; // Bodyguards are managed by their interceptor brain updates
      final nearestPos = _findNearestPos(a.position, allAngelTargets);
      if (nearestPos != null) {
        final dist = a.position.distanceTo(nearestPos);
        if (dist <= angelRange) {
          a.moveTarget = a.position.clone(); // stop in place
        } else {
          a.moveTarget = nearestPos.clone(); // walk toward
        }
      } else {
        a.moveTarget = null; // no enemies — default move up
      }
    }

    // Devils: find nearest angel target, walk toward it or stop in range
    for (final d in devils) {
      final nearestPos = _findNearestPos(d.position, allDevilTargets);
      if (nearestPos != null) {
        final dist = d.position.distanceTo(nearestPos);
        if (dist <= devilRange) {
          d.moveTarget = d.position.clone(); // stop in place
        } else {
          d.moveTarget = nearestPos.clone(); // walk toward
        }
      } else {
        d.moveTarget = null; // no enemies — default move down
      }
    }

    // Fire projectiles
    for (final a in angels) {
      _updateShooter(
        dt,
        a,
        allAngelTargets,
        angelRange,
        angelInterval,
        isAngel: true,
      );
    }
    for (final d in devils) {
      _updateShooter(
        dt,
        d,
        allDevilTargets,
        devilRange,
        devilInterval,
        isAngel: false,
      );
    }
    if (king != null) {
      _updateShooter(
        dt,
        king,
        allDevilTargets,
        kingRange,
        kingInterval,
        isAngel: false,
      );
    }
  }

  /// Find the nearest enemy position.
  Vector2? _findNearestPos(Vector2 from, List<Component> targets) {
    Vector2? bestPos;
    double bestDist = double.infinity;
    for (final t in targets) {
      if (!t.isMounted) continue;
      final tpos = (t is PositionComponent) ? t.position : null;
      if (tpos == null) continue;
      final d = from.distanceTo(tpos);
      if (d < bestDist) {
        bestDist = d;
        bestPos = tpos;
      }
    }
    return bestPos;
  }

  /// Process melee-class soldier attacks — direct damage, no projectiles.
  final Map<Component, double> _meleeTimers = {};

  void _processMeleeCombat(double dt) {
    final melee = world.children
        .whereType<AngelKnight>()
        .where((c) => c.isMounted && c.isActiveCombatant)
        .toList();
    final devils = world.children
        .whereType<DevilSoldier>()
        .where((c) => c.isMounted && c.isActiveCombatant)
        .toList();
    final king = world.children
        .whereType<DevilKing>()
        .where((c) => c.isMounted)
        .firstOrNull;

    final targets = [...devils, if (king != null) king];

    for (final m in melee) {
      if (m.coverTarget != null) {
        // Interceptor Mode: If an enemy gets in close range while I protect my ally, smash them!
        final nearest = _findNearestPos(m.position, targets);
        if (nearest != null && m.position.distanceTo(nearest) <= m.meleeRange) {
          final timer = _meleeTimers.putIfAbsent(m, () => 0);
          _meleeTimers[m] = timer + dt;
          if (_meleeTimers[m]! >= m.meleeInterval) {
            _meleeTimers[m] = 0;
            Component? hitTarget;
            double bestDist = m.meleeRange;
            for (final t in targets) {
              if (!t.isMounted) continue;
              final d = m.position.distanceTo((t as dynamic).position);
              if (d < bestDist) {
                bestDist = d;
                hitTarget = t;
              }
            }
            if (hitTarget != null) {
              (hitTarget as dynamic).takeDamage(m.meleeDamage);
              print('[melee interceptor] ${m.username} struck threat near ${m.coverTarget!.username}!');
            }
          }
        }
        continue; // Skip baseline automated forward movement
      }

      final nearest = _findNearestPos(m.position, targets);
      if (nearest == null) {
        m.moveTarget = null; // no enemies — default move up
        continue;
      }

      final dist = m.position.distanceTo(nearest);
      if (dist <= m.meleeRange) {
        // In range — stop and attack
        m.moveTarget = m.position.clone();
        final timer = _meleeTimers.putIfAbsent(m, () => 0);
        _meleeTimers[m] = timer + dt;
        if (_meleeTimers[m]! >= m.meleeInterval) {
          _meleeTimers[m] = 0;
          // Find nearest enemy component to damage
          Component? hitTarget;
          double bestDist = m.meleeRange;
          for (final t in targets) {
            if (!t.isMounted) continue;
            final d = m.position.distanceTo((t as dynamic).position);
            if (d < bestDist) {
              bestDist = d;
              hitTarget = t;
            }
          }
          if (hitTarget != null) {
            (hitTarget as dynamic).takeDamage(m.meleeDamage);
            m.triggerAttack();
            print('[melee] ${m.username} slashes for ${m.meleeDamage} damage');
          }
        }
      } else {
        // Walk toward nearest enemy
        m.moveTarget = nearest.clone();
      }
    }
  }

  void _updateShooter(
    double dt,
    Component shooter,
    List<Component> targets,
    double range,
    double interval, {
    required bool isAngel,
  }) {
    final timer = _shootTimers.putIfAbsent(shooter, () => 0);
    _shootTimers[shooter] = timer + dt;

    Component? closest;
    double closestDist = range;
    for (final t in targets) {
      if (!t.isMounted) continue;
      final d = (shooter as dynamic).position.distanceTo(
        (t as dynamic).position,
      );
      if (d < closestDist) {
        closestDist = d;
        closest = t;
      }
    }

    if (closest != null && _shootTimers[shooter]! >= interval) {
      _shootTimers[shooter] = 0;
      final sp = (shooter as dynamic).position;
      final tp = (closest as dynamic).position;
      if (isAngel) {
        world.add(
          Projectile.angel(
            startX: sp.x as double,
            startY: (sp.y as double) - 40,
            targetX: tp.x as double,
            targetY: tp.y as double,
          ),
        );
      } else {
        world.add(
          Projectile.devil(
            startX: sp.x as double,
            startY: (sp.y as double) - 20,
            targetX: tp.x as double,
            targetY: tp.y as double,
          ),
        );
      }
    }
  }

  void _checkProjectileHits() {
    final projectiles = world.children
        .whereType<Projectile>()
        .where((c) => c.isMounted)
        .toList();
    final devils = world.children
        .whereType<DevilSoldier>()
        .where((c) => c.isMounted && c.isActiveCombatant)
        .toList();
    final angels = world.children
        .whereType<AngelSoldier>()
        .where((c) => c.isMounted && c.isAlive)
        .toList();
    final queen = world.children
        .whereType<AngelQueen>()
        .where((c) => c.isMounted)
        .firstOrNull;
    final king = world.children
        .whereType<DevilKing>()
        .where((c) => c.isMounted)
        .firstOrNull;

    for (final p in projectiles) {
      if (!p.isMounted) continue;

      if (p.isAngel) {
        // Angel projectiles hit devils + king
        for (final d in devils) {
          if (!d.isMounted) continue;
          if (p.position.distanceTo(d.position) < 24) {
            p.removeFromParent();
            d.takeDamage(1);
            break;
          }
        }
        if (!p.isMounted) continue;

        if (king != null && king.isMounted) {
          if (p.position.distanceTo(king.position) < 32) {
            p.removeFromParent();
            king.takeDamage(1);
          }
        }
      } else {
        // Devil projectiles hit angels + queen
        for (final a in angels) {
          if (!a.isMounted) continue;
          if (p.position.distanceTo(a.position) < 48) {
            p.removeFromParent();
            a.takeDamage(1);
            break;
          }
        }
        if (!p.isMounted) continue;

        if (queen != null && queen.isMounted) {
          if (p.position.distanceTo(queen.position) < 64) {
            p.removeFromParent();
            queen.takeDamage(1);
          }
        }
      }
    }
  }

  void _checkWinLose() {
    final queen = world.children
        .whereType<AngelQueen>()
        .where((c) => c.isMounted)
        .firstOrNull;
    final king = world.children
        .whereType<DevilKing>()
        .where((c) => c.isMounted)
        .firstOrNull;

    if (queen == null && _phase == GamePhase.fighting) {
      _phase = GamePhase.gameOver;
      print('[game] ★ GAME OVER — Queen slain!');
      _showEndGameOverlay('DEFEAT', false);
    }
    if (king == null && queen != null && _phase == GamePhase.fighting) {
      _phase = GamePhase.victory;
      print('[game] ★ VICTORY — Devil King defeated!');
      _showEndGameOverlay('VICTORY', true);
    }
  }

  /// Add the end-game overlay on top of everything.
  void _showEndGameOverlay(String title, bool isVictory) {
    world.add(
      _EndGameOverlay(title: title, isVictory: isVictory)
        ..priority = 9999,
    );
  }

  // ─── RELAY EVENTS ─────────────────────────────────────────

  void _handleEvent(RelayEvent event) {
    // Allow next_match even during game-over/victory
    if ((_phase == GamePhase.gameOver || _phase == GamePhase.victory) &&
        event is! NextMatchEvent) return;

    switch (event) {
      case StartGameEvent _:
      case StartMatchEvent _:
        _startCountdown();
        break;

      case SpawnWaveEvent e:
        final difficulty = e.difficulty ?? 'normal';
        if (_phase == GamePhase.countdown) {
          _waveQueue.add(difficulty);
          print('[game] wave queued: $difficulty (${_waveQueue.length} total)');
        } else if (_phase == GamePhase.fighting) {
          _spawnDevilWave(difficulty);
        } else {
          print('[game] cannot spawn wave in $_phase phase');
        }
        break;

      case SpawnAngelEvent e:
        if (e.name != null) {
          if (e.isMelee) {
            _spawnMelee(e.name!, e.name!);
          } else {
            _spawnAngel('spawn_${e.name}', e.name!);
          }
        } else {
          for (int i = 0; i < e.count; i++) {
            _spawnAngel('dev_$i', 'Dev Angel');
          }
        }
        break;

      case DevConfigEvent e:
        print('[game] config: ${e.key} = ${e.value}');
        break;

      case CommentEvent e:
        _handleComment(e);
        break;

      case LikeEvent e:
        if (_phase == GamePhase.fighting && !_leftUsers.contains(e.userId)) {
          _handleLikeEvent(e);
        }
        break;

      case KillEvent e:
        final soldier = world.children
            .whereType<AngelSoldier>()
            .where((c) => c.isMounted && c.isAlive && c.username == e.username)
            .firstOrNull;
        if (soldier != null) {
          // Use takeDamage to invoke the full ghost asset swap chain
          soldier.takeDamage(soldier.hp);
          print('[game] ${e.username} killed cleanly via dev command path');
        } else {
          print('[game] kill: ${e.username} not found or already dead');
        }
        break;

      case LeaveEvent e:
        _handleLeave(e.userId);
        break;

      case NextMatchEvent _:
        print('[game] ★ NEXT MATCH — returning to lobby');
        _relay.dispose();
        onGameOver?.call();
        break;

      default:
        break;
    }
  }

  // ─── SPAWNING ─────────────────────────────────────────────

  void _spawnAngel(String userId, String username) {
    final rng = Random();
    world.add(
      Sunfletcher(userId: userId, username: username)
        ..position = Vector2(
          60 + rng.nextDouble() * 600,
          900 + rng.nextDouble() * 200,
        ),
    );
    print('[game] $username joined → Sunfletcher spawned');
  }

  /// Spawn a melee-class angel soldier.
  void _spawnMelee(String userId, String username) {
    final rng = Random();
    world.add(
      AngelKnight(userId: userId, username: username)
        ..position = Vector2(
          60 + rng.nextDouble() * 600,
          900 + rng.nextDouble() * 200,
        ),
    );
    print('[game] Knight $username deployed');
  }

  /// Spawn an elite soldier from the lobby selection.
  /// Spreads them across the angel spawn zone in 2 rows (frontline + back).
  /// Respects class assignment: melee gets front row, archer back row.
  void _spawnAngelFromLobby(String username) {
    final rng = Random();
    final hash = username.codeUnits.fold(0, (int a, int b) => a + b);
    final isMelee = _classAssignments[username] == 'melee';
    // Melee in front (y:1080-1120), archer in back (y:1140-1180)
    final baseY = isMelee ? 1080.0 : 1140.0;
    final yOffset = (hash % 2) * 30.0 + rng.nextDouble() * 20;
    final soldier = isMelee
        ? AngelKnight(userId: 'lobby_$username', username: username)
        : Sunfletcher(userId: 'lobby_$username', username: username);
    soldier.position = Vector2(40 + (hash * 7.3 % 640), baseY + yOffset);
    world.add(soldier);
    print(
      '[game] ${isMelee ? "Melee" : "Archer"} $username deployed from lobby',
    );
  }

  void _spawnDevilWave(String difficulty) {
    final rng = Random();
    final count = switch (difficulty) {
      'hard' => 6,
      'boss' => 5,
      _ => 3,
    };
    print('[game] spawning $difficulty wave ($count devils)');

    for (int i = 0; i < count; i++) {
      final isBoss = difficulty == 'boss' && i == 0;
      final devilHp = isBoss ? 15 : (difficulty == 'hard' ? 5 : 3);
      final devil = DevilSoldier(phase: rng.nextDouble() * 6, hp: devilHp)
        ..position = Vector2(
          40 + rng.nextDouble() * 640,
          40 + rng.nextDouble() * 300,
        );
      if (isBoss) devil.scale = Vector2.all(1.8);
      world.add(devil);
    }
  }

  @override
  void onRemove() {
    _relay.dispose();
    super.onRemove();
  }
}
