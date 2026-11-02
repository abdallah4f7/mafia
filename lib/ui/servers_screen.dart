import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/online.dart';
import 'game_screen.dart';
import 'theme.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, required this.name});

  final String name;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final _code = TextEditingController();
  final _search = TextEditingController();
  late final Lobby _lobby;
  StreamSubscription<List<RoomInfo>>? _sub;
  List<RoomInfo> _rooms = const [];
  bool _loading = true;
  bool _failed = false;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _lobby = Lobby();
    _sub = _lobby.changes.listen((rooms) {
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    });
    _lobby.connected.timeout(const Duration(seconds: 10)).then((_) {
      // An empty list sends no update, so stop the spinner after a moment anyway.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _loading = false);
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lobby.close();
    _code.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _join(String code) async {
    if (_joining) return;
    setState(() => _joining = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final session = await RemoteSession.join(code, widget.name);
      if (!mounted) {
        await session.leave();
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(session: session)),
      );
    } on JoinFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _joining = false);
    }
  }

  void _joinByCode() {
    final code = _code.text.trim().toUpperCase();
    if (code.length == 6) _join(code);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final shown = _rooms
        .where(
          (r) =>
              query.isEmpty ||
              r.host.toLowerCase().contains(query) ||
              r.code.toLowerCase().contains(query),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('السيرفرات')),
      body: SafeArea(
        child: Narrow(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _joinByCode(),
                        style: const TextStyle(fontSize: 20, letterSpacing: 4),
                        decoration: const InputDecoration(
                          hintText: 'كود الغرفة',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _code.text.trim().length == 6 && !_joining
                          ? _joinByCode
                          : null,
                      child: const Text('ادخل'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'دور باسم صاحب الغرفة',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                if (_joining) const LinearProgressIndicator(),
                Expanded(child: _list(shown)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(List<RoomInfo> rooms) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return const Center(child: Text('ما قدرنا نتصل بالسيرفر، تأكد من الإنترنت'));
    }
    if (rooms.isEmpty) {
      return const Center(
        child: Text(
          'ما فيه غرف مفتوحة الحين.\nسوّ غرفتك من «إنشاء لعبة».',
          textAlign: TextAlign.center,
          style: TextStyle(color: mist),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4),
      itemCount: rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final room = rooms[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            onTap: room.isFull || _joining ? null : () => _join(room.code),
            leading: const Icon(Icons.meeting_room, color: gold),
            title: Text(
              room.quick ? 'غرفة عشوائية' : 'غرفة ${room.host}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              room.quick
                  ? 'كود ${room.code}'
                  : 'مافيا: ${room.mafia} • كود ${room.code}',
              style: const TextStyle(color: mist),
            ),
            trailing: Text(
              '${room.count}/${room.max}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}
