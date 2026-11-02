import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quick_match_screen.dart';
import 'servers_screen.dart';
import 'setup_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController();
  bool _missingName = false;

  @override
  void initState() {
    super.initState();
    _loadName();
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
              ],
            ),
          ),
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
