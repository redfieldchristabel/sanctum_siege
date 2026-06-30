import 'dart:async';
import 'package:flutter/material.dart';
import 'persistent_storage.dart';

// ══════════════════════════════════════════════════
//  Phases
// ══════════════════════════════════════════════════

enum LobbyPhase { tutorial, ranking, classAssignment, transitioning }

// ══════════════════════════════════════════════════
//  Data Models
// ══════════════════════════════════════════════════

class LobbyPlayer {
  final String username;
  final String profilePicUrl;
  int points;
  bool isGifter; // true = sent a gift this session
  bool isFollower; // true = follows the channel (2x multiplier)

  /// Assigned class: 'sunfletcher' or 'melee'. Null until class phase resolves.
  String? soldierClass;

  LobbyPlayer({
    required this.username,
    required this.profilePicUrl,
    required this.points,
    required this.isGifter,
    this.isFollower = false,
    this.soldierClass,
  });
}

/// A floating "+X" point animation that plays over a card.
class PointPopup {
  final String username;
  final int pointsAdded;
  final double startY; // set by UI at render time
  double opacity;

  PointPopup({
    required this.username,
    required this.pointsAdded,
    this.startY = 0,
    this.opacity = 1.0,
  });
}

// ══════════════════════════════════════════════════
//  Controller — ChangeNotifier, reactive to WebSocket
// ══════════════════════════════════════════════════

class GuildLobbyController extends ChangeNotifier {
  /// Current lobby phase.
  LobbyPhase phase = LobbyPhase.tutorial;

  /// Onboarding tutorial timer seconds.
  int tutorialTimerSeconds = 30;

  /// 18 party slots for display only (driven by master registry).
  final List<LobbyPlayer?> partySlots = List.filled(18, null);

  /// Unbounded master registry — every participant with ≥1 point.
  /// This is the data layer; [partySlots] is the display layer.
  final Map<String, LobbyPlayer> _masterRegistry = {};

  /// Public read-only view for persistence / external access.
  Map<String, LobbyPlayer> get masterRegistry => _masterRegistry;

  /// Usernames of the currently selected 18 (for persistence filtering).
  Set<String> get selectedUsernames =>
      partySlots.where((p) => p != null).map((p) => p!.username).toSet();

  /// Current countdown seconds (displayed on screen).
  int countdownSeconds = 180;

  /// Countdown for the class assignment phase (30s).
  int classTimerSeconds = 30;

  /// True while the match-transition animation is playing.
  bool isTransitioning = false;

  /// Called when the match transition animation finishes.
  VoidCallback? onMatchReady;

  /// 1-second periodic timer that ticks the countdown down.
  Timer? _tickTimer;

  /// Instantly forces the lobby out of the tutorial phase into active player ranking.
  void skipTutorialToRanking() {
    if (phase == LobbyPhase.tutorial) {
      tutorialTimerSeconds = 0;
      phase = LobbyPhase.ranking;
      notifyListeners();
      print('[lobby] Tutorial manually bypassed via admin override.');
    }
  }

  /// Start the countdown timer. Pass a callback for when ranking ends.
  void startCountdown() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (phase == LobbyPhase.tutorial) {
      if (tutorialTimerSeconds > 0) {
        tutorialTimerSeconds--;
        notifyListeners();
      }
      if (tutorialTimerSeconds <= 0) {
        phase = LobbyPhase.ranking;
        notifyListeners();
      }
    } else if (phase == LobbyPhase.ranking) {
      if (countdownSeconds > 0) {
        countdownSeconds--;
        notifyListeners();
      }
      if (countdownSeconds <= 0) {
        startClassAssignment();
        // countdownSeconds / classTimerSeconds are reset inside the method
      }
    } else if (phase == LobbyPhase.classAssignment) {
      if (classTimerSeconds > 0) {
        classTimerSeconds--;
        notifyListeners();
      }
    }
  }

  /// Stop the countdown timer (e.g. on dispose).
  void stopCountdown() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Active point popup animations — the UI renders these as floating overlays.
  final List<PointPopup> activePopups = [];

  /// Card indices currently glowing from a point gain (auto-clears after animation).
  final Set<int> glowingCardIndices = {};

  // ── Public API (called from WebSocket handler / CLI) ─────

  /// Mark a player as a gifter (after they send a gift).
  void markAsGifter(String username) {
    // Update master registry
    final regPlayer = _masterRegistry[username];
    if (regPlayer != null) {
      regPlayer.isGifter = true;
    }
    // Update slot for immediate visual
    final slot = partySlots.indexWhere((p) => p?.username == username);
    if (slot != -1 && partySlots[slot] != null) {
      partySlots[slot]!.isGifter = true;
      notifyListeners();
    }
  }

  /// Add a single player to the party roster.
  /// Player is recorded in the master registry; the 3-phase allocation
  /// algorithm determines their slot position.
  void addPlayer(LobbyPlayer player) {
    _masterRegistry[player.username] = player;

    // Quick immediate fill for responsiveness (empty slots only)
    final emptyIdx = partySlots.indexWhere((p) => p == null);
    if (emptyIdx != -1) {
      partySlots[emptyIdx] = player;
      notifyListeners();
    } else {
      _resortByPoints();
    }
  }

  /// Replace the entire party with incoming top players.
  /// Populates master registry, then runs the 3-phase allocation.
  void updateLobby(List<LobbyPlayer> incomingTopPlayers) {
    print('[lobby] updateLobby: ${incomingTopPlayers.length} players');

    // Populate master registry
    for (final p in incomingTopPlayers) {
      _masterRegistry[p.username] = p;
    }

    // Run 3-phase allocation
    _resortByPoints();

    final filledCount = partySlots.where((p) => p != null).length;
    print('[lobby] slots filled: $filledCount / 18');
  }

  /// Add points to a specific player and trigger visual feedback.
  /// If [isFollower] is true, points are multiplied by 2 (follower bonus).
  @Deprecated('Use processLikePoints or processGiftPoints instead')
  void triggerPointGainAnimation(String username, int pointsAdded, {bool isFollower = false}) {
    _addPoints(username, pointsAdded, isFollower);
  }

  /// Process a like event.
  /// Formula: count × 1, × 2 if follower.
  void processLikePoints(String username, int count, {bool isFollower = false}) {
    final points = isFollower ? count * 2 : count;
    _addPoints(username, points, isFollower);
  }

  /// Process a gift event.
  /// Formula: coinCost × count × 10, × 2 if follower.
  void processGiftPoints(String username,
      {required int coinCost, required int count, bool isFollower = false}) {
    final base = coinCost * count * 10;
    final points = isFollower ? base * 2 : base;
    _addPoints(username, points, isFollower);
  }

  /// Shared internal: apply points, trigger glow/popup, persist.
  void _addPoints(String username, int finalPoints, bool isFollower) {
    // 1) Update master registry (source of truth)
    final regPlayer = _masterRegistry[username];
    if (regPlayer != null) {
      if (isFollower) regPlayer.isFollower = true;
      regPlayer.points += finalPoints;
    } else {
      // First time this player gets points — create registry entry
      _masterRegistry[username] = LobbyPlayer(
        username: username,
        profilePicUrl: '',
        points: finalPoints,
        isGifter: false,
        isFollower: isFollower,
      );
    }

    // 2) If player is visible in a slot, update that slot and show glow
    final idx = partySlots.indexWhere((p) => p?.username == username);
    if (idx != -1 && partySlots[idx] != null) {
      if (isFollower) partySlots[idx]!.isFollower = true;
      partySlots[idx]!.points = _masterRegistry[username]!.points;

      glowingCardIndices.add(idx);
      activePopups.add(PointPopup(
        username: username,
        pointsAdded: finalPoints,
      ));

      print('[lobby] +$finalPoints (follower: $isFollower) → $username (slot ${idx + 1}, now ${partySlots[idx]!.points} pts)');
    } else {
      print('[lobby] point_add: +$finalPoints → $username (registry, not in visible slots — now ${_masterRegistry[username]!.points} pts)');
    }

    notifyListeners();

    // Auto-clear glow after animation duration
    if (idx != -1) {
      Future.delayed(const Duration(milliseconds: 800), () {
        glowingCardIndices.remove(idx);
        notifyListeners();
      });
      Future.delayed(const Duration(milliseconds: 1400), () {
        activePopups.removeWhere((p) => p.username == username);
        notifyListeners();
      });
    }

    // Persist to disk after point change (crash-safe)
    PersistentStorage.saveLobbyState(_masterRegistry, selectedUsernames);

    // Re-sort after points change (give visual time to settle)
    Future.delayed(const Duration(milliseconds: 2000), () {
      _resortByPoints();
    });
  }

  /// Reset all 18 slots to empty with a soft fade.
  void clearLobby() {
    _masterRegistry.clear();
    for (int i = 0; i < 18; i++) partySlots[i] = null;
    activePopups.clear();
    glowingCardIndices.clear();
    countdownSeconds = 180;
    tutorialTimerSeconds = 30;
    phase = LobbyPhase.tutorial;
    PersistentStorage.clearSavedLobby(); // wipe disk too
    notifyListeners();
  }

  /// Start the match transition animation, then callback.
  void startMatchTransition(VoidCallback onTransitionComplete) {
    isTransitioning = true;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 1500), () {
      isTransitioning = false;
      notifyListeners();
      onMatchReady?.call();
      onTransitionComplete();
    });
  }

  // ── Class Assignment Phase ────────────────────────

  /// Transition from ranking to class assignment phase.
  /// Persists filtered registry (crash-safe seed) before assigning classes.
  void startClassAssignment() {
    // ── Crash-Resilient Persistence (Section 3) ──
    // Save filtered data: strip non-gifters + selected 18,
    // keep unselected gifters for the next match seed.
    PersistentStorage.saveLobbyState(_masterRegistry, selectedUsernames);

    phase = LobbyPhase.classAssignment;
    countdownSeconds = 180; // reset for next ranking phase
    classTimerSeconds = 30;
    _assignRandomClasses();
    notifyListeners();
  }

  /// Assign random classes to all players (50/50 split).
  void _assignRandomClasses() {
    final filled = partySlots.where((p) => p != null).cast<LobbyPlayer>().toList();
    final classes = <String>[];
    for (int i = 0; i < filled.length; i++) {
      classes.add(i < filled.length ~/ 2 ? 'sunfletcher' : 'melee');
    }
    classes.shuffle();
    for (int i = 0; i < filled.length; i++) {
      filled[i].soldierClass = classes[i];
    }
  }

  /// Set a player's class (top 5 players only).
  void setPlayerClass(String username, String soldierClass) {
    if (phase != LobbyPhase.classAssignment) return;
    final idx = partySlots.indexWhere((p) => p?.username == username);
    if (idx == -1 || idx >= 5) return; // only top 5 can choose
    if (soldierClass != 'sunfletcher' && soldierClass != 'melee') return;

    // Check this class isn't already taken by another top-5
    final alreadyAssigned = partySlots.where((p) =>
        p != null && p.soldierClass == soldierClass && partySlots.indexOf(p) < 5
    ).length;
    if (alreadyAssigned >= 1) return; // already taken

    partySlots[idx]!.soldierClass = soldierClass;
    print('[lobby] ${partySlots[idx]!.username} chose $soldierClass');
    notifyListeners();
  }

  /// Called when the 30s class timer expires.
  void finalizeClasses() {
    // Any top-5 without a chosen class keep their random assignment
    phase = LobbyPhase.transitioning;
    notifyListeners();
  }

  /// Get the class for a given username.
  String? getClassFor(String username) {
    return partySlots
        .where((p) => p?.username == username)
        .map((p) => p!.soldierClass)
        .firstOrNull;
  }

  /// Build a map of username → class for the battle pipeline.
  Map<String, String> get classAssignments {
    final map = <String, String>{};
    for (final p in partySlots) {
      if (p != null && p.soldierClass != null) {
        map[p.username] = p.soldierClass!;
      }
    }
    return map;
  }

  /// Used by PersistentStorage.restoreLobbyState to seed the master registry
  /// from disk-saved unselected gifters.
  void restoreRegistry(List<LobbyPlayer> players) {
    for (final p in players) {
      _masterRegistry[p.username] = p;
    }
    _resortByPoints();
  }

  // ── Internal: 3-Phase Seat Allocation ────────────

  /// Replace old bus-seat with the 3-phase Hybrid Merit-Wildcard algorithm.
  ///
  /// Phase 1 (Seats 1-14): Pure meritocracy — top 14 by points.
  /// Phase 2 (Seats 15-18): Non-gifter wildcard zone.
  /// Phase 3 (Fallback):   Fill with unselected gifters if <4 non-gifters.
  void _resortByPoints() {
    // ── Phase 1: Pure Meritocracy (Seats 1-14) ──
    // All participants with ≥1 point, sorted descending
    final allPlayers = _masterRegistry.values
        .where((p) => p.points >= 1)
        .toList()
      ..sort((a, b) => b.points.compareTo(a.points));

    final selected = <LobbyPlayer>[];
    final selectedUsernames = <String>{};

    // Take top 14 — pure score, gifter status irrelevant
    for (int i = 0; i < 14 && i < allPlayers.length; i++) {
      selected.add(allPlayers[i]);
      selectedUsernames.add(allPlayers[i].username);
    }
    print('[lobby] Phase 1: ${selected.length} merit seats filled');

    // ── Phase 2: Non-Gifter Wildcard Zone (Seats 15-18) ──
    final remaining = allPlayers
        .where((p) => !selectedUsernames.contains(p.username))
        .toList();
    final nonGifters = remaining
        .where((p) => !p.isGifter)
        .toList()
      ..sort((a, b) => b.points.compareTo(a.points));

    int wildcardFilled = 0;
    for (int i = 0; i < 4 && i < nonGifters.length; i++) {
      selected.add(nonGifters[i]);
      selectedUsernames.add(nonGifters[i].username);
      wildcardFilled++;
    }
    print('[lobby] Phase 2: $wildcardFilled wildcard seats filled');

    // ── Phase 3: Monetization Guard (Fallback) ──
    if (wildcardFilled < 4) {
      final remainingGifters = remaining
          .where((p) => p.isGifter && !selectedUsernames.contains(p.username))
          .toList()
        ..sort((a, b) => b.points.compareTo(a.points));

      int fallbackFilled = 0;
      final slots = 4 - wildcardFilled;
      for (int i = 0; i < slots && i < remainingGifters.length; i++) {
        selected.add(remainingGifters[i]);
        selectedUsernames.add(remainingGifters[i].username);
        fallbackFilled++;
      }
      print('[lobby] Phase 3: $fallbackFilled fallback seats filled');
    }

    // Fill display slots
    for (int i = 0; i < 18; i++) {
      partySlots[i] = i < selected.length ? selected[i] : null;
    }

    print('[lobby] total: ${selected.length} players allocated');
    notifyListeners();
  }
}
