import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/session.dart';
import '../net/online.dart';
import 'game_screen.dart';
import 'theme.dart';

/// Joins the fullest open room, or opens a new one for the next person to find.
class QuickMatchScreen extends StatefulWidget {
  const QuickMatchScreen({super.key, required this.name});

  final String name;

  @override
  State<QuickMatchScreen> createState() => _QuickMatchScreenState();
}

class _QuickMatchScreenState extends State<QuickMatchScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _error = null);
    final lobby = Lobby();
    try {
      await lobby.connected.timeout(const Duration(seconds: 10));
      // Give the room list a moment to arrive. The random part keeps two people who
      // tap together from both finding nothing and opening separate rooms.
      await Future<void>.delayed(
        Duration(milliseconds: 1200 + Random().nextInt(1500)),
      );
      final GameSession session = await _joinOrCreate(lobby);
      if (!mounted) {
        await session.leave();
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(session: session)),
      );
    } catch (_) {
      await lobby.close();
      if (mounted) {
        setState(() => _error = 'ما قدرنا نتصل بالسيرفر، تأكد من الإنترنت');
      }
    }
  }

  Future<GameSession> _joinOrCreate(Lobby lobby) async {
    for (final room in lobby.rooms.where((r) => !r.isFull)) {
      try {
        final session = await RemoteSession.join(room.code, widget.name);
        await lobby.close();
        return session;
      } on JoinFailure {
        // That room just filled up or closed, so try the next one.
      }
    }
    return createRoom(
      name: widget.name,
      maxPlayers: quickRoomSize,
      mafiaCount: 1,
      quick: true,
      lobby: lobby,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دخول عشوائي')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text('ندور لك على غرفة...', style: TextStyle(fontSize: 18, color: mist)),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _search, child: const Text('حاول مرة ثانية')),
                  ],
                ),
        ),
      ),
    );
  }
}
