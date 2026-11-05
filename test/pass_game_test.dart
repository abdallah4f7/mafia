import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia/game/engine.dart';
import 'package:mafia/game/pass_game.dart';
import 'package:mafia/main.dart';
import 'package:mafia/ui/pass_game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const names = ['سارة', 'خالد', 'نورة', 'فهد', 'ريم', 'ماجد', 'هند'];

PassGame newGame({int mafia = 1, int seed = 1}) =>
    PassGame(names, mafia, random: Random(seed));

void dealRoles(PassGame pass) {
  while (pass.game.phase == Phase.reveal) {
    pass.open();
    pass.finishTurn();
  }
}

/// Plays every remaining turn of the current night or vote.
void passAround(PassGame pass, String? Function(EnginePlayer holder) pick) {
  while (pass.holder != null) {
    final holder = pass.holder!;
    pass.open();
    if (pass.targets.isEmpty && pass.game.phase != Phase.voting) {
      pass.finishTurn();
      continue;
    }
    pass.choose(pick(holder));
    if (pass.checked != null) pass.finishTurn();
    if (identical(pass.holder, holder) && pass.game.phase == Phase.night) {
      fail('${holder.role} was stuck on their turn');
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the phone goes to everyone in order, then the first night starts', () {
    final pass = newGame();
    final seen = <String>[];
    while (pass.game.phase == Phase.reveal) {
      expect(pass.opened, isFalse, reason: 'the role must wait for the next person');
      seen.add(pass.holder!.name);
      pass.open();
      pass.finishTurn();
    }
    expect(seen, names);
    expect(pass.game.phase, Phase.night);
    expect(pass.holder!.role, Role.mafia);
  });

  test('the night calls mafia, doctor, then detective, with the right choices', () {
    final pass = newGame(mafia: 2);
    dealRoles(pass);
    final called = <Role>[];
    while (pass.holder != null) {
      final me = pass.holder!;
      called.add(me.role);
      pass.open();
      final options = pass.targets;
      switch (me.role) {
        case Role.mafia:
          expect(options.any((p) => p.role == Role.mafia), isFalse);
        case Role.doctor:
          expect(options, contains(me));
        case Role.detective:
          expect(options, isNot(contains(me)));
        case Role.citizen:
          fail('citizens sleep through the night');
      }
      pass.choose(options.first.id);
      if (pass.checked != null) pass.finishTurn();
    }
    expect(called, [Role.mafia, Role.doctor, Role.detective]);
    expect(pass.game.phase, Phase.dawn);
  });

  test('one mafia pick counts for all of them, and a dead role is not called', () {
    final pass = newGame(mafia: 2);
    dealRoles(pass);
    final doctor = pass.game.players.firstWhere((p) => p.role == Role.doctor);
    passAround(pass, (holder) {
      if (holder.role == Role.mafia) return doctor.id;
      return pass.targets.firstWhere((p) => p.id != doctor.id).id;
    });
    expect(doctor.alive, isFalse);
    pass.next(); // Day.
    pass.next(); // Voting.
    passAround(pass, (_) => null);
    pass.next(); // The second night.
    expect(pass.game.phase, Phase.night);
    final called = <Role>[];
    passAround(pass, (holder) {
      called.add(holder.role);
      return pass.targets.first.id;
    });
    expect(called, [Role.mafia, Role.detective]);
  });

  test('the detective sees the truth during their own turn', () {
    final pass = newGame();
    dealRoles(pass);
    final mafia = pass.game.players.firstWhere((p) => p.role == Role.mafia);
    while (pass.holder!.role != Role.detective) {
      pass.open();
      final options = pass.targets;
      options.isEmpty ? pass.finishTurn() : pass.choose(options.first.id);
    }
    final detective = pass.holder!;
    pass.open();
    pass.choose(mafia.id);
    expect(pass.checked, mafia);
    expect(pass.holder, detective, reason: 'the phone stays until they read it');
    pass.finishTurn();
    expect(identical(pass.holder, detective), isFalse);
  });

  test('the dead no longer get the phone', () {
    final pass = newGame();
    dealRoles(pass);
    final victim = pass.game.players.firstWhere((p) => p.role == Role.citizen);
    passAround(pass, (holder) {
      if (holder.role == Role.mafia) return victim.id;
      // The doctor protects someone else, so the kill goes through.
      return pass.targets.firstWhere((p) => p.id != victim.id).id;
    });
    expect(pass.game.phase, Phase.dawn);
    expect(pass.holder, isNull);
    expect(victim.alive, isFalse);
    pass.next();
    expect(pass.game.phase, Phase.day);
    pass.next();
    expect(pass.game.phase, Phase.voting);
    final voters = <EnginePlayer>[];
    passAround(pass, (holder) {
      voters.add(holder);
      return null;
    });
    expect(voters, hasLength(names.length - 1));
    expect(voters.contains(victim), isFalse);
    expect(pass.game.phase, Phase.verdict);
    expect(pass.game.votedOut, isNull);
  });

  test('every game ends, whatever the players pick', () {
    for (var seed = 0; seed < 300; seed++) {
      final random = Random(seed);
      final pass = newGame(mafia: 1 + seed % 3, seed: seed);
      var steps = 0;
      while (pass.game.phase != Phase.over) {
        expect(++steps, lessThan(500), reason: 'seed $seed never ended');
        if (pass.holder == null) {
          pass.next();
        } else if (pass.game.phase == Phase.reveal) {
          pass.open();
          pass.finishTurn();
        } else {
          passAround(pass, (_) {
            final options = pass.targets;
            return options[random.nextInt(options.length)].id;
          });
        }
      }
      expect(pass.game.winner, isNotNull);
    }
  });

  test('shared names get their seat number, others stay plain', () {
    final pass = PassGame(['سارة', 'سارة', 'خالد', 'نورة', 'فهد'], 1);
    expect(pass.label(pass.game.players[0]), 'سارة 1');
    expect(pass.label(pass.game.players[1]), 'سارة 2');
    expect(pass.label(pass.game.players[2]), 'خالد');
  });

  group('screens', () {
    Future<void> openSetup(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MafiaApp());
      await tester.pump();
      await tester.tap(find.text('لعب على جوال واحد'));
      await tester.pumpAndSettle();
    }

    Future<void> addName(WidgetTester tester, String name) async {
      await tester.enterText(find.byType(TextField), name);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    FilledButton startButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'ابدأ اللعب'),
    );

    testWidgets('a whole game plays through the screens on a small phone', (tester) async {
      tester.view.physicalSize = const Size(960, 1704);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final everyone = [for (var i = 1; i <= maxPlayersLimit; i++) 'لاعب رقم $i'];
      final pass = PassGame(everyone, 3, random: Random(4));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: PassGameScreen(pass: pass, speak: (_) async {}),
        ),
      );

      final phases = <Phase>{};
      var taps = 0;
      while (find.text('لعبة جديدة').evaluate().isEmpty) {
        expect(++taps, lessThan(2000), reason: 'the game never ended');
        phases.add(pass.game.phase);
        if (find.byType(ListTile).evaluate().isNotEmpty) {
          await tester.tap(find.byType(ListTile).first);
          await tester.pump();
          await tester.tap(find.text('تأكيد'));
        } else if (find.text('ابدأوا التصويت').evaluate().isNotEmpty) {
          await tester.tap(find.text('ابدأوا التصويت'));
        } else {
          await tester.tap(find.text('متابعة'));
        }
        await tester.pump();
      }
      expect(pass.game.phase, Phase.over);
      expect(
        phases,
        containsAll([Phase.reveal, Phase.night, Phase.dawn, Phase.day, Phase.voting, Phase.verdict]),
      );
    });

    testWidgets('the night is called out loud and in writing, secrets hidden', (tester) async {
      final spoken = <String>[];
      final pass = newGame();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: PassGameScreen(pass: pass, speak: (text) async => spoken.add(text)),
        ),
      );
      for (var i = 0; i < names.length * 2; i++) {
        await tester.tap(find.text('متابعة'));
        await tester.pump();
      }
      const call = 'المافيا ياخذ الجوال ويحدد من يذبح';
      expect(pass.game.phase, Phase.night);
      expect(spoken.last, contains('حطوا الجوال بالنص وغمضوا عيونكم'));
      expect(spoken.last, contains(call));
      expect(find.text(call), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);

      await tester.tap(find.text('متابعة'));
      await tester.pump();
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('it opens without the home name, and needs 5 names to start', (tester) async {
      await openSetup(tester);
      for (final name in names.take(4)) {
        await addName(tester, name);
      }
      expect(startButton(tester).onPressed, isNull);
      await addName(tester, names[4]);
      expect(startButton(tester).onPressed, isNotNull);
    });

    testWidgets('a role only shows after the next person presses continue', (tester) async {
      await openSetup(tester);
      for (final name in names.take(4)) {
        await addName(tester, name);
      }
      // The fifth name is still in the box when the game starts.
      await tester.enterText(find.byType(TextField), names[4]);
      await tester.pump();
      await tester.tap(find.text('ابدأ اللعب'));
      await tester.pumpAndSettle();

      expect(find.text('عطوا الجوال لـ'), findsOneWidget);
      expect(find.text(names[0]), findsOneWidget);
      expect(find.textContaining('أنت '), findsNothing);

      await tester.tap(find.text('متابعة'));
      await tester.pump();
      expect(find.textContaining('أنت '), findsOneWidget);

      await tester.tap(find.text('متابعة'));
      await tester.pump();
      expect(find.text('عطوا الجوال لـ'), findsOneWidget);
      expect(find.text(names[1]), findsOneWidget);
      expect(find.textContaining('أنت '), findsNothing);
    });
  });
}
