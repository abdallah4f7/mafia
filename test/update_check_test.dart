import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mafia/ui/home_screen.dart';
import 'package:mafia/ui/theme.dart';
import 'package:mafia/update_check.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Client answering(String body, [int status = 200]) =>
    MockClient((_) async => http.Response(body, status));

void main() {
  test('a newer build is reported', () async {
    final update = await checkForUpdate(
      client: answering('{"version": "2.0.0", "build": 9}'),
      current: 3,
    );
    expect(update?.version, '2.0.0');
    expect(update?.build, 9);
  });

  test('the same or an older build is not', () async {
    for (final build in [3, 2]) {
      final update = await checkForUpdate(
        client: answering('{"version": "1.0.0", "build": $build}'),
        current: 3,
      );
      expect(update, isNull);
    }
  });

  test('a failed check is quiet', () async {
    expect(await checkForUpdate(client: answering('', 404)), isNull);
    expect(await checkForUpdate(client: answering('not json')), isNull);
    expect(await checkForUpdate(client: answering('{"version": 1}')), isNull);
    final offline = MockClient((_) async => throw const SocketException('offline'));
    expect(await checkForUpdate(client: offline), isNull);
  });

  test('the version in the code matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('\nversion: $appVersion+$appBuild'));
  });

  group('home screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pumpHome(WidgetTester tester, AppUpdate? update) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: HomeScreen(findUpdate: () async => update),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the notice when there is an update', (tester) async {
      await pumpHome(tester, const AppUpdate('2.0.0', 9));
      expect(find.textContaining('2.0.0'), findsOneWidget);
      expect(find.text('حدّث الآن'), findsOneWidget);
    });

    testWidgets('shows nothing when up to date', (tester) async {
      await pumpHome(tester, null);
      expect(find.text('حدّث الآن'), findsNothing);
    });
  });
}
