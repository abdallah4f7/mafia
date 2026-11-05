import 'dart:math';

import 'engine.dart';

/// One phone shared by a room. It goes around everyone for the roles and the votes.
/// At night it stays in the middle, and each role is called to it in turn while the
/// others close their eyes. Nothing here is timed, since the players are sitting
/// together and decide when to move on.
class PassGame {
  PassGame(List<String> names, int mafiaCount, {Random? random})
    : game = GameEngine(
        code: 'PASS',
        maxPlayers: names.length,
        mafiaCount: mafiaCount,
        random: random,
      ) {
    for (var i = 0; i < names.length; i++) {
      game.addPlayer('p$i', names[i]);
    }
    game.start();
    _queue.addAll(game.players);
  }

  final GameEngine game;
  final _queue = <EnginePlayer>[];

  /// False while the phone is being handed over, so a secret is never on the screen
  /// until the right person says they have it.
  bool opened = false;

  /// Who the detective just checked. They see it right away, since they won't hold
  /// the phone again until after the morning.
  EnginePlayer? checked;

  /// Who should have the phone, or null when it's on the table for everyone. At night
  /// this is whoever speaks for the role being called.
  EnginePlayer? get holder => _queue.isEmpty ? null : _queue.first;

  /// Who the holder can pick right now.
  List<EnginePlayer> get targets {
    final me = holder;
    if (me == null) return const [];
    bool other(EnginePlayer p) => p.id != me.id;
    if (game.phase == Phase.voting) return game.alive.where(other).toList();
    if (game.phase != Phase.night) return const [];
    return switch (me.role) {
      Role.mafia => game.alive.where((p) => p.role != Role.mafia).toList(),
      Role.doctor => game.alive,
      Role.detective => game.alive.where(other).toList(),
      Role.citizen => const [],
    };
  }

  /// A plain name is enough, unless two people share it.
  String label(EnginePlayer p) => game.players.where((o) => o.name == p.name).length > 1
      ? '${p.name} ${p.seat}'
      : p.name;

  void open() => opened = true;

  /// The holder's night pick or vote. A null [targetId] skips the vote.
  void choose(String? targetId) {
    final me = holder;
    if (me == null) return;
    if (game.phase == Phase.voting) {
      if (game.submitVote(me.id, targetId)) finishTurn();
    } else if (targetId != null && game.submitNight(me.id, targetId)) {
      if (me.role == Role.detective) {
        checked = game.player(targetId);
        return;
      }
      // The mafia look at the phone together, so their one pick counts for all of them.
      if (me.role == Role.mafia) {
        for (final p in game.alive.where((p) => p.role == Role.mafia)) {
          game.submitNight(p.id, targetId);
        }
      }
      finishTurn();
    }
  }

  void finishTurn() {
    checked = null;
    opened = false;
    _queue.removeAt(0);
    if (_queue.isEmpty) next();
  }

  /// Moves on from whatever is showing. The holder's turn ends the same way once
  /// nobody is left to pass the phone to.
  void next() {
    game.advance();
    if (game.phase == Phase.voting) {
      _queue.addAll(game.alive);
    } else if (game.phase == Phase.night) {
      for (final role in const [Role.mafia, Role.doctor, Role.detective]) {
        final caller = game.alive.where((p) => p.role == role).firstOrNull;
        if (caller != null) _queue.add(caller);
      }
    }
  }
}
