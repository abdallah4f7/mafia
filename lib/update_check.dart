import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Keep these two equal to `version` in pubspec.yaml. A test fails if they drift apart.
const appVersion = '1.0.3';
const appBuild = 4;

const _versionUrl = 'https://abdallah4f7.github.io/mafia/version.json';
const _apkUrl = 'https://github.com/abdallah4f7/mafia/releases/latest/download/Mafia.apk';
const _webUrl = 'https://abdallah4f7.github.io/mafia/app/';

class AppUpdate {
  const AppUpdate(this.version, this.build);

  final String version;
  final int build;
}

/// The newer version the download page announces, or null if this one is current.
/// A failed check counts as no update: it must never get in the way of playing.
Future<AppUpdate?> checkForUpdate({http.Client? client, int current = appBuild}) async {
  final net = client ?? http.Client();
  try {
    // The time in the query gets past any cached copy of the file.
    final url = Uri.parse('$_versionUrl?t=${DateTime.now().millisecondsSinceEpoch}');
    final response = await net.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final build = json['build'] as int;
    return build > current ? AppUpdate(json['version'] as String, build) : null;
  } catch (_) {
    return null;
  } finally {
    if (client == null) net.close();
  }
}

/// The web and Windows versions just reload onto the new web build. The Android app
/// sends the player to download the new APK, which installs over this one.
Future<void> installUpdate(AppUpdate update) async {
  if (kIsWeb) {
    await launchUrl(Uri.parse('$_webUrl?v=${update.build}'), webOnlyWindowName: '_self');
  } else {
    await launchUrl(Uri.parse(_apkUrl), mode: LaunchMode.externalApplication);
  }
}
