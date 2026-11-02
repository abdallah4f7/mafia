import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mafia/game/bots.dart';
import 'package:mafia/game/engine.dart';

GameEngine newGame(int players, int mafia, {int seed = 1}) {
  final game = GameEngine(
    code: 'TEST00',
    maxPlayers: players,
    mafiaCount: mafia,
    random: Random(seed),
  );
  for (var i = 0; i < players; i++) {
    game.addPlayer('p$i', 'لاعب', isBot: true);
  }
  return game;
}

EnginePlayer withRole(GameEngine g, Role role) =>
    g.players.firstWhere((p) => p.role == role && p.alive);

void toNight(GameEngine g) {
  g.start();
  g.advance();
  expect(g.phase, Phase.night);
}

void main() {
  group('starting', () {
    test('needs at least 5 players', () {
      final game = newGame(4, 1);
      expect(game.startProblem, isNotNull);
      game.start();
      expect(game.phase, Phase.lobby);
      game.addPlayer('p9', 'لاعب');
      expect(game.startProblem, isNull);
      game.start();
      expect(game.phase, Phase.reveal);
    });

    test('mafia limit keeps the game from being over at the start', () {
      expect(maxMafiaFor(5), 2);
      expect(maxMafiaFor(6), 2);
      expect(maxMafiaFor(7), 3);
      expect(maxMafiaFor(15), 3);
      expect(newGame(6, 3).startProblem, isNotNull);
      expect(newGame(7, 3).startProblem, isNull);
    });

    test('deals exactly the requested roles', () {
      for (final (players, mafia) in [(5, 1), (5, 2), (7, 3), (15, 3)]) {
        final game = newGame(players, mafia)..start();
        int count(Role r) => game.players.where((p) => p.role == r).length;
        expect(count(Role.mafia), mafia);
        expect(count(Role.doctor), 1);
        expect(count(Role.detective), 1);
        expect(count(Role.citizen), players - mafia - 2);
      }
    });

    test('two players can share a name and stay separate', () {
      final game = newGame(5, 1);
      expect(game.players.map((p) => p.name).toSet().length, 1);
      expect(game.players.map((p) => p.id).toSet().length, 5);
      expect(game.players.map((p) => p.seat).toSet().length, 5);
    });
  });

  group('secrets', () {
    test('a citizen\'s view never contains anyone else\'s role', () {
      final game = newGame(8, 2);
      toNight(game);
      final me = withRole(game, Role.citizen);
      final view = game.viewFor(me.id);
      final others = (view['players'] as List).where((p) => p['id'] != me.id);
      expect(others.every((p) => !(p as Map).containsKey('role')), isTrue);
      expect(view.containsKey('mafiaVotes'), isFalse);
      expect(view.containsKey('checks'), isFalse);
      final mafia = withRole(game, Role.mafia);
      game.submitNight(mafia.id, me.id);
      expect(jsonEncode(game.viewFor(me.id)), isNot(contains('mafiaVotes')));
    });

    test('mafia see each other but not the doctor or detective', () {
      final game = newGame(8, 2);
      toNight(game);
      final mafia = withRole(game, Role.mafia);
      final seen = (game.viewFor(mafia.id)['players'] as List)
          .where((p) => (p as Map).containsKey('role'))
          .map((p) => p['role'])
          .toList();
      expect(seen, ['mafia', 'mafia']);
    });

    test('mafia chat stays with the mafia until the game ends', () {
      final game = newGame(8, 2);
      toNight(game);
      final mafia = withRole(game, Role.mafia);
      final citizen = withRole(game, Role.citizen);
      expect(game.addChat(mafia.id, 'نقتل مين؟'), isTrue);
      expect(game.addChat(citizen.id, 'أنا صاحي'), isFalse);
      expect(game.viewFor(citizen.id)['chat'], isEmpty);
      expect(game.viewFor(mafia.id)['chat'], hasLength(1));
    });

    test('roles show once a player is dead', () {
      final game = newGame(5, 1);
      toNight(game);
      final victim = withRole(game, Role.citizen);
      final other = game.players.firstWhere(
        (p) => p.role == Role.citizen && p.id != victim.id,
      );
      game.submitNight(withRole(game, Role.mafia).id, victim.id);
      game.advance();
      final entry = (game.viewFor(other.id)['players'] as List).firstWhere(
        (p) => p['id'] == victim.id,
      );
      expect(entry['role'], 'citizen');
    });
  });

  group('night', () {
    test('doctor saves the mafia target', () {
      final game = newGame(5, 1);
      toNight(game);
      final victim = withRole(game, Role.citizen);
      game.submitNight(withRole(game, Role.mafia).id, victim.id);
      game.submitNight(withRole(game, Role.doctor).id, victim.id);
      game.advance();
      expect(game.nightVictim, isNull);
      expect(victim.alive, isTrue);
    });

    test('detective learns the truth', () {
      final game = newGame(5, 1);
      toNight(game);
      final mafia = withRole(game, Role.mafia);
      game.submitNight(withRole(game, Role.detective).id, mafia.id);
      game.advance();
      expect(game.detectiveResults[mafia.id], isTrue);
    });

    test('illegal picks are refused', () {
      final game = newGame(7, 2);
      toNight(game);
      final mafia = game.players.where((p) => p.role == Role.mafia).toList();
      final citizen = withRole(game, Role.citizen);
      final detective = withRole(game, Role.detective);
      expect(game.submitNight(mafia[0].id, mafia[1].id), isFalse);
      expect(game.submitNight(citizen.id, mafia[0].id), isFalse);
      expect(game.submitNight(detective.id, detective.id), isFalse);
    });

    test('a disconnected player does not hold up the phase', () {
      final game = newGame(5, 1);
      toNight(game);
      game.submitNight(withRole(game, Role.mafia).id, withRole(game, Role.citizen).id);
      game.submitNight(withRole(game, Role.doctor).id, withRole(game, Role.citizen).id);
      expect(game.phaseComplete, isFalse);
      withRole(game, Role.detective).online = false;
      expect(game.phaseComplete, isTrue);
    });
  });

  group('voting', () {
    GameEngine atVoting() {
      final game = newGame(7, 1);
      toNight(game);
      game.advance(); // Dawn, with no kill.
      game.advance(); // Day.
      game.advance(); // Voting.
      expect(game.phase, Phase.voting);
      return game;
    }

    test('most votes goes out', () {
      final game = atVoting();
      final out = game.players[0];
      game.submitVote(game.players[1].id, out.id);
      game.submitVote(game.players[2].id, out.id);
      game.submitVote(game.players[3].id, game.players[1].id);
      game.advance();
      expect(game.votedOut, out.id);
      expect(out.alive, isFalse);
    });

    test('a tie sends nobody out', () {
      final game = atVoting();
      game.submitVote(game.players[0].id, game.players[1].id);
      game.submitVote(game.players[1].id, game.players[0].id);
      game.advance();
      expect(game.votedOut, isNull);
      expect(game.alive, hasLength(7));
    });

    test('more skips than votes sends nobody out', () {
      final game = atVoting();
      game.submitVote(game.players[0].id, game.players[1].id);
      game.submitVote(game.players[2].id, null);
      game.submitVote(game.players[3].id, null);
      game.advance();
      expect(game.votedOut, isNull);
    });

    test('you can\'t vote for yourself and the dead can\'t vote', () {
      final game = atVoting();
      expect(game.submitVote(game.players[0].id, game.players[0].id), isFalse);
      game.players[1].alive = false;
      expect(game.submitVote(game.players[1].id, game.players[0].id), isFalse);
      expect(game.submitVote(game.players[0].id, game.players[1].id), isFalse);
    });
  });

  group('winning', () {
    test('town wins when the last mafia goes', () {
      final game = newGame(5, 1);
      toNight(game);
      game.advance();
      game.advance();
      game.advance();
      final mafia = withRole(game, Role.mafia);
      for (final p in game.alive.where((p) => p.id != mafia.id)) {
        game.submitVote(p.id, mafia.id);
      }
      game.advance();
      game.advance();
      expect(game.phase, Phase.over);
      expect(game.winner, Role.citizen);
    });

    test('mafia win on reaching equal numbers', () {
      final game = newGame(5, 2);
      toNight(game);
      final victim = withRole(game, Role.citizen);
      for (final m in game.players.where((p) => p.role == Role.mafia)) {
        game.submitNight(m.id, victim.id);
      }
      game.advance();
      game.advance();
      expect(game.phase, Phase.over);
      expect(game.winner, Role.mafia);
    });
  });

  test('bot games always finish, and both sides can win', () {
    final wins = <Role, int>{Role.mafia: 0, Role.citizen: 0};
    for (var seed = 0; seed < 600; seed++) {
      final random = Random(seed);
      final players = minPlayers + seed % (maxPlayersLimit - minPlayers + 1);
      final mafia = 1 + seed % maxMafiaFor(players);
      final game = newGame(players, mafia, seed: seed);
      final brain = BotBrain(random);
      game.start();
      var steps = 0;
      while (game.phase != Phase.over) {
        expect(++steps, lessThan(2000), reason: 'seed $seed never ended');
        if (game.phase == Phase.night) {
          for (final bot in game.alive) {
            final target = brain.nightTarget(game, bot);
            if (target != null) {
              expect(game.submitNight(bot.id, target), isTrue);
            }
          }
          expect(game.phaseComplete, isTrue);
        } else if (game.phase == Phase.day) {
          for (final bot in game.alive) {
            expect(game.addChat(bot.id, brain.dayLine(game, bot)), isTrue);
          }
        } else if (game.phase == Phase.voting) {
          for (final bot in game.alive) {
            expect(game.submitVote(bot.id, brain.voteTarget(game, bot)), isTrue);
          }
          expect(game.phaseComplete, isTrue);
          game.advance();
          brain.rememberVerdict(game);
          continue;
        }
        game.advance();
      }
      wins[game.winner!] = wins[game.winner!]! + 1;
    }
    // ignore: avoid_print
    print('wins over 600 bot games: $wins');
    expect(wins[Role.mafia], greaterThan(30));
    expect(wins[Role.citizen], greaterThan(30));
  });
}
