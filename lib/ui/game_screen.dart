import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/session.dart';
import 'theme.dart';

const roleNames = {
  'mafia': 'مافيا',
  'doctor': 'طبيب',
  'detective': 'شايب',
  'citizen': 'مواطن',
};

const roleHints = {
  'mafia': 'كل ليلة تختارون مع بعض مين تقتلون. لا ينكشف أمركم بالنهار.',
  'doctor': 'كل ليلة تختار شخص تحميه، وتقدر تحمي نفسك.',
  'detective': 'كل ليلة تفحص شخص وتعرف إذا كان مافيا أو لا.',
  'citizen': 'ما عندك قدرة خاصة. ناقش وصوّت وطلّع المافيا.',
};

const roleIcons = {
  'mafia': Icons.theater_comedy,
  'doctor': Icons.medical_services,
  'detective': Icons.search,
  'citizen': Icons.person,
};

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.session});

  final GameSession session;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Timer _clock;
  bool _closedShown = false;

  GameSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    _session.removeListener(_changed);
    _session.leave();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final reason = _session.closedReason;
    if (reason != null && !_closedShown) {
      _closedShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: const Text('انتهت اللعبة'),
          content: Text(reason),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialog).pop();
                Navigator.of(context).pop();
              },
              child: const Text('رجوع'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _confirmLeave() async {
    final view = _session.view;
    final phase = view?['phase'];
    if (phase != 'over') {
      final isHost = view?['host'] == view?['you'] && view?['code'] != 'BOTS';
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('تطلع من اللعبة؟'),
          content: Text(
            isHost ? 'أنت منشئ الغرفة، وإذا طلعت تنتهي اللعبة عند الكل.' : 'ما تقدر ترجع لنفس اللعبة بعدها.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('أكمل'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('اطلع'),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final view = _session.view;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: view == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _table(_GameView(view)),
    );
  }

  Widget _table(_GameView v) {
    final left = _session.secondsLeft;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _confirmLeave),
        title: Text(v.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (left > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Center(
                child: Text(
                  '$left',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: left <= 5 ? blood : gold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final table = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Banner(v: v, session: _session),
                Expanded(child: _PlayerGrid(v: v, session: _session)),
              ],
            );
            final chat = _ChatPanel(v: v, session: _session);
            if (box.maxWidth >= 800) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: table),
                  SizedBox(width: 340, child: chat),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: table),
                SizedBox(height: box.maxHeight * 0.34, child: chat),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Typed access to the JSON view the host sends.
class _GameView {
  _GameView(this.json);

  final Map<String, dynamic> json;

  String get phase => json['phase'] as String;
  String get code => json['code'] as String;
  int get round => json['round'] as int;
  int get max => json['max'] as int;
  int get mafiaCount => json['mafia'] as int;
  bool get quick => json['quick'] as bool;
  bool get isHost => json['host'] == you;
  String get you => json['you'] as String;
  String? get problem => json['problem'] as String?;
  String? get target => json['target'] as String?;
  String? get winner => json['winner'] as String?;
  String? get channel => json['channel'] as String?;
  bool get ready => json['ready'] == true;
  List<Map<String, dynamic>> get players =>
      (json['players'] as List).map((p) => Map<String, dynamic>.from(p as Map)).toList();
  List<Map<String, dynamic>> get chat =>
      (json['chat'] as List).map((p) => Map<String, dynamic>.from(p as Map)).toList();
  Map<String, dynamic> get votes => Map<String, dynamic>.from(json['votes'] as Map? ?? {});
  Map<String, dynamic> get mafiaVotes =>
      Map<String, dynamic>.from(json['mafiaVotes'] as Map? ?? {});
  Map<String, dynamic> get checks => Map<String, dynamic>.from(json['checks'] as Map? ?? {});

  Map<String, dynamic>? playerById(String? id) {
    for (final p in players) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  Map<String, dynamic> get me => playerById(you) ?? const {};
  String? get myRole => me['role'] as String?;
  bool get iAmAlive => me['alive'] == true;

  String get title => switch (phase) {
    'lobby' => quick ? 'ندور على لاعبين' : 'غرفة الانتظار',
    'reveal' => 'دورك',
    'night' => 'الليلة $round',
    'dawn' => 'طلع الصبح',
    'day' => 'نقاش النهار',
    'voting' => 'التصويت',
    'verdict' => 'النتيجة',
    _ => 'انتهت اللعبة',
  };

  /// Whether tapping [p] does anything in this phase.
  bool canTarget(Map<String, dynamic> p) {
    if (!iAmAlive || p['alive'] != true) return false;
    final isMe = p['id'] == you;
    if (phase == 'voting') return !isMe;
    if (phase != 'night') return false;
    return switch (myRole) {
      'mafia' => p['role'] != 'mafia',
      'doctor' => true,
      'detective' => !isMe,
      _ => false,
    };
  }

  String? get action => switch (phase) {
    'night' => 'night',
    'voting' => 'vote',
    _ => null,
  };

  String? get selected => phase == 'voting' ? votes[you] as String? : target;
}

/// A bot's name already holds its seat number. People get the number added, since
/// two of them can share a name.
String _nameOf(Map<String, dynamic> p) =>
    p['bot'] == true ? '${p['name']}' : '${p['name']} ${p['seat']}';

String _label(Map<String, dynamic>? p) => p == null ? '' : _nameOf(p);

class _Banner extends StatelessWidget {
  const _Banner({required this.v, required this.session});

  final _GameView v;
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: v.phase == 'night' ? const Color(0xFF17172B) : panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: _content(context),
      ),
    );
  }

  Widget _headline(String text, {Color? color}) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: mist)),
  );

  List<Widget> _content(BuildContext context) {
    final role = v.myRole;
    switch (v.phase) {
      case 'lobby':
        return _lobby(context);
      case 'reveal':
        return [
          Icon(roleIcons[role], size: 42, color: role == 'mafia' ? blood : gold),
          const SizedBox(height: 6),
          _headline('أنت ${roleNames[role]}', color: role == 'mafia' ? blood : gold),
          _note(roleHints[role] ?? ''),
          if (role == 'mafia' && v.mafiaCount > 1) _note('شريكك في المافيا محدد بالأحمر تحت.'),
        ];
      case 'night':
        if (!v.iAmAlive) return [_headline('أنت ميت'), _note('تابع اللعبة بصمت.')];
        return switch (role) {
          'mafia' => [_headline('اختاروا ضحية الليلة', color: blood)],
          'doctor' => [_headline('اختار مين تحمي الليلة', color: good)],
          'detective' => [_headline('اختار مين تفحص الليلة', color: gold)],
          _ => [_headline('نام، المافيا صاحية'), _note('انتظر طلوع الصبح.')],
        };
      case 'dawn':
        final victim = v.playerById(v.json['victim'] as String?);
        return [
          if (victim == null)
            _headline('الحمد لله، ما مات أحد الليلة', color: good)
          else ...[
            _headline('قتلت المافيا ${_label(victim)}', color: blood),
            _note('كان دوره: ${roleNames[victim['role']]}'),
          ],
          ..._detectiveNews(),
        ];
      case 'day':
        return [
          _headline('ناقشوا وحددوا المشتبه فيه'),
          ..._detectiveNews(),
          if (v.iAmAlive) ...[
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: v.ready ? null : () => session.send({'a': 'ready'}),
              child: Text(v.ready ? 'تم، ننتظر الباقين' : 'جاهز للتصويت'),
            ),
          ] else
            _note('أنت ميت، وتقدر تتكلم مع الموتى بس.'),
        ];
      case 'voting':
        return [
          _headline(v.iAmAlive ? 'مين تطلّع من اللعبة؟' : 'الأحياء يصوتون الحين'),
          if (v.iAmAlive) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: v.votes[v.you] == ''
                  ? null
                  : () => session.send({'a': 'vote', 't': null}),
              child: Text(v.votes[v.you] == '' ? 'تخطيت التصويت' : 'تخطي التصويت'),
            ),
          ],
        ];
      case 'verdict':
        final out = v.playerById(v.json['out'] as String?);
        if (out == null) return [_headline('ما طلع أحد، ما اتفقتوا')];
        return [
          _headline('طلع ${_label(out)}', color: gold),
          _note('كان دوره: ${roleNames[out['role']]}'),
        ];
      default:
        final mafiaWon = v.winner == 'mafia';
        final iWon = mafiaWon == (role == 'mafia');
        return [
          Icon(mafiaWon ? Icons.theater_comedy : Icons.shield, size: 42, color: mafiaWon ? blood : good),
          const SizedBox(height: 6),
          _headline(mafiaWon ? 'فازت المافيا' : 'فاز المواطنون', color: mafiaWon ? blood : good),
          _note(iWon ? 'مبروك، فريقك فاز!' : 'خسر فريقك، حظ أوفر المرة الجاية.'),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('رجوع للقائمة'),
          ),
        ];
    }
  }

  /// The detective's newest result stays in view for the morning after.
  List<Widget> _detectiveNews() {
    if (v.myRole != 'detective' || v.checks.isEmpty || !v.iAmAlive) return const [];
    final last = v.checks.entries.last;
    final who = _label(v.playerById(last.key));
    return [_note(last.value == true ? 'نتيجة فحصك: $who مافيا!' : 'نتيجة فحصك: $who مو مافيا.')];
  }

  List<Widget> _lobby(BuildContext context) {
    final count = v.players.length;
    return [
      _headline('$count من ${v.max} لاعبين'),
      if (!v.quick) ...[
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('الكود: ', style: TextStyle(color: mist)),
            SelectableText(
              v.code,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 3, color: gold),
            ),
            IconButton(
              tooltip: 'نسخ الكود',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: v.code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('انتسخ الكود')),
                );
              },
            ),
          ],
        ),
        _note('عدد المافيا: ${v.mafiaCount}'),
      ],
      if (v.quick) _note('إذا ما اكتمل العدد وخلص الوقت، تكمّل البوتات الأماكن الفاضية.'),
      if (!v.quick && v.isHost) ...[
        const SizedBox(height: 10),
        FilledButton(
          onPressed: v.problem == null ? () => session.send({'a': 'start'}) : null,
          child: const Text('ابدأ اللعبة'),
        ),
        if (v.problem != null) _note(v.problem!),
      ] else if (!v.quick)
        _note(count < 5 ? 'لازم 5 لاعبين أقل شيء عشان تبدأ' : 'ننتظر منشئ الغرفة يبدأ'),
    ];
  }
}

class _PlayerGrid extends StatelessWidget {
  const _PlayerGrid({required this.v, required this.session});

  final _GameView v;
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final tally = <String, int>{};
    final ballots = v.phase == 'night' ? v.mafiaVotes : v.votes;
    for (final target in ballots.values) {
      if (target is String && target.isNotEmpty) {
        tally[target] = (tally[target] ?? 0) + 1;
      }
    }
    return GridView.extent(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      maxCrossAxisExtent: 170,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.75,
      children: [
        for (final p in v.players)
          _PlayerTile(
            player: p,
            isYou: p['id'] == v.you,
            selected: v.selected == p['id'],
            votes: tally[p['id']] ?? 0,
            check: v.checks[p['id']] as bool?,
            teammate: v.myRole == 'mafia' && p['role'] == 'mafia' && p['id'] != v.you,
            onTap: v.canTarget(p)
                ? () => session.send({'a': v.action, 't': p['id']})
                : null,
          ),
      ],
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.player,
    required this.isYou,
    required this.selected,
    required this.votes,
    required this.check,
    required this.teammate,
    required this.onTap,
  });

  final Map<String, dynamic> player;
  final bool isYou;
  final bool selected;
  final int votes;
  final bool? check;
  final bool teammate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final alive = player['alive'] == true;
    final online = player['online'] == true;
    final role = player['role'] as String?;
    final Color edge = selected
        ? gold
        : teammate || check == true
        ? blood
        : onTap != null
        ? mist
        : Colors.transparent;

    String? status;
    if (!alive && role != null) {
      status = 'ميت • ${roleNames[role]}';
    } else if (!online) {
      status = 'انقطع';
    } else if (check != null) {
      status = check! ? 'مافيا!' : 'مو مافيا';
    } else if (role != null && (isYou || teammate)) {
      status = isYou ? 'أنت • ${roleNames[role]}' : roleNames[role];
    } else if (isYou) {
      status = 'أنت';
    }

    return Opacity(
      opacity: alive ? 1 : 0.5,
      child: Material(
        color: selected ? panelHigh : panel,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: edge, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: isYou ? gold : panelHigh,
                  child: player['bot'] == true
                      ? Icon(Icons.smart_toy, size: 16, color: isYou ? ink : mist)
                      : Text(
                          '${player['seat']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isYou ? ink : Colors.white,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nameOf(player),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration: alive ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      if (status != null)
                        Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: check == true || teammate ? blood : mist,
                          ),
                        ),
                    ],
                  ),
                ),
                if (votes > 0)
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: blood,
                    child: Text(
                      '$votes',
                      style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({required this.v, required this.session});

  final _GameView v;
  final GameSession session;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _seen = 0;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    widget.session.send({'a': 'chat', 'text': text});
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.v.chat;
    if (lines.length != _seen) {
      _seen = lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    final channel = widget.v.channel;
    final hint = switch (channel) {
      'mafia' => 'كلام سري مع المافيا',
      'dead' => 'كلام مع الموتى بس',
      null => 'الكل نايم، ما تقدر تتكلم',
      _ => 'اكتب رسالة',
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: lines.isEmpty
                ? const Center(child: Text('ما فيه رسائل', style: TextStyle(color: mist)))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: lines.length,
                    itemBuilder: (_, i) => _line(lines[i]),
                  ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  enabled: channel != null,
                  maxLength: 200,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: hint,
                    counterText: '',
                    isDense: true,
                    fillColor: panelHigh,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'إرسال',
                onPressed: channel == null ? null : _send,
                icon: const Icon(Icons.send, color: gold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(Map<String, dynamic> l) {
    final color = switch (l['c']) {
      'mafia' => blood,
      'dead' => mist,
      _ => gold,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: widget.v.playerById(l['id'] as String?)?['bot'] == true
                  ? '${l['n']}: '
                  : '${l['n']} ${l['s']}: ',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            TextSpan(text: '${l['t']}'),
          ],
        ),
      ),
    );
  }
}
