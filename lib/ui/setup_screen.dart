import 'package:flutter/material.dart';

import '../game/engine.dart';
import '../game/pass_game.dart';
import '../net/online.dart';
import 'game_screen.dart';
import 'pass_game_screen.dart';
import 'theme.dart';

class BotSetupScreen extends StatefulWidget {
  const BotSetupScreen({super.key, required this.name});

  final String name;

  @override
  State<BotSetupScreen> createState() => _BotSetupScreenState();
}

class _BotSetupScreenState extends State<BotSetupScreen> {
  int _bots = 6;
  int _mafia = 1;

  @override
  Widget build(BuildContext context) {
    final total = _bots + 1;
    return _SetupScaffold(
      title: 'اللعب مع بوتات',
      children: [
        _CountSlider(
          label: 'عدد البوتات',
          note: 'المجموع معك: $total لاعبين',
          value: _bots,
          min: minPlayers - 1,
          max: maxPlayersLimit - 1,
          onChanged: (v) => setState(() {
            _bots = v;
            if (_mafia > maxMafiaFor(v + 1)) _mafia = maxMafiaFor(v + 1);
          }),
        ),
        _MafiaPicker(
          total: total,
          value: _mafia,
          onChanged: (v) => setState(() => _mafia = v),
        ),
      ],
      action: 'ابدأ اللعب',
      onAction: () {
        final session = startBotGame(
          name: widget.name,
          bots: _bots,
          mafiaCount: _mafia,
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => GameScreen(session: session)),
        );
      },
    );
  }
}

class CreateGameScreen extends StatefulWidget {
  const CreateGameScreen({super.key, required this.name});

  final String name;

  @override
  State<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends State<CreateGameScreen> {
  int _players = 8;
  int _mafia = 2;

  @override
  Widget build(BuildContext context) {
    return _SetupScaffold(
      title: 'إنشاء لعبة',
      children: [
        _CountSlider(
          label: 'عدد اللاعبين',
          note: 'تقدر تبدأ من $minPlayers لاعبين، حتى لو ما امتلأت الغرفة',
          value: _players,
          min: minPlayers,
          max: maxPlayersLimit,
          onChanged: (v) => setState(() {
            _players = v;
            if (_mafia > maxMafiaFor(v)) _mafia = maxMafiaFor(v);
          }),
        ),
        _MafiaPicker(
          total: _players,
          value: _mafia,
          onChanged: (v) => setState(() => _mafia = v),
        ),
      ],
      action: 'أنشئ الغرفة',
      onAction: () {
        final room = createRoom(
          name: widget.name,
          maxPlayers: _players,
          mafiaCount: _mafia,
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => GameScreen(session: room)),
        );
      },
    );
  }
}

class PassSetupScreen extends StatefulWidget {
  const PassSetupScreen({super.key});

  @override
  State<PassSetupScreen> createState() => _PassSetupScreenState();
}

class _PassSetupScreenState extends State<PassSetupScreen> {
  final _name = TextEditingController();
  final _focus = FocusNode();
  final _names = <String>[];
  int _mafia = 1;

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _typing => _name.text.trim().isNotEmpty;

  void _add() {
    if (!_typing || _names.length >= maxPlayersLimit) return;
    setState(() {
      _names.add(_name.text.trim());
      _name.clear();
    });
  }

  void _remove(int index) {
    setState(() {
      _names.removeAt(index);
      final limit = maxMafiaFor(_pickerTotal);
      if (_mafia > limit) _mafia = limit;
    });
  }

  /// With fewer names than the game needs, the choice is limited as if it had the minimum.
  int get _pickerTotal => _names.length < minPlayers ? minPlayers : _names.length;

  void _start() {
    // A name still in the box counts, so nobody gets left out by not pressing add.
    _add();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PassGameScreen(pass: PassGame(List.of(_names), _mafia)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final full = _names.length >= maxPlayersLimit;
    final count = _names.length + (_typing ? 1 : 0);
    return _SetupScaffold(
      title: 'لعب على جوال واحد',
      children: [
        TextField(
          controller: _name,
          focusNode: _focus,
          enabled: !full,
          maxLength: 20,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            _add();
            _focus.requestFocus();
          },
          decoration: InputDecoration(
            labelText: 'اسم اللاعب',
            hintText: 'اكتب الاسم واضغط إضافة',
            prefixIcon: const Icon(Icons.person),
            counterText: '',
            suffixIcon: IconButton(
              tooltip: 'إضافة',
              icon: const Icon(Icons.add_circle, color: gold),
              onPressed: _typing && !full ? _add : null,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _names.length; i++)
              InputChip(
                label: Text(_names[i]),
                onDeleted: () => _remove(i),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          count < minPlayers
              ? 'سجلتوا ${_names.length}، ولازم $minPlayers لاعبين أقل شيء'
              : 'سجلتوا ${_names.length} من $maxPlayersLimit لاعب',
          style: const TextStyle(color: mist),
        ),
        const SizedBox(height: 24),
        _MafiaPicker(
          total: _pickerTotal,
          value: _mafia,
          onChanged: (v) => setState(() => _mafia = v),
        ),
      ],
      action: 'ابدأ اللعب',
      onAction: count >= minPlayers ? _start : null,
    );
  }
}

class _SetupScaffold extends StatelessWidget {
  const _SetupScaffold({
    required this.title,
    required this.children,
    required this.action,
    required this.onAction,
  });

  final String title;
  final List<Widget> children;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Narrow(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...children,
                const SizedBox(height: 12),
                FilledButton(onPressed: onAction, child: Text(action)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountSlider extends StatelessWidget {
  const _CountSlider({
    required this.label,
    required this.note,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String note;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              Text(
                '$value',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: gold),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
          Text(note, style: const TextStyle(color: mist)),
        ],
      ),
    );
  }
}

class _MafiaPicker extends StatelessWidget {
  const _MafiaPicker({
    required this.total,
    required this.value,
    required this.onChanged,
  });

  final int total;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final limit = maxMafiaFor(total);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('عدد المافيا', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var n = 1; n <= maxMafia; n++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: ChoiceChip(
                    label: Text('$n', style: const TextStyle(fontSize: 18)),
                    selected: value == n,
                    onSelected: n <= limit ? (_) => onChanged(n) : null,
                  ),
                ),
            ],
          ),
          if (limit < maxMafia)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${limit + 1} مافيا يحتاجون ${(limit + 1) * 2 + 1} لاعبين أقل شيء',
                style: const TextStyle(color: mist),
              ),
            ),
        ],
      ),
    );
  }
}
