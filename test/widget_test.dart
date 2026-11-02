import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia/game/engine.dart';
import 'package:mafia/game/session.dart';
import 'package:mafia/main.dart';
import 'package:mafia/net/online.dart';
import 'package:mafia/ui/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MafiaApp());
    await tester.pump();
  }

  testWidgets('home shows the four options', (tester) async {
    await pumpHome(tester);
    expect(find.text('اللعب مع بوتات'), findsOneWidget);
    expect(find.text('دخول عشوائي'), findsOneWidget);
    expect(find.text('إنشاء لعبة'), findsOneWidget);
    expect(find.text('دخول السيرفرات'), findsOneWidget);
  });

  testWidgets('no option opens without a name', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('اللعب مع بوتات'));
    await tester.pumpAndSettle();
    expect(find.text('لازم تكتب اسمك أول'), findsOneWidget);
    expect(find.text('ابدأ اللعب'), findsNothing);
  });

  testWidgets('bot setup opens with a name and limits the mafia', (tester) async {
    await pumpHome(tester);
    await tester.enterText(find.byType(TextField), 'عبدالله');
    await tester.tap(find.text('اللعب مع بوتات'));
    await tester.pumpAndSettle();
    expect(find.text('ابدأ اللعب'), findsOneWidget);
    expect(find.text('عدد البوتات'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(3));
  });

  testWidgets('a bot game shows your role on the table', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final session = startBotGame(name: 'عبدالله', bots: 6, mafiaCount: 2);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(session: session)),
    );
    await tester.pump();
    expect(find.text('عبدالله 1'), findsOneWidget);
    final role = session.game.player(session.localId)!.role;
    expect(role, isA<Role>());
    expect(find.textContaining('أنت '), findsWidgets);
    // Closing the screen stops the game and its timers.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  test('random room code avoids look-alike characters', () {
    for (var i = 0; i < 200; i++) {
      expect(randomRoomCode(), matches(RegExp(r'^[A-HJKMNP-Z2-9]{6}$')));
    }
  });
}
