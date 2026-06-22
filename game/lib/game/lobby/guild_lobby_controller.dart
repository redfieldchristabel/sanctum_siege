import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════
//  Data Models
// ══════════════════════════════════════════════════

class LobbyPlayer {
  final String username;
  final String profilePicUrl;
  int points;
  bool isGifter; // true = ranks 1-13 (points slot), false = ranks 14-18 (wildcard)

  LobbyPlayer({
    required this.username,
    required this.profilePicUrl,
    required this.points,
    required this.isGifter,
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
  /// 20 party slots. null = empty (awaiting hero).
  final List<LobbyPlayer?> partySlots = List.filled(18, null);

  /// Current countdown seconds (displayed on screen).
  int countdownSeconds = 180;

  /// True while the match-transition animation is playing.
  bool isTransitioning = false;

  /// Called when the match transition animation finishes.
  VoidCallback? onMatchReady;

  /// Active point popup animations — the UI renders these as floating overlays.
  final List<PointPopup> activePopups = [];

  /// Card indices currently glowing from a point gain (auto-clears after animation).
  final Set<int> glowingCardIndices = {};

  // ── Public API (called from WebSocket handler / CLI) ─────

  /// Mark a player as a gifter (after they send a gift).
  void markAsGifter(String username) {
    final slot = partySlots.indexWhere((p) => p?.username == username);
    if (slot != -1 && partySlots[slot] != null) {
      partySlots[slot]!.isGifter = true;
      notifyListeners();
    }
  }

  /// Add a single player to the party roster.
  /// Finds the first empty slot, or replaces the lowest-points wildcard if full.
  void addPlayer(LobbyPlayer player) {
    // 1) Find first empty slot
    final emptyIdx = partySlots.indexWhere((p) => p == null);
    if (emptyIdx != -1) {
      partySlots[emptyIdx] = player;
      print('[lobby] addPlayer: ${player.username} → slot ${emptyIdx + 1}');
      notifyListeners();
      return;
    }

    // 2) All slots full — replace the lowest-points wildcard
    int worstIdx = -1;
    int worstPts = 999999;
    for (int i = 13; i < 18; i++) {
      final p = partySlots[i];
      if (p != null && p.points < worstPts) {
        worstPts = p.points;
        worstIdx = i;
      }
    }
    if (worstIdx != -1) {
      print('[lobby] addPlayer: ${player.username} replaces slot ${worstIdx + 1}');
      partySlots[worstIdx] = player;
      notifyListeners();
    }
  }

  /// Replace the entire party with incoming top players.
  /// Bus-seat algorithm:
  ///   1. Sort all players by points descending
  ///   2. Take top 18
  ///   3. Ensure up to 5 non-gifters are in the party:
  ///      - If <5 non-gifters in the 18, bump lowest-point gifters
  ///        and replace with next highest-point non-gifters from outside
  void updateLobby(List<LobbyPlayer> incomingTopPlayers) {
    print('[lobby] updateLobby: ${incomingTopPlayers.length} players');

    // 1) Sort all by points descending (gifter/normal ignored)
    final sorted = List<LobbyPlayer>.from(incomingTopPlayers)
      ..sort((a, b) => b.points.compareTo(a.points));

    // 2) Take top 18
    final selected = sorted.take(18).toList();

    // 3) Ensure up to 5 non-gifters
    final remaining = sorted.skip(18).toList();
    int nonGifters = selected.where((p) => !p.isGifter).length;
    int gifterBumpIdx = 17; // start from lowest-point gifter

    while (nonGifters < 5 && remaining.isNotEmpty) {
      // Find the next non-gifter waiting outside
      final nextNonGifter = remaining.indexWhere((p) => !p.isGifter);
      if (nextNonGifter == -1) break; // no more non-gifters in pool

      // Find the lowest-point gifter in selected to bump
      while (gifterBumpIdx >= 0 && !selected[gifterBumpIdx].isGifter) {
        gifterBumpIdx--;
      }
      if (gifterBumpIdx < 0) break; // no bumpable gifter found

      // Replace: bump gifter, insert non-gifter
      selected[gifterBumpIdx] = remaining.removeAt(nextNonGifter);
      nonGifters++;
      gifterBumpIdx--;
    }

    // Re-sort final selected by points for display
    selected.sort((a, b) => b.points.compareTo(a.points));

    // Fill slots
    for (int i = 0; i < 18; i++) {
      partySlots[i] = i < selected.length ? selected[i] : null;
    }

    print('[lobby] slots filled: ${selected.where((p) => p.isGifter).length} gifters + '
        '${selected.where((p) => !p.isGifter).length} non-gifters');
    notifyListeners();
  }

  /// Add points to a specific player and trigger visual feedback.
  void triggerPointGainAnimation(String username, int pointsAdded) {
    final idx = partySlots.indexWhere((p) => p?.username == username);
    if (idx == -1 || partySlots[idx] == null) {
      print('[lobby] point_add: $username not found in slots');
      return;
    }

    partySlots[idx]!.points += pointsAdded;
    print('[lobby] +$pointsAdded → $username (slot ${idx + 1}, now ${partySlots[idx]!.points} pts)');

    // Trigger glow
    glowingCardIndices.add(idx);
    activePopups.add(PointPopup(
      username: username,
      pointsAdded: pointsAdded,
    ));

    notifyListeners();

    // Auto-clear glow after animation duration
    Future.delayed(const Duration(milliseconds: 800), () {
      glowingCardIndices.remove(idx);
      notifyListeners();
    });

    // Fade out popup
    Future.delayed(const Duration(milliseconds: 1400), () {
      activePopups.removeWhere((p) => p.username == username);
      notifyListeners();
    });

    // Re-sort after points change (give visual time to settle)
    Future.delayed(const Duration(milliseconds: 2000), () {
      _resortByPoints();
    });
  }

  /// Reset all 18 slots to empty with a soft fade.
  void clearLobby() {
    for (int i = 0; i < 18; i++) partySlots[i] = null;
    activePopups.clear();
    glowingCardIndices.clear();
    countdownSeconds = 180;
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

  // ── Internal ──────────────────────────────────────

  void _resortByPoints() {
    final filled = <LobbyPlayer>[];
    for (final slot in partySlots) {
      if (slot != null) filled.add(slot);
    }

    // Same bus-seat algorithm as updateLobby
    filled.sort((a, b) => b.points.compareTo(a.points));

    final selected = filled.take(18).toList();
    final remaining = filled.skip(18).toList();
    int nonGifters = selected.where((p) => !p.isGifter).length;
    int gifterBumpIdx = 17;

    while (nonGifters < 5 && remaining.isNotEmpty) {
      final nextNonGifter = remaining.indexWhere((p) => !p.isGifter);
      if (nextNonGifter == -1) break;
      while (gifterBumpIdx >= 0 && !selected[gifterBumpIdx].isGifter) {
        gifterBumpIdx--;
      }
      if (gifterBumpIdx < 0) break;
      selected[gifterBumpIdx] = remaining.removeAt(nextNonGifter);
      nonGifters++;
      gifterBumpIdx--;
    }

    selected.sort((a, b) => b.points.compareTo(a.points));

    for (int i = 0; i < 18; i++) {
      partySlots[i] = i < selected.length ? selected[i] : null;
    }

    notifyListeners();
  }
}
