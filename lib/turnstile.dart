/// The Cloudflare Turnstile check the website puts on signup and the password
/// reset mail, for the app: the website's own /turnstile-widget page in a
/// webview. The page is served from openpak.org, so the widget needs no extra
/// hostname, and it hands its answer back over the `OpenPakTurnstile`
/// JavaScript channel as `{"kind": "token" | "error" | "expired", "token"}`.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'l10n.dart';
import 'widgets.dart';

/// Runs the check and returns the token, or null when there is none to send
/// (the person cancelled, or the check moved to the browser). [websitePage] is
/// the website's own form, the fallback where no webview exists.
typedef TurnstileSolver = Future<String?> Function(
  BuildContext context, {
  required Uri widget,
  required Uri websitePage,
  String? language,
});

/// The default [TurnstileSolver]: a dialog around the widget page. A platform
/// without a webview implementation opens [websitePage] in the browser instead,
/// so the person finishes there.
Future<String?> turnstileInWebView(
  BuildContext context, {
  required Uri widget,
  required Uri websitePage,
  String? language,
}) async {
  if (WebViewPlatform.instance == null) {
    final l = context.l10n;
    final opened = await launchUrl(websitePage, mode: LaunchMode.externalApplication);
    if (context.mounted) showToast(context, opened ? l.turnstileInBrowser : l.commonNoConnection);
    return null;
  }
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TurnstileDialog(url: widget, language: language),
  );
}

class TurnstileDialog extends StatefulWidget {
  const TurnstileDialog({super.key, required this.url, this.language});
  final Uri url;
  final String? language;

  @override
  State<TurnstileDialog> createState() => _TurnstileDialogState();
}

class _TurnstileDialogState extends State<TurnstileDialog> {
  late final WebViewController _web;
  String? _error;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('OpenPakTurnstile', onMessageReceived: (m) => _answer(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        // The widget page and Cloudflare's frame only: a link out of the
        // widget (Cloudflare's privacy notice) goes to the browser.
        onNavigationRequest: (req) {
          final host = Uri.tryParse(req.url)?.host;
          if (!req.isMainFrame || host == widget.url.host) return NavigationDecision.navigate;
          launchUrl(Uri.parse(req.url), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) _fail(loading: true);
        },
      ));
    _load();
  }

  void _load() {
    setState(() => _error = null);
    _web.loadRequest(widget.url, headers: {
      if (widget.language != null) 'Accept-Language': widget.language!,
    });
  }

  void _fail({bool loading = false}) {
    if (!mounted) return;
    final l = context.l10n;
    setState(() => _error = loading ? l.turnstileLoadFailed : l.errorTurnstileFailed);
  }

  void _answer(String raw) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['kind']) {
      case 'token':
        final token = m['token'] as String? ?? '';
        if (token.isNotEmpty && mounted) Navigator.pop(context, token);
      case 'expired':
        _load(); // A token is good for minutes; an expired one is simply asked again.
      case 'error':
        _fail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.turnstileTitle),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.turnstileHelp),
            const SizedBox(height: 12),
            SizedBox(height: 80, child: WebViewWidget(controller: _web)),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        if (_error != null) FilledButton(onPressed: _load, child: Text(l.turnstileRetry)),
      ],
    );
  }
}
