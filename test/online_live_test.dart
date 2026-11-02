import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mafia/game/session.dart';
import 'package:mafia/net/online.dart';
import 'package:realtime_client/realtime_client.dart';

// Plays over the real Supabase Realtime service, so it only runs on request:
//   $env:LIVE='1'; flutter test test/online_live_test.dart

Future<void> until(
  bool Function() done,
  String what, {
  Duration limit = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(limit);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  // No testWidgets here: the widget binding would block real sockets.
  final skip = Platform.environment['LIVE'] == null ? 'set LIVE=1 to run' : null;

  test('a full online round: list, join, secrets, play, host leaves', () async {
    // Each participant gets its own connection, as they would on their own device.
    final sockets = <RealtimeClient>[];
    RealtimeClient socket() {
      final client = newRealtimeClient();
      sockets.add(client);
      return client;
    }

    final watcher = Lobby(client: socket());
    await watcher.connected;

    final room = createRoom(
      name: 'صاحب الغرفة',
      maxPlayers: 6,
      mafiaCount: 1,
      client: socket(),
    );
    final code = room.view!['code'] as String;

    await until(
      () => watcher.rooms.any((r) => r.code == code),
      'room in the server list',
    );

    // A code nobody has opened fails cleanly instead of hanging.
    await expectLater(
      RemoteSession.join('ZZZZZZ', 'ضايع', client: socket()),
      throwsA(isA<JoinFailure>()),
    );

    // Same name on purpose: that has to be allowed.
    final clients = <RemoteSession>[];
    for (final name in ['سعد', 'سعد', 'منى', 'ليلى']) {
      clients.add(await RemoteSession.join(code, name, client: socket()));
    }
    await until(
      () => (room.view!['players'] as List).length == 5,
      'five players in the room',
    );
    await until(
      () => watcher.rooms.any((r) => r.code == code && r.count == 5),
      'server list showing the new count',
    );

    // Only the host may start the game.
    clients.first.send({'a': 'start'});
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(room.view!['phase'], 'lobby');

    room.send({'a': 'start'});
    await until(
      () => clients.every((c) => c.view!['phase'] == 'reveal'),
      'everyone seeing the role reveal',
    );

    await until(
      () => !watcher.rooms.any((r) => r.code == code),
      'started room leaving the server list',
    );

    // Nobody receives anyone else's role, and everyone receives their own.
    final everyone = <GameSession>[room, ...clients];
    for (final s in everyone) {
      final players = (s.view!['players'] as List).cast<Map>();
      final mine = players.firstWhere((p) => p['id'] == s.view!['you']);
      expect(mine['role'], isNotNull);
      final known = players.where((p) => p['role'] != null);
      expect(known, hasLength(1), reason: jsonEncode(s.view));
    }

    await until(
      () => everyone.every((s) => s.view!['phase'] == 'night'),
      'night falling',
    );

    String roleOf(GameSession s) => ((s.view!['players'] as List).cast<Map>())
        .firstWhere((p) => p['id'] == s.view!['you'])['role'] as String;
    final ids = [for (final s in everyone) s.view!['you'] as String];

    for (final s in everyone) {
      final me = s.view!['you'];
      final role = roleOf(s);
      if (role == 'citizen') continue;
      s.send({'a': 'night', 't': ids.firstWhere((id) => id != me)});
    }
    await until(
      () => everyone.every((s) => s.view!['phase'] == 'dawn'),
      'dawn after every role acted',
    );

    await until(
      () => everyone.every((s) => s.view!['phase'] == 'day'),
      'day',
    );

    // Chat from a remote player reaches everybody.
    final alive = everyone.where((s) {
      final players = (s.view!['players'] as List).cast<Map>();
      return players.firstWhere((p) => p['id'] == s.view!['you'])['alive'] == true;
    }).toList();
    final speaker = alive.firstWhere((s) => s is RemoteSession);
    speaker.send({'a': 'chat', 'text': 'مرحبا'});
    await until(
      () => alive.every(
        (s) => (s.view!['chat'] as List).any((l) => l['t'] == 'مرحبا'),
      ),
      'chat reaching everyone',
    );

    for (final s in alive) {
      s.send({'a': 'ready'});
    }
    await until(
      () => everyone.every((s) => s.view!['phase'] == 'voting'),
      'voting after everyone was ready',
    );

    // The host leaving ends the game for everyone still connected.
    await room.leave();
    await until(
      () => clients.every((c) => c.closedReason != null),
      'clients told that the host left',
    );

    for (final c in clients) {
      await c.leave();
    }
    await watcher.close();
    for (final client in sockets) {
      await client.disconnect();
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
