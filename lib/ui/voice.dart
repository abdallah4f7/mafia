import 'package:audioplayers/audioplayers.dart';

AudioPlayer? _player;

/// Plays a recording from assets/voice, made from tool/voice_lines.txt. Everything
/// spoken is also on the screen, so a failure here must never get in the way of playing.
Future<void> playVoice(String line) async {
  try {
    final player = _player ??= AudioPlayer();
    await player.stop();
    await player.play(AssetSource('voice/$line.mp3'));
  } catch (_) {}
}
