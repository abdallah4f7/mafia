import 'package:flutter/material.dart';

import '../game/engine.dart';
import '../game/pass_game.dart';
import 'game_screen.dart';
import 'theme.dart';
import 'voice.dart';

const _closeEyes = 'حطوا الجوال بالنص وغمضوا عيونكم';

const _nightCalls = {
  Role.mafia: 'المافيا ياخذ الجوال ويحدد من يذبح',
  Role.doctor: 'الدكتور ياخذ الجوال ويحدد من يحمي',
  Role.detective: 'الشايب ياخذ الجوال ويحدد من يختار',
};

class PassGameScreen extends StatefulWidget {
  const PassGameScreen({super.key, required this.pass, this.speak = speakArabic});

  final PassGame pass;
  final Future<void> Function(String text) speak;

  @override
  State<PassGameScreen> createState() => _PassGameScreenState();
}

class _PassGameScreenState extends State<PassGameScreen> {
  String? _pick;

  PassGame get _pass => widget.pass;
  GameEngine get _game => _pass.game;

  @override
  void initState() {
    super.initState();
    _announce();
  }

  void _act(VoidCallback change) {
    setState(() {
      change();
      _pick = null;
    });
    _announce();
  }

  /// Says what the room needs to hear, including the people with their eyes closed.
  void _announce() {
    final holder = _pass.holder;
    if (holder != null) {
      if (_pass.opened) return;
      widget.speak(
        _game.phase == Phase.night
            ? '$_closeEyes. ${_nightCalls[holder.role]}'
            : 'عطوا الجوال لـ ${_pass.label(holder)}',
      );
    } else if (_game.phase == Phase.dawn) {
      final victim = _game.player(_game.nightVictim);
      widget.speak(
        victim == null
            ? 'افتحوا عيونكم. الحمد لله، ما مات أحد الليلة'
            : 'افتحوا عيونكم. قتلت المافيا ${_pass.label(victim)}',
      );
    }
  }

  Future<void> _confirmLeave() async {
    if (_game.phase != Phase.over) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('تطلعون من اللعبة؟'),
          content: const Text('بتضيع اللعبة الحالية.'),
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

  String get _title => switch (_game.phase) {
    Phase.reveal => 'توزيع الأدوار',
    Phase.night => 'الليلة ${_game.round}',
    Phase.dawn => 'طلع الصبح',
    Phase.day => 'نقاش النهار',
    Phase.voting => 'التصويت',
    Phase.verdict => 'النتيجة',
    _ => 'انتهت اللعبة',
  };

  @override
  Widget build(BuildContext context) {
    final holder = _pass.holder;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _confirmLeave),
          title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: SafeArea(
          child: Narrow(
            child: holder == null
                ? _table()
                : _pass.opened
                ? _turn(holder)
                : _handoff(holder),
          ),
        ),
      ),
    );
  }

  /// The content scrolls and the buttons stay in reach, even with 15 names to pick from.
  Widget _page(List<Widget> content, List<Widget> actions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: content,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: actions,
          ),
        ),
      ],
    );
  }

  Widget _headline(String text, {Color? color, double size = 24}) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: color),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: mist, fontSize: 16),
    ),
  );

  Widget _continue(VoidCallback change, {String label = 'متابعة'}) =>
      FilledButton(onPressed: () => _act(change), child: Text(label));

  Widget _handoff(EnginePlayer holder) {
    if (_game.phase == Phase.night) {
      return _page(
        [
          const SizedBox(height: 60),
          const Icon(Icons.bedtime, size: 72, color: gold),
          const SizedBox(height: 16),
          _headline(_closeEyes, size: 22),
          const SizedBox(height: 16),
          _headline(_nightCalls[holder.role]!, color: gold, size: 26),
        ],
        [_continue(_pass.open)],
      );
    }
    return _page(
      [
        const SizedBox(height: 60),
        const Icon(Icons.phone_android, size: 72, color: gold),
        const SizedBox(height: 16),
        _headline('عطوا الجوال لـ', size: 20),
        const SizedBox(height: 8),
        _headline(_pass.label(holder), color: gold, size: 38),
        _note('الشاشة الجاية سرية، اضغط متابعة إذا صار الجوال معك.'),
      ],
      [_continue(_pass.open)],
    );
  }

  Widget _turn(EnginePlayer me) {
    if (_game.phase == Phase.reveal) return _reveal(me);
    if (_game.phase == Phase.voting) return _vote(me);
    final checked = _pass.checked;
    if (checked != null) {
      final isMafia = checked.role == Role.mafia;
      return _page(
        [
          const SizedBox(height: 60),
          Icon(Icons.search, size: 64, color: isMafia ? blood : good),
          const SizedBox(height: 12),
          _headline(
            isMafia ? '${_pass.label(checked)} مافيا!' : '${_pass.label(checked)} مو مافيا',
            color: isMafia ? blood : good,
          ),
          _note('خلها سر لين تقرر تقولها.'),
        ],
        [_continue(_pass.finishTurn)],
      );
    }
    return me.role == Role.mafia
        ? _nightPick('اختاروا من تذبحون الليلة', blood, const [])
        : me.role == Role.doctor
        ? _nightPick('اختار من تحمي الليلة', good, const [])
        : _nightPick('اختار من تبغى تعرف عنه', gold, _pastChecks());
  }

  Widget _reveal(EnginePlayer me) {
    final role = me.role.name;
    final color = me.role == Role.mafia ? blood : gold;
    final partners = _game.players.where((p) => p.role == Role.mafia && p.id != me.id);
    return _page(
      [
        const SizedBox(height: 40),
        Icon(roleIcons[role], size: 72, color: color),
        const SizedBox(height: 12),
        _headline(_pass.label(me), size: 20),
        const SizedBox(height: 4),
        _headline('أنت ${roleNames[role]}', color: color, size: 34),
        _note(roleHints[role] ?? ''),
        if (me.role == Role.mafia && partners.isNotEmpty)
          _note('معك في المافيا: ${partners.map(_pass.label).join('، ')}'),
      ],
      [_continue(_pass.finishTurn)],
    );
  }

  List<Widget> _pastChecks() => [
    for (final entry in _game.detectiveResults.entries)
      _note(
        '${_pass.label(_game.player(entry.key)!)}: ${entry.value ? 'مافيا' : 'مو مافيا'}',
      ),
  ];

  Widget _nightPick(String title, Color color, List<Widget> notes) {
    return _page(
      [
        _headline(title, color: color, size: 22),
        ...notes,
        const SizedBox(height: 16),
        ..._targets(),
      ],
      [
        FilledButton(
          onPressed: _pick == null ? null : () => _act(() => _pass.choose(_pick)),
          child: const Text('تأكيد'),
        ),
      ],
    );
  }

  Widget _vote(EnginePlayer me) {
    return _page(
      [
        _headline(_pass.label(me), size: 18),
        const SizedBox(height: 4),
        _headline('مين تطلّع من اللعبة؟', size: 22),
        _note('صوتك سري.'),
        const SizedBox(height: 16),
        ..._targets(),
      ],
      [
        FilledButton(
          onPressed: _pick == null ? null : () => _act(() => _pass.choose(_pick)),
          child: const Text('تأكيد'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _act(() => _pass.choose(null)),
          child: const Text('تخطي التصويت'),
        ),
      ],
    );
  }

  List<Widget> _targets() => [
    for (final p in _pass.targets)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: _pick == p.id ? panelHigh : panel,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: _pick == p.id ? gold : Colors.transparent, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: () => setState(() => _pick = p.id),
            title: Text(_pass.label(p), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
  ];

  /// The phone is on the table here, so everything on screen is for everyone.
  Widget _table() {
    switch (_game.phase) {
      case Phase.dawn:
        final victim = _game.player(_game.nightVictim);
        return _page(
          [
            const SizedBox(height: 40),
            if (victim == null)
              _headline('الحمد لله، ما مات أحد الليلة', color: good)
            else ...[
              _headline('قتلت المافيا ${_pass.label(victim)}', color: blood),
              _note('الدور: ${roleNames[victim.role.name]}'),
            ],
          ],
          [_continue(_pass.next)],
        );
      case Phase.day:
        return _page(
          [
            _headline('ناقشوا وحددوا المشتبه فيه', size: 22),
            const SizedBox(height: 16),
            ..._roster(),
          ],
          [_continue(_pass.next, label: 'ابدأوا التصويت')],
        );
      case Phase.verdict:
        final out = _game.player(_game.votedOut);
        return _page(
          [
            const SizedBox(height: 40),
            if (out == null)
              _headline('ما طلع أحد، ما اتفقتوا')
            else ...[
              _headline('طلع ${_pass.label(out)}', color: gold),
              _note('الدور: ${roleNames[out.role.name]}'),
            ],
          ],
          [_continue(_pass.next)],
        );
      default:
        final mafiaWon = _game.winner == Role.mafia;
        final color = mafiaWon ? blood : good;
        return _page(
          [
            Icon(mafiaWon ? Icons.theater_comedy : Icons.shield, size: 56, color: color),
            const SizedBox(height: 8),
            _headline(mafiaWon ? 'فازت المافيا' : 'فاز المواطنون', color: color),
            const SizedBox(height: 16),
            ..._roster(),
          ],
          [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('لعبة جديدة'),
            ),
          ],
        );
    }
  }

  /// Roles stay hidden until a player dies or the game ends.
  List<Widget> _roster() {
    final over = _game.phase == Phase.over;
    return [
      for (final p in _game.players)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Opacity(
            opacity: p.alive ? 1 : 0.5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _pass.label(p),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: p.alive ? null : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                  if (over || !p.alive)
                    Text(
                      roleNames[p.role.name]!,
                      style: TextStyle(color: p.role == Role.mafia ? blood : mist),
                    ),
                ],
              ),
            ),
          ),
        ),
    ];
  }
}
