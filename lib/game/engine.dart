import 'dart:math';

enum Role { mafia, doctor, detective, citizen }

enum Phase { lobby, reveal, night, dawn, day, voting, verdict, over }

const minPlayers = 5;
const maxPlayersLimit = 15;
const maxMafia = 3;

/// The most mafia a game of [count] players can have and still start with
/// fewer mafia than everyone else.
int maxMafiaFor(int count) => min(maxMafia, (count - 1) ~/ 2);

Duration phaseDuration(Phase phase) => switch (phase) {
  Phase.reveal => const Duration(seconds: 8),
  Phase.night => const Duration(seconds: 30),
  Phase.dawn => const Duration(seconds: 6),
  Phase.day => const Duration(seconds: 75),
  Phase.voting => const Duration(seconds: 30),
  Phase.verdict => const Duration(seconds: 6),
  _ => Duration.zero,
};

class EnginePlayer {
  EnginePlayer(this.id, this.name, this.seat, {this.isBot = false});

  final String id;
  final String name;
  final int seat;
  final bool isBot;
  bool alive = true;
  bool online = true;
  Role role = Role.citizen;
}

class ChatLine {
  ChatLine(this.channel, this.senderId, this.sender, this.seat, this.text);

  /// public, mafia or dead.
  final String channel;
  final String senderId;
  final String sender;
  final int seat;
  final String text;
}

/// The rules of the game, with no timers or network: whoever hosts the room
/// feeds it actions and decides when to call [advance].
class GameEngine {
  GameEngine({
    required this.code,
    required this.maxPlayers,
    required this.mafiaCount,
    this.quick = false,
    Random? random,
  }) : _random = random ?? Random();

  final String code;
  final int maxPlayers;
  int mafiaCount;
  final bool quick;
  final Random _random;

  final players = <EnginePlayer>[];
  final chat = <ChatLine>[];
  Phase phase = Phase.lobby;
  int round = 0;
  String? hostId;
  int _nextSeat = 1;

  final mafiaVotes = <String, String>{};
  String? doctorTarget;
  String? detectiveTarget;
  final detectiveResults = <String, bool>{};
  final votes = <String, String?>{};
  final ready = <String>{};

  String? nightVictim;
  String? votedOut;
  Role? winner;

  EnginePlayer? player(String? id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<EnginePlayer> get alive => players.where((p) => p.alive).toList();
  bool get isFull => players.length >= maxPlayers;

  EnginePlayer addPlayer(String id, String name, {bool isBot = false}) {
    final p = EnginePlayer(id, name, _nextSeat++, isBot: isBot);
    players.add(p);
    return p;
  }

  void removeFromLobby(String id) {
    assert(phase == Phase.lobby);
    players.removeWhere((p) => p.id == id);
  }

  /// Why the game can't start yet, or null when it can.
  String? get startProblem {
    if (players.length < minPlayers) {
      return 'لازم $minPlayers لاعبين أقل شيء (الحين ${players.length})';
    }
    if (mafiaCount > maxMafiaFor(players.length)) {
      return '$mafiaCount مافيا يحتاجون ${mafiaCount * 2 + 1} لاعبين أقل شيء';
    }
    return null;
  }

  void start() {
    if (phase != Phase.lobby || startProblem != null) return;
    final shuffled = players.toList()..shuffle(_random);
    for (var i = 0; i < shuffled.length; i++) {
      shuffled[i].role = i < mafiaCount
          ? Role.mafia
          : i == mafiaCount
          ? Role.doctor
          : i == mafiaCount + 1
          ? Role.detective
          : Role.citizen;
    }
    phase = Phase.reveal;
  }

  bool submitNight(String actorId, String targetId) {
    final actor = player(actorId);
    final target = player(targetId);
    if (phase != Phase.night || actor == null || !actor.alive) return false;
    if (target == null || !target.alive) return false;
    switch (actor.role) {
      case Role.mafia:
        if (target.role == Role.mafia) return false;
        mafiaVotes[actorId] = targetId;
      case Role.doctor:
        doctorTarget = targetId;
      case Role.detective:
        if (targetId == actorId) return false;
        detectiveTarget = targetId;
      case Role.citizen:
        return false;
    }
    return true;
  }

  /// A null [targetId] skips the vote.
  bool submitVote(String voterId, String? targetId) {
    final voter = player(voterId);
    if (phase != Phase.voting || voter == null || !voter.alive) return false;
    if (targetId != null) {
      final target = player(targetId);
      if (target == null || !target.alive || targetId == voterId) return false;
    }
    votes[voterId] = targetId;
    return true;
  }

  bool markReady(String id) {
    final p = player(id);
    if (phase != Phase.day || p == null || !p.alive) return false;
    return ready.add(id);
  }

  /// True when nobody still has to act, so the host can skip the rest of the timer.
  /// Disconnected players never hold the game up.
  bool get phaseComplete {
    bool waitingOn(EnginePlayer p) => p.alive && p.online;
    switch (phase) {
      case Phase.night:
        for (final p in players.where(waitingOn)) {
          if (p.role == Role.mafia && !mafiaVotes.containsKey(p.id)) return false;
          if (p.role == Role.doctor && doctorTarget == null) return false;
          if (p.role == Role.detective && detectiveTarget == null) return false;
        }
        return true;
      case Phase.day:
        return players
            .where((p) => waitingOn(p) && !p.isBot)
            .every((p) => ready.contains(p.id));
      case Phase.voting:
        return players.where(waitingOn).every((p) => votes.containsKey(p.id));
      default:
        return false;
    }
  }

  void advance() {
    switch (phase) {
      case Phase.lobby:
      case Phase.over:
        return;
      case Phase.reveal:
        round = 1;
        _beginNight();
      case Phase.night:
        _resolveNight();
        phase = Phase.dawn;
      case Phase.dawn:
        _checkWinner();
        if (phase != Phase.over) {
          ready.clear();
          phase = Phase.day;
        }
      case Phase.day:
        votes.clear();
        phase = Phase.voting;
      case Phase.voting:
        _resolveVote();
        phase = Phase.verdict;
      case Phase.verdict:
        _checkWinner();
        if (phase != Phase.over) {
          round++;
          _beginNight();
        }
    }
  }

  void _beginNight() {
    mafiaVotes.clear();
    doctorTarget = null;
    detectiveTarget = null;
    phase = Phase.night;
  }

  void _resolveNight() {
    final target = _mostVoted(mafiaVotes.values);
    nightVictim = target != null && target != doctorTarget ? target : null;
    player(nightVictim)?.alive = false;
    final checked = player(detectiveTarget);
    if (checked != null) {
      // Removing first keeps the newest result last, even for a repeat check.
      detectiveResults.remove(checked.id);
      detectiveResults[checked.id] = checked.role == Role.mafia;
    }
  }

  void _resolveVote() {
    final counts = <String, int>{};
    var skips = 0;
    for (final target in votes.values) {
      if (target == null) {
        skips++;
      } else {
        counts[target] = (counts[target] ?? 0) + 1;
      }
    }
    votedOut = null;
    if (counts.isEmpty) return;
    final top = counts.values.reduce(max);
    final leaders = counts.keys.where((k) => counts[k] == top).toList();
    // A tie, or more skips than votes against anyone, leaves everyone alive.
    if (leaders.length == 1 && top > skips) {
      votedOut = leaders.single;
      player(votedOut)?.alive = false;
    }
  }

  /// A tied mafia picks at random between the leaders.
  String? _mostVoted(Iterable<String> ballots) {
    final counts = <String, int>{};
    for (final b in ballots) {
      counts[b] = (counts[b] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final top = counts.values.reduce(max);
    final leaders = counts.keys.where((k) => counts[k] == top).toList();
    return leaders[_random.nextInt(leaders.length)];
  }

  void _checkWinner() {
    final mafia = alive.where((p) => p.role == Role.mafia).length;
    final others = alive.length - mafia;
    if (mafia == 0) {
      winner = Role.citizen;
    } else if (mafia >= others) {
      winner = Role.mafia;
    }
    if (winner != null) phase = Phase.over;
  }

  /// Which chat [p] may write to right now, or null when they have to stay quiet.
  String? chatChannelFor(EnginePlayer p) {
    if (phase == Phase.lobby || phase == Phase.over) return 'public';
    if (!p.alive) return 'dead';
    if (phase == Phase.night) return p.role == Role.mafia ? 'mafia' : null;
    return 'public';
  }

  bool addChat(String senderId, String text) {
    final p = player(senderId);
    final clean = text.trim();
    if (p == null || clean.isEmpty) return false;
    final channel = chatChannelFor(p);
    if (channel == null) return false;
    chat.add(
      ChatLine(
        channel,
        p.id,
        p.name,
        p.seat,
        clean.length > 200 ? clean.substring(0, 200) : clean,
      ),
    );
    if (chat.length > 200) chat.removeAt(0);
    return true;
  }

  bool _canRead(EnginePlayer? viewer, ChatLine line) {
    if (phase == Phase.over || line.channel == 'public') return true;
    if (viewer == null) return false;
    if (line.channel == 'dead') return !viewer.alive;
    return viewer.role == Role.mafia;
  }

  /// Everything [viewerId] is allowed to know, and nothing else. This is the only
  /// thing that leaves the host, so a secret left out of it can't leak.
  Map<String, dynamic> viewFor(String viewerId) {
    final me = player(viewerId);
    final started = phase != Phase.lobby;
    final over = phase == Phase.over;
    final iAmMafia = started && me?.role == Role.mafia;

    bool roleVisible(EnginePlayer p) {
      if (!started) return false;
      return over ||
          !p.alive ||
          p.id == viewerId ||
          (iAmMafia && p.role == Role.mafia);
    }

    String? myTarget;
    if (phase == Phase.night && me != null) {
      myTarget = switch (me.role) {
        Role.mafia => mafiaVotes[me.id],
        Role.doctor => doctorTarget,
        Role.detective => detectiveTarget,
        Role.citizen => null,
      };
    }
    final publicVotes = phase == Phase.voting || phase == Phase.verdict;
    final visibleChat = chat.where((l) => _canRead(me, l)).toList();

    return {
      'code': code,
      'phase': phase.name,
      'round': round,
      'max': maxPlayers,
      'mafia': mafiaCount,
      'quick': quick,
      'host': hostId,
      'you': viewerId,
      'problem': startProblem,
      'players': [
        for (final p in players)
          {
            'id': p.id,
            'name': p.name,
            'seat': p.seat,
            'bot': p.isBot,
            'alive': p.alive,
            'online': p.online,
            if (roleVisible(p)) 'role': p.role.name,
          },
      ],
      'target': myTarget,
      if (iAmMafia && phase == Phase.night) 'mafiaVotes': mafiaVotes,
      if (publicVotes)
        'votes': votes.map((k, v) => MapEntry(k, v ?? '')),
      'ready': ready.contains(viewerId),
      if (started && me?.role == Role.detective)
        'checks': detectiveResults,
      'victim': nightVictim,
      'out': votedOut,
      'winner': winner?.name,
      'channel': me == null ? null : chatChannelFor(me),
      'chat': [
        for (final l in visibleChat.skip(max(0, visibleChat.length - 60)))
          {
            'c': l.channel,
            'id': l.senderId,
            'n': l.sender,
            's': l.seat,
            't': l.text,
          },
      ],
    };
  }
}
