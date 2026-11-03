import 'dart:math';

import 'engine.dart';

const _idleLines = [
  'أحد عنده شك في أحد؟',
  'خلونا نركز يا جماعة',
  'أنا بريء والله',
  'الوضع مريب الليلة',
  'مين ساكت من أول اللعبة؟',
  'لا تستعجلون بالتصويت',
  'أنا مواطن عادي، صدقوني',
];

const _accuseLines = [
  '{n} كلامه ما يدخل المخ',
  'أشك في {n}',
  'أحس {n} مافيا',
  'ليش {n} ساكت؟ هذا مريب',
];

const _accusedSure = 'أنا المحقق، و{n} مافيا، صوتوا عليه!';

/// How the bots think. They only use what their role could really know, plus a
/// shared memory of how suspicious each player has looked in public.
class BotBrain {
  BotBrain([Random? random]) : _random = random ?? Random();

  final Random _random;
  final _suspicion = <String, int>{};

  /// The player a bot picks tonight, or null when its role has nothing to do.
  String? nightTarget(GameEngine game, EnginePlayer bot) {
    switch (bot.role) {
      case Role.mafia:
        // Mafia bots pile onto a partner's pick so their vote doesn't split.
        final picked = game.mafiaVotes.values.toList();
        if (picked.isNotEmpty) return picked.first;
        return _pick(game.alive.where((p) => p.role != Role.mafia))?.id;
      case Role.doctor:
        return _pick(game.alive)?.id;
      case Role.detective:
        final others = game.alive.where((p) => p.id != bot.id);
        final unchecked = others.where(
          (p) => !game.detectiveResults.containsKey(p.id),
        );
        return _pick(unchecked.isNotEmpty ? unchecked : others)?.id;
      case Role.citizen:
        return null;
    }
  }

  /// Who a bot votes for, or null to skip.
  String? voteTarget(GameEngine game, EnginePlayer bot) {
    final known = _knownMafia(game, bot);
    if (known != null) return known.id;

    final candidates = game.alive.where((p) {
      if (p.id == bot.id) return false;
      if (bot.role == Role.mafia) return p.role != Role.mafia;
      if (bot.role == Role.detective) return game.detectiveResults[p.id] != true;
      return true;
    }).toList();
    if (candidates.isEmpty) return null;
    if (bot.role != Role.mafia && _random.nextInt(8) == 0) return null;

    final weights = [
      for (final p in candidates)
        1 +
            max(0, _suspicion[p.id] ?? 0) * 2 +
            game.votes.values.where((v) => v == p.id).length * 2,
    ];
    var roll = _random.nextInt(weights.reduce((a, b) => a + b));
    for (var i = 0; i < candidates.length; i++) {
      roll -= weights[i];
      if (roll < 0) return candidates[i].id;
    }
    return candidates.last.id;
  }

  /// A line for a bot to say during the day. Accusations are remembered, since the
  /// other bots heard them too.
  String dayLine(GameEngine game, EnginePlayer bot) {
    final known = _knownMafia(game, bot);
    if (known != null) {
      _suspicion[known.id] = (_suspicion[known.id] ?? 0) + 4;
      return _accusedSure.replaceAll('{n}', known.name);
    }
    if (_random.nextBool()) return _idleLines[_random.nextInt(_idleLines.length)];
    final target = _pick(
      game.alive.where(
        (p) =>
            p.id != bot.id &&
            !(bot.role == Role.mafia && p.role == Role.mafia),
      ),
    );
    if (target == null) return _idleLines.first;
    _suspicion[target.id] = (_suspicion[target.id] ?? 0) + 1;
    return _accuseLines[_random.nextInt(_accuseLines.length)].replaceAll(
      '{n}',
      target.name,
    );
  }

  /// Learns from how a vote turned out: backing an innocent looks bad, and
  /// backing a mafia member clears you.
  void rememberVerdict(GameEngine game) {
    final out = game.player(game.votedOut);
    if (out == null) return;
    game.votes.forEach((voter, target) {
      if (target != out.id) return;
      final change = out.role == Role.mafia ? -2 : 1;
      _suspicion[voter] = (_suspicion[voter] ?? 0) + change;
    });
  }

  EnginePlayer? _knownMafia(GameEngine game, EnginePlayer bot) {
    if (bot.role != Role.detective) return null;
    for (final p in game.alive) {
      if (game.detectiveResults[p.id] == true) return p;
    }
    return null;
  }

  EnginePlayer? _pick(Iterable<EnginePlayer> from) {
    final list = from.toList();
    return list.isEmpty ? null : list[_random.nextInt(list.length)];
  }
}
