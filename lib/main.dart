import 'package:flutter/material.dart';

import 'api.dart';
import 'home_page.dart';
import 'session.dart';
import 'sign_in_page.dart';

/// The server this build talks to. Override for a local stack with
/// `--dart-define=OPENPAK_BASE_URL=http://10.0.2.2:20010`.
const baseUrl = String.fromEnvironment(
  'OPENPAK_BASE_URL',
  defaultValue: 'https://openpak.org',
);

void main() => runApp(const OpenPakApp());

class OpenPakApp extends StatefulWidget {
  const OpenPakApp({super.key});
  @override
  State<OpenPakApp> createState() => _OpenPakAppState();
}

class _OpenPakAppState extends State<OpenPakApp> {
  final _session = Session();
  final _api = OpenPakApi(baseUrl: baseUrl);
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// A stored token means signed in until the server says otherwise; the first
  /// 401 from any screen signs out. Nothing is validated up front, because
  /// that would put a network round trip in front of the first frame.
  Future<void> _restore() async {
    _api.token = await _session.read();
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _onSignedIn(String token) async {
    await _session.write(token);
    setState(() {});
  }

  Future<void> _onSignedOut() async {
    await _api.signOut();
    await _session.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenPak',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFE60012),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFFE60012),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: _restoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _api.token == null
          ? SignInPage(api: _api, onSignedIn: _onSignedIn)
          : HomePage(api: _api, onSignedOut: _onSignedOut),
    );
  }
}
