import 'package:flutter_test/flutter_test.dart';
import 'package:mafia/game/engine.dart';
import 'package:mafia/game/session.dart';
import 'package:mafia/net/online.dart';

// testWidgets is only here for its fake clock, so timers run without real waiting.
void main() {
  HostSession quickRoom() {
    final game = GameEngine(code: 'QUICK0', maxPlayers: 6, mafiaCount: 1, quick: true)
      ..addPlayer('me', 'أنا');
    return HostSession(game, 'me');
  }

  testWidgets('a lone random player gets bots after the wait', (tester) async {
    final session = quickRoom();
    await tester.pump(const Duration(seconds: 59));
    expect(session.game.phase, Phase.lobby);
    await tester.pump(const Duration(seconds: 2));
    expect(session.game.phase, Phase.reveal);
    expect(session.game.players, hasLength(minPlayers));
    expect(session.game.players.where((p) => p.isBot), hasLength(minPlayers - 1));
    session.dispose();
  });

  testWidgets('a random room with 5 people starts soon, with no bots', (tester) async {
    final session = quickRoom();
    for (var i = 0; i < 4; i++) {
      session.addPlayer('p$i', 'لاعب');
    }
    await tester.pump(const Duration(seconds: 14));
    expect(session.game.phase, Phase.lobby);
    await tester.pump(const Duration(seconds: 2));
    expect(session.game.phase, Phase.reveal);
    expect(session.game.players.where((p) => p.isBot), isEmpty);
    session.dispose();
  });

  testWidgets('a full random room starts at once', (tester) async {
    final session = quickRoom();
    for (var i = 0; i < 5; i++) {
      session.addPlayer('p$i', 'لاعب');
    }
    expect(session.game.phase, Phase.reveal);
    expect(session.addPlayer('late', 'متأخر'), isFalse);
    session.dispose();
  });

  testWidgets('only the host can start, and only with enough players', (tester) async {
    final game = GameEngine(code: 'ROOM00', maxPlayers: 8, mafiaCount: 1)
      ..addPlayer('me', 'أنا');
    final session = HostSession(game, 'me');
    for (var i = 0; i < 3; i++) {
      session.addPlayer('p$i', 'لاعب');
    }
    session.send({'a': 'start'});
    expect(game.phase, Phase.lobby, reason: 'only 4 players');
    session.addPlayer('p3', 'لاعب');
    session.handle('p0', {'a': 'start'});
    expect(game.phase, Phase.lobby, reason: 'not the host');
    session.send({'a': 'start'});
    expect(game.phase, Phase.reveal);
    session.dispose();
  });

  testWidgets('leaving the waiting room frees the seat', (tester) async {
    final game = GameEngine(code: 'ROOM00', maxPlayers: 5, mafiaCount: 1)
      ..addPlayer('me', 'أنا');
    final session = HostSession(game, 'me');
    session.addPlayer('p0', 'لاعب');
    session.playerGone('p0');
    expect(game.players, hasLength(1));
    session.dispose();
  });

  testWidgets('a bot game plays itself to the end even if you do nothing', (tester) async {
    final session = startBotGame(name: 'أنا', bots: 7, mafiaCount: 2);
    expect(session.view!['phase'], 'reveal');
    final seen = <String>{};
    for (var s = 0; s < 3600 && session.game.phase != Phase.over; s++) {
      await tester.pump(const Duration(seconds: 1));
      seen.add(session.view!['phase'] as String);
    }
    expect(session.game.phase, Phase.over);
    expect(seen, containsAll(['night', 'dawn', 'day', 'voting', 'verdict', 'over']));
    expect(session.view!['winner'], isNotNull);
    expect(session.game.chat, isNotEmpty, reason: 'bots should talk');
    session.dispose();
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('a game where you are the only human can be sped along', (tester) async {
    final session = startBotGame(name: 'أنا', bots: 5, mafiaCount: 1);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 7));
    if (session.game.phase == Phase.day && session.game.player(session.localId)!.alive) {
      session.send({'a': 'ready'});
      expect(session.game.phase, Phase.voting);
    }
    session.dispose();
    await tester.pump(const Duration(minutes: 2));
  });
}
