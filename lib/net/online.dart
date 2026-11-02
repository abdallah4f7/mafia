import 'dart:async';

import 'package:realtime_client/realtime_client.dart';

import '../config.dart';
import '../game/engine.dart';
import '../game/session.dart';

/// All online play goes through Supabase Realtime channels; nothing is stored.
///
/// - `mafia-lobby`: a presence list of the rooms that are waiting for players.
/// - `mafia-room-CODE`: where people knock to join a room.
/// - `mafia-p-CODE-SECRET`: one private line between the host and each player.
///   Secret roles only travel here, so they don't show up in the others' traffic.
RealtimeClient? _client;

RealtimeClient newRealtimeClient() => RealtimeClient(
  '${supabaseUrl.replaceFirst('https://', 'wss://')}/realtime/v1',
  params: {'apikey': supabasePublishableKey},
);

RealtimeClient get realtime => _client ??= newRealtimeClient();

const _heartbeat = Duration(seconds: 8);
const _timeout = Duration(seconds: 30);

class RoomInfo {
  RoomInfo(this.code, this.host, this.count, this.max, this.mafia, this.quick);

  final String code;
  final String host;
  final int count;
  final int max;
  final int mafia;
  final bool quick;

  bool get isFull => count >= max;

  Map<String, dynamic> toJson() => {
    'code': code,
    'host': host,
    'count': count,
    'max': max,
    'mafia': mafia,
    'quick': quick,
  };

  static RoomInfo? tryParse(Map<String, dynamic> j) {
    try {
      return RoomInfo(
        j['code'] as String,
        j['host'] as String,
        j['count'] as int,
        j['max'] as int,
        j['mafia'] as int,
        j['quick'] as bool,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A live view of the waiting rooms. A host also uses it to list its own room,
/// which disappears by itself if the host drops off.
class Lobby {
  Lobby({String? key, RealtimeClient? client}) : _rt = client ?? realtime {
    _channel = _rt.channel(
      'mafia-lobby',
      RealtimeChannelConfig(key: key ?? randomId()),
    );
    _channel.onPresenceSync((_) => _sync());
    _channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _subscribed = true;
        if (!_connected.isCompleted) _connected.complete();
        final pending = _announced;
        if (pending != null) _channel.track(pending);
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        if (!_connected.isCompleted) {
          _connected.completeError(error ?? 'lobby: $status');
        }
      }
    });
  }

  final RealtimeClient _rt;
  late final RealtimeChannel _channel;
  final _connected = Completer<void>();
  final _rooms = StreamController<List<RoomInfo>>.broadcast();
  List<RoomInfo> rooms = const [];
  Map<String, dynamic>? _announced;
  bool _subscribed = false;
  bool _closed = false;

  Stream<List<RoomInfo>> get changes => _rooms.stream;
  Future<void> get connected => _connected.future;

  void _sync() {
    final list = <RoomInfo>[];
    for (final state in _channel.presenceState()) {
      for (final presence in state.presences) {
        final room = RoomInfo.tryParse(presence.payload);
        if (room != null) list.add(room);
      }
    }
    list.sort((a, b) => b.count.compareTo(a.count));
    rooms = list;
    if (!_closed) _rooms.add(list);
  }

  void announce(RoomInfo room) {
    _announced = room.toJson();
    if (_subscribed) _channel.track(_announced!);
  }

  /// Takes the room off the list, once the game has started.
  void withdraw() {
    _announced = null;
    if (_subscribed) _channel.untrack();
  }

  Future<void> close() async {
    _closed = true;
    await _rooms.close();
    await _rt.removeChannel(_channel);
  }
}

class _Peer {
  _Peer(this.id, this.channel);

  final String id;
  final RealtimeChannel channel;
  DateTime lastSeen = DateTime.now();
  DateTime lastChat = DateTime.fromMillisecondsSinceEpoch(0);
  bool live = false;
}

/// Puts a [HostSession] online: lets people in, relays their actions to the game
/// and sends each of them their own view of it.
class OnlineHost {
  OnlineHost(this.session, this.lobby, {RealtimeClient? client})
    : _rt = client ?? realtime {
    final code = session.game.code;
    _room = _rt.channel('mafia-room-$code');
    // Opening or closing a channel inside a message callback breaks the client,
    // which is still looping over its channels, so that work waits a moment.
    _room
        .onBroadcast(
          event: 'join',
          callback: (message) => scheduleMicrotask(() => _onJoin(message)),
        )
        .subscribe();
    session.onChanged = _queuePush;
    _beat = Timer.periodic(_heartbeat, (_) => _tick());
    _announce();
  }

  final RealtimeClient _rt;
  final HostSession session;
  final Lobby lobby;
  late final RealtimeChannel _room;
  final _peers = <String, _Peer>{};
  late final Timer _beat;
  Timer? _pushTimer;
  bool _closed = false;

  void _announce() {
    final game = session.game;
    if (game.phase != Phase.lobby || game.isFull) {
      lobby.withdraw();
      return;
    }
    lobby.announce(
      RoomInfo(
        game.code,
        game.player(session.localId)?.name ?? '',
        game.players.length,
        game.maxPlayers,
        game.mafiaCount,
        game.quick,
      ),
    );
  }

  void _onJoin(Map<String, dynamic> message) {
    final payload = message['payload'] ?? message;
    final secret = payload['secret'];
    final rawName = payload['name'];
    if (_closed || secret is! String || rawName is! String) return;
    if (secret.length < 8 || secret.length > 32) return;
    final name = rawName.trim();
    if (name.isEmpty) return;

    final known = _peers[secret];
    if (known != null) {
      known.lastSeen = DateTime.now();
      if (known.live) _sendView(known);
      return;
    }

    final peer = _Peer(randomId(), _openLine(secret));
    _peers[secret] = peer;
    peer.channel.subscribe((status, _) {
      if (status != RealtimeSubscribeStatus.subscribed || peer.live) return;
      peer.live = true;
      final accepted = session.game.player(peer.id) != null ||
          session.addPlayer(peer.id, name.length > 20 ? name.substring(0, 20) : name);
      if (accepted) {
        _sendView(peer);
      } else {
        _reject(secret, peer);
      }
    });
  }

  RealtimeChannel _openLine(String secret) {
    final channel = _rt.channel('mafia-p-${session.game.code}-$secret');
    channel.onBroadcast(
      event: 'c',
      callback: (message) {
        final peer = _peers[secret];
        final payload = message['payload'] ?? message;
        if (peer == null || payload is! Map) return;
        final action = Map<String, dynamic>.from(payload);
        scheduleMicrotask(() => _onAction(secret, peer, action));
      },
    );
    return channel;
  }

  void _onAction(String secret, _Peer peer, Map<String, dynamic> action) {
    peer.lastSeen = DateTime.now();
    switch (action['a']) {
      case 'ping':
        return;
      case 'leave':
        _drop(secret, peer);
      case 'chat':
        final now = DateTime.now();
        if (now.difference(peer.lastChat) < const Duration(milliseconds: 500)) return;
        peer.lastChat = now;
        session.handle(peer.id, action);
      default:
        session.handle(peer.id, action);
    }
  }

  Future<void> _reject(String secret, _Peer peer) async {
    final reason = session.game.phase == Phase.lobby
        ? 'الغرفة ممتلئة'
        : 'اللعبة بدأت خلاص';
    await peer.channel.sendBroadcastMessage(
      event: 'reject',
      payload: {'reason': reason},
    );
    _peers.remove(secret);
    await _rt.removeChannel(peer.channel);
  }

  void _drop(String secret, _Peer peer) {
    _peers.remove(secret);
    _rt.removeChannel(peer.channel);
    session.playerGone(peer.id);
  }

  void _tick() {
    final now = DateTime.now();
    for (final entry in _peers.entries.toList()) {
      if (now.difference(entry.value.lastSeen) > _timeout) {
        _drop(entry.key, entry.value);
      } else if (entry.value.live) {
        entry.value.channel.sendBroadcastMessage(event: 'beat', payload: {});
      }
    }
  }

  /// Bots can act several times in a moment, so changes are sent as a batch.
  void _queuePush() {
    if (_closed) return;
    _announce();
    _pushTimer ??= Timer(const Duration(milliseconds: 120), () {
      _pushTimer = null;
      if (_closed) return;
      for (final peer in _peers.values) {
        if (peer.live) _sendView(peer);
      }
    });
  }

  void _sendView(_Peer peer) {
    peer.channel.sendBroadcastMessage(
      event: 'v',
      payload: session.viewOf(peer.id),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _beat.cancel();
    _pushTimer?.cancel();
    session.onChanged = null;
    for (final peer in _peers.values) {
      if (peer.live) {
        await peer.channel.sendBroadcastMessage(event: 'bye', payload: {});
      }
      await _rt.removeChannel(peer.channel);
    }
    _peers.clear();
    await _rt.removeChannel(_room);
    await lobby.close();
  }
}

/// A [HostSession] with people connected to it from elsewhere.
class HostedRoom extends GameSession {
  HostedRoom(this.host, this.online) {
    host.addListener(_copy);
    _copy();
  }

  final HostSession host;
  final OnlineHost online;

  void _copy() => setView(host.view!);

  @override
  void send(Map<String, dynamic> action) => host.send(action);

  @override
  Future<void> leave() async {
    host.removeListener(_copy);
    await online.close();
    host.dispose();
  }
}

class JoinFailure implements Exception {
  JoinFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The game as seen from a player who joined someone else's room.
class RemoteSession extends GameSession {
  RemoteSession._(this.code, this._secret, this._rt);

  final RealtimeClient _rt;
  final String code;
  final String _secret;
  late RealtimeChannel _line;
  late RealtimeChannel _room;
  Timer? _beat;
  DateTime _lastHeard = DateTime.now();
  bool _left = false;

  /// Knocks on the room and waits to be let in. Throws [JoinFailure] if it can't.
  static Future<RemoteSession> join(
    String code,
    String name, {
    RealtimeClient? client,
  }) async {
    final session = RemoteSession._(code, randomId(16), client ?? realtime);
    await session._connect(name);
    return session;
  }

  Future<void> _connect(String name) async {
    final admitted = Completer<void>();
    void fail(String message) {
      if (!admitted.isCompleted) admitted.completeError(JoinFailure(message));
    }

    final lineOpen = Completer<void>();
    _line = _rt.channel('mafia-p-$code-$_secret')
      ..onBroadcast(
        event: 'v',
        callback: (message) {
          _lastHeard = DateTime.now();
          final payload = message['payload'] ?? message;
          setView(Map<String, dynamic>.from(payload as Map));
          if (!admitted.isCompleted) admitted.complete();
        },
      )
      ..onBroadcast(
        event: 'beat',
        callback: (_) => _lastHeard = DateTime.now(),
      )
      ..onBroadcast(
        event: 'reject',
        callback: (message) {
          final payload = message['payload'] ?? message;
          fail('${payload['reason'] ?? 'ما قدرنا ندخلك'}');
        },
      )
      ..onBroadcast(
        event: 'bye',
        callback: (_) => close('منشئ الغرفة طلع، وانتهت اللعبة'),
      )
      ..subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed &&
            !lineOpen.isCompleted) {
          lineOpen.complete();
        }
      });

    final roomOpen = Completer<void>();
    _room = _rt.channel('mafia-room-$code')
      ..subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed &&
            !roomOpen.isCompleted) {
          roomOpen.complete();
        }
      });

    Timer? knocking;
    try {
      await Future.wait([lineOpen.future, roomOpen.future])
          .timeout(const Duration(seconds: 10));
      void knock() => _room.sendBroadcastMessage(
        event: 'join',
        payload: {'secret': _secret, 'name': name},
      );
      knock();
      // The host may still be opening its side, so knock until someone answers.
      knocking = Timer.periodic(const Duration(seconds: 2), (_) => knock());
      await admitted.future.timeout(const Duration(seconds: 9));
    } on TimeoutException {
      await _disconnect();
      throw JoinFailure('ما لقينا غرفة بهالكود، تأكد منه وجرب مرة ثانية');
    } on JoinFailure {
      await _disconnect();
      rethrow;
    } finally {
      knocking?.cancel();
    }

    await _rt.removeChannel(_room);
    _lastHeard = DateTime.now();
    _beat = Timer.periodic(_heartbeat, (_) {
      send({'a': 'ping'});
      if (DateTime.now().difference(_lastHeard) > _timeout) {
        _beat?.cancel();
        close('انقطع الاتصال بمنشئ الغرفة');
      }
    });
  }

  @override
  void send(Map<String, dynamic> action) {
    if (_left) return;
    _line.sendBroadcastMessage(event: 'c', payload: action);
  }

  Future<void> _disconnect() async {
    _beat?.cancel();
    await _rt.removeChannel(_line);
    await _rt.removeChannel(_room);
  }

  @override
  Future<void> leave() async {
    if (_left) return;
    send({'a': 'leave'});
    _left = true;
    await _disconnect();
  }
}

/// Opens a new online room with the player in it.
HostedRoom createRoom({
  required String name,
  required int maxPlayers,
  required int mafiaCount,
  bool quick = false,
  Lobby? lobby,
  RealtimeClient? client,
}) {
  final id = randomId();
  final game = GameEngine(
    code: randomRoomCode(),
    maxPlayers: maxPlayers,
    mafiaCount: mafiaCount,
    quick: quick,
  )..addPlayer(id, name);
  final session = HostSession(game, id);
  return HostedRoom(
    session,
    OnlineHost(
      session,
      lobby ?? Lobby(key: game.code, client: client),
      client: client,
    ),
  );
}

/// A game on this device against bots. It needs no connection at all.
HostSession startBotGame({
  required String name,
  required int bots,
  required int mafiaCount,
}) {
  final id = randomId();
  final game = GameEngine(
    code: 'BOTS',
    maxPlayers: bots + 1,
    mafiaCount: mafiaCount,
  )..addPlayer(id, name);
  final session = HostSession(game, id);
  session.addBots(bots);
  session.startGame();
  return session;
}

const quickRoomSize = 10;
