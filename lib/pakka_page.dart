import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

const _metaTermsUrl = 'https://dev.meta.ai/legal/terms-of-service';
const _privacyUrl = 'https://openpak.org/privacy#pakka';

// The app has no ticket flow of its own; the website's Help page is it.
const _helpUrl = 'https://openpak.org/help';

Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Pakka's official mark, round.
class PakkaAvatar extends StatelessWidget {
  const PakkaAvatar({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: Image.asset('assets/pakka.png', width: size, height: size, fit: BoxFit.cover, semanticLabel: 'Pakka'),
  );
}

/// One line of a chat: who said it and what.
class _Line {
  _Line(this.fromPakka, this.text);
  final bool fromPakka;
  String text;
}

/// Chat with Pakka, the assistant. Reached from Account only when the server
/// says the account may use it; opened directly on any other account it says
/// so and offers the support ticket instead. If the state cannot be fetched
/// nothing here pretends Pakka works.
class PakkaPage extends StatefulWidget {
  const PakkaPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<PakkaPage> createState() => _PakkaPageState();
}

class _PakkaPageState extends State<PakkaPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late Future<PakkaState> _state;
  bool _consent = false;
  String? _convId;
  final _lines = <_Line>[];
  bool _busy = false; // a reply is on its way
  bool _tool = false; // Pakka is looking something up
  String? _failed; // the text of a message that did not go through
  String? _failure;
  StreamSubscription<PakkaEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _state = widget.api.pakkaState().then((s) {
      _consent = s.consent;
      return s;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  Future<void> _accept() async {
    try {
      await widget.api.pakkaAccept();
      if (!mounted) return;
      setState(() => _consent = true);
      showToast(context, context.l10n.pakkaNoticeAccepted);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    }
  }

  Future<void> _withdraw() async {
    try {
      await widget.api.pakkaWithdraw();
      if (!mounted) return;
      unawaited(_sub?.cancel());
      setState(() {
        _consent = false;
        _busy = false;
        _tool = false;
      });
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    }
  }

  void _showNotice() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: SingleChildScrollView(child: _NoticeText(l: ctx.l10n)),
      actions: [
        if (_consent)
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _withdraw();
            },
            child: Text(ctx.l10n.pakkaNoticeWithdraw, style: TextStyle(color: tokensOf(ctx).bad)),
          ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.pakkaNoticeClose)),
      ],
    ),
  );

  void _newChat() {
    _sub?.cancel();
    setState(() {
      _convId = null;
      _lines.clear();
      _busy = false;
      _tool = false;
      _failed = null;
      _failure = null;
    });
  }

  Future<void> _openChat(PakkaConversation c) async {
    Navigator.of(context).pop(); // the drawer
    unawaited(_sub?.cancel());
    try {
      final msgs = await widget.api.pakkaMessages(c.id);
      if (!mounted) return;
      setState(() {
        _convId = c.id;
        _lines
          ..clear()
          ..addAll(msgs.map((m) => _Line(m.fromPakka, m.text)));
        _busy = false;
        _tool = false;
        _failed = null;
        _failure = null;
      });
      _toBottom();
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    }
  }

  Future<void> _send([String? again]) async {
    final text = (again ?? _input.text).trim();
    if (text.isEmpty || _busy || !_consent) return;
    final l = context.l10n;
    setState(() {
      _busy = true;
      _tool = false;
      _failed = null;
      _failure = null;
      _lines
        ..add(_Line(false, text))
        ..add(_Line(true, ''));
    });
    _input.clear();
    _toBottom();
    void fail(String why, {bool consentLost = false}) {
      if (!mounted) return;
      setState(() {
        // The unsent message goes back to the field, and the half answer goes.
        _lines.removeRange(_lines.length - 2, _lines.length);
        _busy = false;
        _tool = false;
        _failed = text;
        _failure = why;
        if (consentLost) _consent = false;
        _input.text = text;
      });
    }

    try {
      _convId ??= (await widget.api.pakkaCreate()).id;
      final id = _convId!;
      final done = Completer<void>();
      _sub = widget.api.pakkaSend(id, text).listen(
        (e) {
          if (!mounted) return;
          switch (e.kind) {
            case 'tool':
              setState(() => _tool = true);
            case 'delta':
              setState(() {
                _tool = false;
                _lines.last.text += e.text;
              });
              _toBottom();
            case 'error':
              _sub?.cancel();
              fail(apiErrorText(l, ApiException(502, '', code: e.text)));
              if (!done.isCompleted) done.complete();
            case 'done':
              setState(() {
                _busy = false;
                _tool = false;
              });
          }
        },
        onError: (Object e) {
          fail(e is ApiException ? apiErrorText(l, e) : l.pakkaError, consentLost: e is ApiException && e.code == 'consent_required');
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          // A stream that ends without `done` or an error was cut off.
          if (mounted && _busy) fail(l.pakkaError);
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future;
    } on ApiException catch (e) {
      fail(apiErrorText(l, e), consentLost: e.code == 'consent_required');
    } catch (_) {
      fail(l.pakkaError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return FutureBuilder<PakkaState>(
      future: _state,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(title: Text(l.pakkaTitle)), body: const Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(title: Text(l.pakkaTitle)), body: LoadFailure(snap.error));
        }
        if (!snap.data!.visible) return _Unavailable(l: l);
        return _chat(context, snap.data!);
      },
    );
  }

  Widget _chat(BuildContext context, PakkaState s) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [const PakkaAvatar(size: 28), const SizedBox(width: 10), Text(l.pakkaTitle)],
        ),
        actions: [
          IconButton(tooltip: l.pakkaNoticeView, onPressed: _showNotice, icon: const Icon(Icons.info_outline)),
          IconButton(
            tooltip: l.pakkaHistory,
            onPressed: () => _scaffold.currentState?.openEndDrawer(),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      endDrawer: _HistoryDrawer(api: widget.api, current: _convId, onOpen: _openChat, onNew: () {
        Navigator.of(context).pop();
        _newChat();
      }, onDeleted: (id) {
        if (id == _convId) _newChat();
      }),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!_consent)
                      Panel(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _NoticeText(l: l),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: _accept, child: Text(l.pakkaNoticeAccept)),
                            ],
                          ),
                        ),
                      )
                    else if (_lines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            const PakkaAvatar(size: 64),
                            const SizedBox(height: 12),
                            Text(l.pakkaWelcome, textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
                          ],
                        ),
                      ),
                    for (final (i, m) in _lines.indexed)
                      _Bubble(
                        line: m,
                        status: _busy && i == _lines.length - 1
                            ? (_tool ? l.pakkaLooking : (m.text.isEmpty ? l.pakkaTyping : null))
                            : null,
                      ),
                    if (_failure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Notice(_failure!),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(onPressed: () => _send(_failed), child: Text(l.pakkaRetry)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: _consent,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: s.maxChars,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(hintText: l.pakkaPlaceholder),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(
                      tooltip: l.pakkaSend,
                      onPressed: _consent && !_busy ? () => _send() : null,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
              SafeArea(top: false, child: _Footer(l: l)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two fixed lines under every Pakka screen, and the way to a person.
class _Footer extends StatelessWidget {
  const _Footer({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${l.pakkaAi} ${l.pakkaRetention}',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted, fontSize: 12),
          ),
          TextButton(onPressed: () => _open(_helpUrl), child: Text(l.pakkaTicket, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.line, this.status});
  final _Line line;

  /// "Pakka is typing" / "Looking that up", under (or instead of) the text.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final mine = !line.fromPakka;
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(maxWidth: (MediaQuery.of(context).size.width * 0.75).clamp(0, 520)),
      decoration: BoxDecoration(color: mine ? t.accentWeak : t.paper2, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (line.text.isNotEmpty) SelectableText(line.text),
          if (status != null)
            Text(status!, style: TextStyle(color: t.muted, fontStyle: FontStyle.italic)),
        ],
      ),
    );
    if (mine) return Align(alignment: Alignment.centerRight, child: bubble);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Padding(padding: EdgeInsets.only(right: 8, bottom: 4), child: PakkaAvatar(size: 28)),
        Flexible(child: bubble),
      ],
    );
  }
}

/// Title, body and the two links of the data-use notice.
class _NoticeText extends StatelessWidget {
  const _NoticeText({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(l.pakkaNoticeTitle, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(l.pakkaNoticeBody),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          TextButton(onPressed: () => _open(_metaTermsUrl), child: Text(l.pakkaNoticeMeta)),
          TextButton(onPressed: () => _open(_privacyUrl), child: Text(l.pakkaNoticePrivacy)),
        ],
      ),
    ],
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(l.pakkaTitle)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PakkaAvatar(size: 64),
            const SizedBox(height: 16),
            Text(l.pakkaOffTitle, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(l.pakkaOffBody, textAlign: TextAlign.center, style: TextStyle(color: tokensOf(context).muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _open(_helpUrl), child: Text(l.pakkaTicket)),
          ],
        ),
      ),
    ),
  );
}

/// Past chats, newest first, with new chat and delete.
class _HistoryDrawer extends StatefulWidget {
  const _HistoryDrawer({
    required this.api,
    required this.current,
    required this.onOpen,
    required this.onNew,
    required this.onDeleted,
  });
  final OpenPakApi api;
  final String? current;
  final void Function(PakkaConversation) onOpen;
  final VoidCallback onNew;
  final void Function(String id) onDeleted;

  @override
  State<_HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends State<_HistoryDrawer> {
  late Future<List<PakkaConversation>> _list = widget.api.pakkaConversations();

  Future<void> _delete(PakkaConversation c) async {
    final l = context.l10n;
    if (!await confirm(context, l.pakkaDeleteConfirm, action: l.pakkaDelete)) return;
    try {
      await widget.api.pakkaDelete(c.id);
      widget.onDeleted(c.id);
      if (!mounted) return;
      setState(() {
        _list = widget.api.pakkaConversations();
      });
      showToast(context, l.pakkaDeleted);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = tokensOf(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.pakkaHistory, style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(leading: const Icon(Icons.add), title: Text(l.pakkaNew), onTap: widget.onNew),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<PakkaConversation>>(
                future: _list,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) return LoadFailure(snap.error);
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return Center(child: Text(l.pakkaEmpty, style: TextStyle(color: t.muted)));
                  }
                  return ListView(
                    children: [
                      for (final c in list)
                        ListTile(
                          selected: c.id == widget.current,
                          title: Text(c.title.isEmpty ? l.pakkaUntitled : c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: c.updated == null ? null : Text(shortDateTime(l, c.updated!)),
                          trailing: IconButton(
                            tooltip: l.pakkaDelete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(c),
                          ),
                          onTap: () => widget.onOpen(c),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
