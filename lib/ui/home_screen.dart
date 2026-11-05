import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../update_check.dart';
import 'quick_match_screen.dart';
import 'servers_screen.dart';
import 'setup_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.findUpdate = checkForUpdate});

  final Future<AppUpdate?> Function() findUpdate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController();
  bool _missingName = false;
  AppUpdate? _update;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _loadName();
    _lookForUpdate();
    // The game can stay open for a long time, so keep checking. The notice only shows
    // on this screen, so it never interrupts a game in progress.
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) => _lookForUpdate());
  }

  Future<void> _lookForUpdate() async {
    final update = await widget.findUpdate();
    if (update != null && mounted) setState(() => _update = update);
  }

  Future<void> _loadName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('name');
      if (saved != null && mounted && _name.text.isEmpty) _name.text = saved;
    } catch (_) {
      // Remembering the name is only a convenience.
    }
  }

  Future<void> _saveName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', name);
    } catch (_) {}
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _open(Widget Function(String name) screen) {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _missingName = true);
      return;
    }
    _saveName(name);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen(name)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Narrow(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const Icon(Icons.theater_comedy, size: 64, color: blood),
                const SizedBox(height: 8),
                const Text(
                  'مافيا',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
                ),
                const Text(
                  'مين فيكم يكذب؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mist, fontSize: 16),
                ),
                const SizedBox(height: 28),
                if (_update != null) _UpdateNotice(update: _update!),
                TextField(
                  controller: _name,
                  maxLength: 20,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (_missingName) setState(() => _missingName = false);
                  },
                  decoration: InputDecoration(
                    labelText: 'اسمك',
                    hintText: 'اكتب اسمك عشان تدخل',
                    prefixIcon: const Icon(Icons.person),
                    counterText: '',
                    errorText: _missingName ? 'لازم تكتب اسمك أول' : null,
                  ),
                ),
                const SizedBox(height: 20),
                _Option(
                  icon: Icons.smart_toy,
                  title: 'اللعب مع بوتات',
                  subtitle: 'أنت تحدد عدد البوتات وعدد المافيا',
                  onTap: () => _open((n) => BotSetupScreen(name: n)),
                ),
                _Option(
                  icon: Icons.shuffle,
                  title: 'دخول عشوائي',
                  subtitle: 'تدخل مع ناس عشوائيين',
                  onTap: () => _open((n) => QuickMatchScreen(name: n)),
                ),
                _Option(
                  icon: Icons.add_circle,
                  title: 'إنشاء لعبة',
                  subtitle: 'تسوي غرفتك وتحدد العدد والمافيا',
                  onTap: () => _open((n) => CreateGameScreen(name: n)),
                ),
                _Option(
                  icon: Icons.dns,
                  title: 'دخول السيرفرات',
                  subtitle: 'دور السيرفر اللي تبغاه أو حط الكود',
                  onTap: () => _open((n) => ServersScreen(name: n)),
                ),
                // Everyone types their own name on the next screen, so this one doesn't ask.
                _Option(
                  icon: Icons.phone_android,
                  title: 'لعب على جوال واحد',
                  subtitle: 'تسجلون أسماءكم والجوال يدور بينكم',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PassSetupScreen()),
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

class _UpdateNotice extends StatefulWidget {
  const _UpdateNotice({required this.update});

  final AppUpdate update;

  @override
  State<_UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<_UpdateNotice> {
  int? _percent;

  Future<void> _install() async {
    setState(() => _percent = 0);
    await installUpdate(
      widget.update,
      onProgress: (percent) {
        if (mounted) setState(() => _percent = percent);
      },
    );
    if (mounted) setState(() => _percent = null);
  }

  @override
  Widget build(BuildContext context) {
    final percent = _percent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: panel,
          border: Border.all(color: gold),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.system_update, color: gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                percent == null
                    ? 'فيه تحديث جديد (${widget.update.version})'
                    : 'جاري التنزيل $percent٪',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (percent == null)
              TextButton(
                onPressed: _install,
                child: const Text('حدّث الآن', style: TextStyle(color: gold)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Icon(icon, color: gold, size: 30),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          subtitle: Text(subtitle, style: const TextStyle(color: mist)),
          trailing: const Icon(Icons.chevron_left, color: mist),
        ),
      ),
    );
  }
}
