import 'package:flutter_tts/flutter_tts.dart';

FlutterTts? _tts;

/// Reads [text] aloud in Arabic. A device without an Arabic voice simply stays quiet:
/// everything spoken is also on the screen, so this must never get in the way of playing.
Future<void> speakArabic(String text) async {
  try {
    final tts = _tts ??= FlutterTts();
    await tts.setLanguage('ar-SA');
    await tts.stop();
    await tts.speak(text);
  } catch (_) {}
}
