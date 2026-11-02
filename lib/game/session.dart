import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'bots.dart';
import 'engine.dart';

/// What the game screen talks to, whether the game runs here or on someone else's
/// device. The view always arrives as the same JSON, so both paths look alike.
abstract class GameSession extends ChangeNotifier {
  Map<String, dynamic>? view;

  /// Set when the game ended underneath the player (host left, connection lost).
  String? closedReason;

  DateTime? _deadline;

  int get secondsLeft {
    final d = _deadline;
    if (d == null) return 0;
    return max(0, d.difference(DateTime.now()).inSeconds + 1);
  }

  @protected
  void setView(Map<String, dynamic> next) {
    view = next;
    final left = next['left'] as int?;
    _deadline = left == null || left <= 0
        ? null
        : DateTime.now().add(Duration(milliseconds: left));
    notifyListeners();
  }

  @protected
  void close(String reason) {
    closedReason = reason;
    notifyListeners();
  }

  void send(Map<String, dynamic> action);
  Future<void> leave();
}

String randomId([int length = 12]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Room codes skip letters and digits that are easy to mix up when read aloud.
String randomRoomCode() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Runs the game on this device: the phase timers, the bots, and applying everyone's
/// actions. Bot games use this alone; online rooms put [OnlineHost] on top of it.
class HostSession extends GameSession {
  HostSession(this.game, this.localId, {Random? random})
    : _random = random ?? Random(),
      _brain = BotBrain(random) {
    game.hostId = localId;
    if (game.quick) _scheduleQuickStart(_quickWait);
    _publish();
  }

  /// How long a random room waits for people before bots fill the empty seats.
  static const _quickWait = Duration(seconds: 60);

  /// How long a random room waits for more people once it has enough to play.
  static const _quickGrace = Duration(seconds: 15);

  final GameEngine game;
  final String localId;
  final Random _random;
  final BotBrain _brain;

  Timer? _phaseTimer;
  final _botTimers = <Timer>[];
  DateTime? _phaseEnd;
  bool _disposed = false;

  /// Called after every change, so the network layer can send out new views.
  VoidCallback? onChanged;

  int get msLeft {
    final end = _phaseEnd;
    return end == null ? 0 : end.difference(DateTime.now()).inMilliseconds;
  }

  @override
  void send(Map<String, dynamic> action) => handle(localId, action);

  void handle(String playerId, Map<String, dynamic> action) {
    final target = action['t'] as String?;
    switch (action['a']) {
      case 'start':
        if (playerId == game.hostId) startGame();
        return;
      case 'night':
        if (target == null || !game.submitNight(playerId, target)) return;
      case 'vote':
        if (!game.submitVote(playerId, target)) return;
      case 'ready':
        if (!game.markReady(playerId)) return;
      case 'chat':
        if (!game.addChat(playerId, '${action['text'] ?? ''}')) return;
      default:
        return;
    }
    _afterAction();
  }

  void startGame() {
    game.start();
    if (game.phase == Phase.reveal) _enterPhase();
  }

  /// Adds someone to the waiting room. Returns false if the room can't take them.
  bool addPlayer(String id, String name) {
    if (game.phase != Phase.lobby || game.isFull) return false;
    game.addPlayer(id, name);
    if (game.quick) {
      if (game.isFull) {
        _startQuick();
        return true;
      }
      if (game.players.length >= minPlayers && msLeft > _quickGrace.inMilliseconds) {
        _scheduleQuickStart(_quickGrace);
      }
    }
    _publish();
    return true;
  }

  void playerGone(String id) {
    if (game.phase == Phase.lobby) {
      game.removeFromLobby(id);
    } else {
      game.player(id)?.online = false;
    }
    _afterAction();
  }

  void addBots(int count) {
    final free = botNames.toList()..shuffle(_random);
    for (var i = 0; i < count; i++) {
      game.addPlayer('bot-${randomId(6)}', free[i % free.length], isBot: true);
    }
  }

  void _scheduleQuickStart(Duration wait) {
    _phaseEnd = DateTime.now().add(wait);
    _phaseTimer?.cancel();
    _phaseTimer = Timer(wait, _startQuick);
  }

  void _startQuick() {
    _phaseTimer?.cancel();
    final missing = minPlayers - game.players.length;
    if (missing > 0) addBots(missing);
    game.mafiaCount = game.players.length >= 7 ? 2 : 1;
    startGame();
  }

  void _afterAction() {
    if (game.phaseComplete) {
      _nextPhase();
    } else {
      _publish();
    }
  }

  void _nextPhase() {
    final wasVoting = game.phase == Phase.voting;
    game.advance();
    if (wasVoting) _brain.rememberVerdict(game);
    _enterPhase();
  }

  void _enterPhase() {
    _phaseTimer?.cancel();
    for (final t in _botTimers) {
      t.cancel();
    }
    _botTimers.clear();

    final duration = phaseDuration(game.phase);
    if (game.phase == Phase.over) {
      _phaseEnd = null;
    } else {
      _phaseEnd = DateTime.now().add(duration);
      _phaseTimer = Timer(duration, _nextPhase);
    }
    _scheduleBots();
    // A phase with nobody left to wait for (a day with only bots alive) still gets
    // a short beat so the screen doesn't flash past.
    if (game.phase == Phase.day && game.phaseComplete) {
      _phaseEnd = DateTime.now().add(const Duration(seconds: 4));
      _phaseTimer?.cancel();
      _phaseTimer = Timer(const Duration(seconds: 4), _nextPhase);
    }
    _publish();
  }

  void _scheduleBots() {
    for (final bot in game.alive.where((p) => p.isBot)) {
      switch (game.phase) {
        case Phase.night:
          if (bot.role != Role.citizen) _botAfter(2, 9, () => _botNight(bot));
        case Phase.voting:
          _botAfter(2, 12, () => _botVote(bot));
        case Phase.day:
          // Spread out over the day, so the talk doesn't all land in one burst.
          // With no human left to wait for the day is short, so they talk right away.
          final lines = 1 + _random.nextInt(3);
          final latest = game.phaseComplete ? 3 : 45;
          for (var i = 0; i < lines; i++) {
            _botAfter(1, latest, () => _botSay(bot));
          }
        default:
          break;
      }
    }
  }

  void _botAfter(int minSeconds, int maxSeconds, VoidCallback run) {
    final ms = (minSeconds + _random.nextDouble() * (maxSeconds - minSeconds)) * 1000;
    _botTimers.add(Timer(Duration(milliseconds: ms.round()), () {
      if (!_disposed) run();
    }));
  }

  void _botNight(EnginePlayer bot) {
    final target = _brain.nightTarget(game, bot);
    if (target != null && game.submitNight(bot.id, target)) _afterAction();
  }

  void _botVote(EnginePlayer bot) {
    if (game.submitVote(bot.id, _brain.voteTarget(game, bot))) _afterAction();
  }

  void _botSay(EnginePlayer bot) {
    if (game.addChat(bot.id, _brain.dayLine(game, bot))) _publish();
  }

  /// The view for [id], with the time left on the current phase.
  Map<String, dynamic> viewOf(String id) => {...game.viewFor(id), 'left': msLeft};

  void _publish() {
    if (_disposed) return;
    setView(viewOf(localId));
    onChanged?.call();
  }

  @override
  Future<void> leave() async => dispose();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _phaseTimer?.cancel();
    for (final t in _botTimers) {
      t.cancel();
    }
    super.dispose();
  }
}
