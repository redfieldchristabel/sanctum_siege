import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'relay_client.dart';
import 'components/arena_background.dart';
import 'components/devil_soldier.dart';
import 'components/devil_king.dart';
import 'components/angel_soldier.dart';
import 'components/angel_queen.dart';
import 'components/projectile.dart';

/// Game phases
enum GamePhase { idle, countdown, fighting, gameOver, victory }

/// Sanctum Siege — TikTok interactive live game.
///
/// Flow:
///   1. idle — Queen visible, angels can join, nothing fights
///   2. countdown — admin sends `game_start`, 3s timer, admin queues waves
///   3. fighting — queued waves deploy, combat active, King attacks
///   4. gameOver — Queen died
///   5. victory — King died
class SanctumSiegeGame extends FlameGame {
  late final RelayClient _relay;

  GamePhase _phase = GamePhase.idle;
  double _countdownTimer = 0;
  static const double countdownDuration = 3.0; // 7 in prod

  // Shoot cooldowns
  final Map<Component, double> _shootTimers = {};

  // Wave queue — admin queues during countdown, they deploy in fighting
  final List<String> _waveQueue = [];

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
    world.add(AngelQueen()..position = Vector2(360, 1220));
    // King (visible but doesn't fight until fighting phase)
    world.add(DevilKing()..position = Vector2(360, 70));
    // (rampart guards removed — only spawn via wave) 

    // Relay
    _relay = RelayClient(
      url: 'ws://localhost:8080',
      onEvent: _handleEvent,
    );
    _relay.connect();

    print('[game] ★ IDLE — Waiting for admin to start game');
  }

  // ─── UPDATE LOOP ──────────────────────────────────────────

  @override
  void update(double dt) {
    if (_phase == GamePhase.gameOver || _phase == GamePhase.victory) return;
    super.update(dt);

    if (_phase == GamePhase.countdown) {
      _countdownTimer -= dt;
      if (_countdownTimer <= 0) {
        _startFighting();
      }
      return; // no combat during countdown
    }

    if (_phase == GamePhase.fighting) {
      _processCombat(dt);
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
    print('[game] ★ COUNTDOWN ${countdownDuration}s — admin, queue your waves!');
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

  // ─── COMBAT (CoC-style: walk toward nearest enemy, stop to shoot) ──

  void _processCombat(double dt) {
    final angels = world.children.whereType<AngelSoldier>().where((c) => c.isMounted).toList();
    final devils = world.children.whereType<DevilSoldier>().where((c) => c.isMounted).toList();
    final queen = world.children.whereType<AngelQueen>().where((c) => c.isMounted).firstOrNull;
    final king = world.children.whereType<DevilKing>().where((c) => c.isMounted).firstOrNull;

    final allAngelTargets = [...devils, if (king != null) king];
    final allDevilTargets = [...angels, if (queen != null) queen];

    // Angels: find nearest devil, walk toward it or stop in range
    for (final a in angels) {
      final nearestPos = _findNearestPos(a.position, allAngelTargets);
      if (nearestPos != null) {
        final dist = a.position.distanceTo(nearestPos);
        if (dist <= angelRange) {
          a.moveTarget = null; // stop, in range to shoot
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
          d.moveTarget = null; // stop, in range to shoot
        } else {
          d.moveTarget = nearestPos.clone(); // walk toward
        }
      } else {
        d.moveTarget = null; // no enemies — default move down
      }
    }

    // Fire projectiles
    for (final a in angels) {
      _updateShooter(dt, a, allAngelTargets, angelRange, angelInterval, isAngel: true);
    }
    for (final d in devils) {
      _updateShooter(dt, d, allDevilTargets, devilRange, devilInterval, isAngel: false);
    }
    if (king != null) {
      _updateShooter(dt, king, allDevilTargets, kingRange, kingInterval, isAngel: false);
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

  void _updateShooter(double dt, Component shooter, List<Component> targets,
      double range, double interval, {required bool isAngel}) {
    final timer = _shootTimers.putIfAbsent(shooter, () => 0);
    _shootTimers[shooter] = timer + dt;

    Component? closest;
    double closestDist = range;
    for (final t in targets) {
      if (!t.isMounted) continue;
      final d = (shooter as dynamic).position.distanceTo((t as dynamic).position);
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
        world.add(Projectile.angel(
          startX: sp.x as double,
          startY: (sp.y as double) - 20,
          targetX: tp.x as double,
          targetY: tp.y as double,
        ));
      } else {
        world.add(Projectile.devil(
          startX: sp.x as double,
          startY: (sp.y as double) - 20,
          targetX: tp.x as double,
          targetY: tp.y as double,
        ));
      }
    }
  }

  void _checkProjectileHits() {
    final projectiles = world.children.whereType<Projectile>().where((c) => c.isMounted).toList();
    final devils = world.children.whereType<DevilSoldier>().where((c) => c.isMounted).toList();
    final angels = world.children.whereType<AngelSoldier>().where((c) => c.isMounted).toList();
    final queen = world.children.whereType<AngelQueen>().where((c) => c.isMounted).firstOrNull;
    final king = world.children.whereType<DevilKing>().where((c) => c.isMounted).firstOrNull;

    for (final p in projectiles) {
      if (!p.isMounted) continue;
      bool hit = false;

      for (final d in devils) {
        if (!d.isMounted) continue;
        if (p.position.distanceTo(d.position) < 28) {
          p.removeFromParent();
          d.takeDamage(1);
          hit = true;
          break;
        }
      }
      if (hit) continue;

      if (king != null && king.isMounted) {
        if (p.position.distanceTo(king.position) < 36) {
          p.removeFromParent();
          king.takeDamage(1);
          continue;
        }
      }

      for (final a in angels) {
        if (!a.isMounted) continue;
        if (p.position.distanceTo(a.position) < 28) {
          p.removeFromParent();
          a.takeDamage(1);
          hit = true;
          break;
        }
      }
      if (hit) continue;

      if (queen != null && queen.isMounted) {
        if (p.position.distanceTo(queen.position) < 36) {
          p.removeFromParent();
          queen.takeDamage(1);
        }
      }
    }
  }

  void _checkWinLose() {
    final queen = world.children.whereType<AngelQueen>().where((c) => c.isMounted).firstOrNull;
    final king = world.children.whereType<DevilKing>().where((c) => c.isMounted).firstOrNull;

    if (queen == null && _phase == GamePhase.fighting) {
      _phase = GamePhase.gameOver;
      print('[game] ★ GAME OVER — Queen slain!');
    }
    if (king == null && queen != null && _phase == GamePhase.fighting) {
      _phase = GamePhase.victory;
      print('[game] ★ VICTORY — Devil King defeated!');
    }
  }

  // ─── RELAY EVENTS ─────────────────────────────────────────

  void _handleEvent(String event, Map<String, dynamic> data, String source) {
    if (_phase == GamePhase.gameOver || _phase == GamePhase.victory) return;

    switch (event) {
      case 'game_start':
        _startCountdown();
        break;

      case 'join':
        // Angels can join at any time (idle, countdown, fighting)
        final name = data['username'] as String? ?? 'Angel';
        final userId = data['userId'] as String? ?? 'anon';
        _spawnAngel(userId, name);
        break;

      case 'spawn_wave':
        final difficulty = data['difficulty'] as String? ?? 'normal';
        if (_phase == GamePhase.countdown) {
          // Queue waves during countdown, deploy when fighting starts
          _waveQueue.add(difficulty);
          print('[game] wave queued: $difficulty (${_waveQueue.length} total)');
        } else if (_phase == GamePhase.fighting) {
          // Instant spawn during combat
          _spawnDevilWave(difficulty);
        } else {
          print('[game] cannot spawn wave in $_phase phase');
        }
        break;

      case 'spawn_angel':
        final count = data['count'] as int? ?? 1;
        for (int i = 0; i < count; i++) _spawnAngel('dev_$i', 'Dev Angel');
        break;

      case 'dev_config':
        print('[game] config: ${data['key']} = ${data['value']}');
        break;

      default:
        break;
    }
  }

  // ─── SPAWNING ─────────────────────────────────────────────

  void _spawnAngel(String userId, String username) {
    final rng = Random();
    world.add(AngelSoldier(userId: userId, username: username)
      ..position = Vector2(60 + rng.nextDouble() * 600, 900 + rng.nextDouble() * 200));
    print('[game] $username joined → Angel spawned');
  }

  void _spawnDevilWave(String difficulty) {
    final rng = Random();
    final count = switch (difficulty) { 'hard' => 6, 'boss' => 5, _ => 3 };
    print('[game] spawning $difficulty wave ($count devils)');

    for (int i = 0; i < count; i++) {
      final isBoss = difficulty == 'boss' && i == 0;
      final devilHp = isBoss ? 15 : (difficulty == 'hard' ? 5 : 3);
      final devil = DevilSoldier(phase: rng.nextDouble() * 6, hp: devilHp)
        ..position = Vector2(40 + rng.nextDouble() * 640, 40 + rng.nextDouble() * 300);
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
