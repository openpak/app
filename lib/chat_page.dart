import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// What a message shows: its text, or what kind of message it was, as the
/// website words it.
String chatLine(AppLocalizations l, ChatMessage m) => m.isText
    ? m.body
    : l.chatSpecialMessage('${m.kind[0].toUpperCase()}${m.kind.substring(1)}');

/// Conversations, newest first, as on the website's chat page. A peer who is
/// not a friend any more shows by account id, the same as there.
class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  late Future<(List<Conversation>, Map<String, String>)> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() {
    _data = Future.wait([widget.api.conversations(), widget.api.friends()]).then((r) => (
      r[0] as List<Conversation>,
      {for (final f in r[1] as List<Friend>) f.accountId: f.displayName},
    ));
  });

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.chatTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: () async => _reload(),
        child: FutureBuilder(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return LoadFailure(snap.error);
            final (convs, names) = snap.data!;
            if (convs.isEmpty) {
              return ScrollableMessage(l.chatNoConversations);
            }
            return ListView(
              padding: pagePadding(context),
              children: [
                // One card of rows, as the Account sections are.
                Panel(
                  child: Column(
                    children: [
                      for (final (i, c) in convs.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: Avatar(name: names[c.peer] ?? c.peer),
                          title: Text(names[c.peer] ?? c.peer),
                          subtitle: Text(
                            c.newest.from == c.peer ? chatLine(l, c.newest) : l.chatFromYou(chatLine(l, c.newest)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.muted),
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatPage(api: widget.api, peer: c.peer, name: names[c.peer] ?? c.peer),
                            ));
                            _reload();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One conversation. While it is open it asks for anything newer every few
/// seconds; the recipient's consoles are told by the server, not by this.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.api, required this.peer, required this.name});
  final OpenPakApi api;
  final String peer;
  final String name;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  Timer? _poll;
  Object? _error;
  bool _loaded = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    // ponytail: polling while open; a push or socket when chat outgrows it.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final after = _messages.isEmpty ? 0 : _messages.last.id;
      final more = await widget.api.chatHistory(widget.peer, after: after);
      if (!mounted) return;
      setState(() {
        // A poll and a send can overlap; only what is newer than the list now is added.
        final last = _messages.isEmpty ? 0 : _messages.last.id;
        _messages.addAll(more.where((m) => m.id > last));
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted && !_loaded) setState(() => _error = e);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.sendChat(widget.peer, text);
      _input.clear();
      await _fetch();
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorText(context.l10n, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(
        children: [
          Expanded(
            child: _error != null
                ? LoadFailure(_error)
                : !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(child: Text(l.chatNoMessages, style: TextStyle(color: t.muted)))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[_messages.length - 1 - i];
                      final mine = m.from != widget.peer;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: mine ? t.accentWeak : t.paper2,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(chatLine(l, m)),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: l.chatHint),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    tooltip: l.chatSend,
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
